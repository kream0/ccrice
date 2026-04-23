import { createServer } from 'node:http';
import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import { createWriteStream, accessSync, readdirSync, readFileSync } from 'node:fs';
import { execFile } from 'node:child_process';
import { join } from 'node:path';
import makeWASocket, {
  useMultiFileAuthState,
  makeCacheableSignalKeyStore,
  DisconnectReason,
  fetchLatestBaileysVersion,
  downloadContentFromMessage,
  isJidBroadcast,
  isJidNewsletter,
  normalizeMessageContent,
  proto,
} from '@whiskeysockets/baileys';
import NodeCache from 'node-cache';
import pino from 'pino';
import qrcode from 'qrcode-terminal';

const PORT = process.env.WA_PORT || 7777;
const DATA_DIR = join(import.meta.dirname, '.data');
const AUTH_DIR = join(DATA_DIR, 'auth');
const MSG_FILE = join(DATA_DIR, 'messages.jsonl');
const CONTACTS_FILE = join(DATA_DIR, 'contacts.json');
const WATERMARKS_FILE = join(DATA_DIR, 'watermarks.json');
const WATCHERS_FILE = process.env.WATCHERS_FILE || join(process.env.HOME, 'fang/watchers.json');
const MEDIA_DIR = join(DATA_DIR, 'media');

const logger = pino({ level: process.env.WA_LOG || 'silent' });

// --- LID-to-phone resolution (uses Baileys' own auth mappings) ---
const lidToPhone = new Map();
try {
  for (const f of readdirSync(AUTH_DIR)) {
    const match = f.match(/^lid-mapping-(\d+)_reverse\.json$/);
    if (match) {
      const phone = JSON.parse(readFileSync(join(AUTH_DIR, f), 'utf8'));
      lidToPhone.set(`${match[1]}@lid`, `${phone}@s.whatsapp.net`);
    }
  }
  console.log(`[lid] loaded ${lidToPhone.size} LID→phone mappings`);
} catch (e) { console.warn('[lid] failed to load mappings:', e.message); }

function resolveLid(jid) {
  if (!jid?.endsWith('@lid')) return jid;
  return lidToPhone.get(jid) || jid;
}

await mkdir(DATA_DIR, { recursive: true });

// --- Contacts map (jid -> name) ---
let contacts = {};
try {
  contacts = JSON.parse(await readFile(join(import.meta.dirname, 'contacts.json'), 'utf8'));
} catch {}
try {
  Object.assign(contacts, JSON.parse(await readFile(CONTACTS_FILE, 'utf8')));
} catch {}

function saveContacts() {
  writeFile(CONTACTS_FILE, JSON.stringify(contacts)).catch(() => {});
}

// --- Per-conversation watermarks (last-read tracking for watched JIDs) ---
let watermarks = {};
try {
  watermarks = JSON.parse(await readFile(WATERMARKS_FILE, 'utf8'));
} catch {}

let watchedJids = new Set();
try {
  const w = JSON.parse(await readFile(WATCHERS_FILE, 'utf8'));
  watchedJids = new Set((w.watchers || []).map(e => e.jid));
} catch {}

function saveWatermarks() {
  writeFile(WATERMARKS_FILE, JSON.stringify(watermarks, null, 2)).catch(() => {});
}

function updateWatermarks(msgs) {
  let changed = false;
  for (const m of msgs) {
    if (!watchedJids.has(m.chat)) continue;
    const current = watermarks[m.chat];
    if (!current || m.ts > current.lastMsgTs) {
      watermarks[m.chat] = {
        lastMsgId: m.id,
        lastMsgTs: m.ts,
        lastFromMe: m.fromMe || false,
      };
      changed = true;
    }
  }
  if (changed) saveWatermarks();
}

function resolveContact(jid) {
  return contacts[jid] || null;
}

// --- Message ring buffer (in-memory, last N messages, persisted as JSONL) ---
const MAX_MSGS = 50000;
let messages = [];
const seenIds = new Set();
try {
  const raw = await readFile(MSG_FILE, 'utf8');
  messages = raw.trim().split('\n').filter(Boolean).map(l => JSON.parse(l));
  if (messages.length > MAX_MSGS) messages = messages.slice(-MAX_MSGS);
  for (const m of messages) if (m.id) seenIds.add(m.id);
} catch {}

let flushTimer;
function pushMessages(msgs, { sort = false } = {}) {
  // Deduplicate by message ID
  const newMsgs = msgs.filter(m => !m.id || !seenIds.has(m.id));
  for (const m of newMsgs) if (m.id) seenIds.add(m.id);
  if (!newMsgs.length) return;
  messages.push(...newMsgs);
  if (sort) messages.sort((a, b) => a.ts - b.ts);
  if (messages.length > MAX_MSGS) messages = messages.slice(-MAX_MSGS);
  clearTimeout(flushTimer);
  flushTimer = setTimeout(flushToDisk, 3000);
}

async function flushToDisk() {
  try {
    await writeFile(MSG_FILE, messages.map(m => JSON.stringify(m)).join('\n') + '\n');
  } catch (e) {
    console.error('flush error:', e.message);
  }
}

// --- Owner JID detection (set after connection, used to detect mis-routed DMs) ---
let ownerPhoneJid = null;  // e.g., "33787280440@s.whatsapp.net"
let ownerLid = null;       // e.g., "162079533199509@lid"

// Reverse lookup: pushName → phone JID for DM re-routing
function reverseContactLookup(pushName) {
  if (!pushName) return null;
  const candidates = new Set();
  for (const [jid, name] of Object.entries(contacts)) {
    if (name === pushName && jid !== ownerPhoneJid && jid !== ownerLid) {
      // Resolve LID entries to phone JIDs
      const resolved = resolveLid(jid);
      if (resolved !== ownerPhoneJid) candidates.add(resolved);
    }
  }
  // Also check watcher JIDs whose contact name starts with pushName
  if (candidates.size === 0) {
    for (const jid of watchedJids) {
      if (jid === ownerPhoneJid || jid.endsWith('@g.us') || jid.endsWith('@lid')) continue;
      const cName = contacts[jid];
      if (cName && pushName.length >= 1 && cName.startsWith(pushName)) candidates.add(jid);
    }
  }
  return candidates.size === 1 ? [...candidates][0] : null; // only return if unambiguous
}

// --- WhatsApp connection ---
let sock = null;
let connectionState = 'disconnected';

async function connectWA() {
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version } = await fetchLatestBaileysVersion();

  const msgRetryCounterCache = new NodeCache({ stdTTL: 600, checkperiod: 120 });

  sock = makeWASocket({
    version,
    auth: {
      creds: state.creds,
      keys: makeCacheableSignalKeyStore(state.keys, logger),
    },
    logger,
    browser: ['WhatsApp-Claude', 'Chrome', '1.0.0'],
    generateHighQualityLinkPreview: false,
    syncFullHistory: false,
    markOnlineOnConnect: false,
    shouldSyncHistoryMessage: ({ syncType }) => {
      // Allow RECENT (reconnect recovery) and ON_DEMAND (explicit fetch)
      // Block FULL and INITIAL_BOOTSTRAP to avoid flooding on re-pair
      return syncType === proto.HistorySync.HistorySyncType.RECENT
          || syncType === proto.HistorySync.HistorySyncType.ON_DEMAND;
    },
    shouldIgnoreJid: (jid) => isJidBroadcast(jid) || isJidNewsletter(jid),
    msgRetryCounterCache,
    maxMsgRetryCount: 5,
    getMessage: async (key) => {
      const msg = messages.find(m => m.id === key.id && m.chat === key.remoteJid);
      return msg ? undefined : undefined;
    },
  });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', (update) => {
    const { connection, lastDisconnect, qr } = update;
    if (qr) {
      console.log('\n┌─ Scan this QR code with WhatsApp ─┐');
      qrcode.generate(qr, { small: true });
      console.log('└───────────────────────────────────┘\n');
    }
    connectionState = connection || connectionState;
    if (connection === 'close') {
      const code = lastDisconnect?.error?.output?.statusCode;
      if (code !== DisconnectReason.loggedOut) {
        console.log('Reconnecting...');
        setTimeout(connectWA, 2000);
      } else {
        console.log('Logged out. Scan QR again.');
        connectionState = 'loggedOut';
      }
    } else if (connection === 'open') {
      console.log('Connected to WhatsApp');
      lastMessageTime = Date.now();

      // Detect owner's JID and LID for DM re-routing
      if (sock.user?.id) {
        const rawId = sock.user.id;
        // sock.user.id can be "162079533199509:4@lid" or "33787280440:4@s.whatsapp.net"
        const num = rawId.split(':')[0].split('@')[0];
        if (rawId.includes('@lid')) {
          ownerLid = `${num}@lid`;
          ownerPhoneJid = lidToPhone.get(ownerLid) || null;
        } else {
          ownerPhoneJid = `${num}@s.whatsapp.net`;
          // Find owner's LID from forward mapping
          try {
            const lidNum = JSON.parse(readFileSync(join(AUTH_DIR, `lid-mapping-${num}.json`), 'utf8'));
            ownerLid = `${lidNum}@lid`;
          } catch {}
        }
        console.log(`[owner] phone=${ownerPhoneJid}, lid=${ownerLid}`);
      }

      // Initialize watermarks for new watched JIDs (fresh pair: start from NOW)
      let wmChanged = false;
      for (const jid of watchedJids) {
        if (!watermarks[jid]) {
          watermarks[jid] = { lastMsgId: null, lastMsgTs: Math.floor(Date.now() / 1000), lastFromMe: false };
          wmChanged = true;
        }
      }
      if (wmChanged) saveWatermarks();

      // After RECENT sync window (20s), fetch history for ALL watched JIDs
      // If a watermark has no cursor (null lastMsgId after re-pair), recover it
      // from the last stored message in messages.jsonl before fetching.
      setTimeout(async () => {
        // Recover null cursors from stored messages
        let recovered = false;
        const nullCursorJids = [...watchedJids].filter(j => watermarks[j] && !watermarks[j].lastMsgId);
        if (nullCursorJids.length > 0) {
          try {
            const stored = await readFile(MSG_FILE, 'utf8');
            const lastPerJid = {};
            for (const line of stored.split('\n')) {
              if (!line.trim()) continue;
              try {
                const msg = JSON.parse(line);
                if (msg.chat && (!lastPerJid[msg.chat] || msg.ts > lastPerJid[msg.chat].ts)) {
                  lastPerJid[msg.chat] = msg;
                }
              } catch {}
            }
            for (const jid of nullCursorJids) {
              const last = lastPerJid[jid];
              if (last) {
                watermarks[jid] = { lastMsgId: last.id, lastMsgTs: last.ts, lastFromMe: last.fromMe || false };
                console.log(`[watermark] recovered cursor for ${jid} from stored msg ${last.id} @ ${new Date(last.ts * 1000).toISOString()}`);
                recovered = true;
              }
            }
            if (recovered) saveWatermarks();
          } catch (e) {
            console.warn(`[watermark] failed to recover cursors from messages.jsonl: ${e.message}`);
          }
        }

        for (const jid of watchedJids) {
          const wm = watermarks[jid];
          if (!wm?.lastMsgId) {
            // No cursor even after recovery attempt — request recent messages without cursor
            try {
              // Use chatModify to mark unread, which triggers WA to send recent messages
              await sock.chatModify({ markRead: false }, jid);
              console.log(`[watermark] no cursor for ${jid}, marked unread to trigger sync`);
            } catch (e) {
              console.warn(`[watermark] mark-unread fallback failed for ${jid}: ${e.message}`);
            }
            continue;
          }
          try {
            const key = { remoteJid: jid, fromMe: wm.lastFromMe, id: wm.lastMsgId };
            await sock.fetchMessageHistory(50, key, wm.lastMsgTs * 1000);
            console.log(`[watermark] requested history for ${jid} since ${new Date(wm.lastMsgTs * 1000).toISOString()}`);
          } catch (e) {
            console.warn(`[watermark] fetch failed for ${jid}: ${e.message}`);
          }
        }
      }, 25000);
    }
  });

  function learnContacts(list) {
    let changed = false;
    for (const c of list) {
      const name = c.notify || c.verifiedName || c.name || c.pushName || null;
      if (name && c.id) { contacts[c.id] = name; changed = true; }
    }
    if (changed) saveContacts();
  }

  sock.ev.on('contacts.upsert', learnContacts);
  sock.ev.on('contacts.update', learnContacts);

  sock.ev.on('messaging-history.set', (data) => {
    console.log(`[history-sync] received: ${data.messages?.length || 0} messages, ${data.contacts?.length || 0} contacts, ${data.chats?.length || 0} chats, isLatest=${data.isLatest}`);

    // Update LID→phone mappings from history sync metadata
    if (data.lidPnMappings?.length) {
      for (const { lid, pn } of data.lidPnMappings) {
        if (lid && pn) {
          const lidJid = lid.endsWith('@lid') ? lid : `${lid}@lid`;
          const pnJid = pn.endsWith('@s.whatsapp.net') ? pn : `${pn}@s.whatsapp.net`;
          if (!lidToPhone.has(lidJid)) {
            lidToPhone.set(lidJid, pnJid);
            console.log(`[history-sync] learned LID mapping: ${lidJid} → ${pnJid}`);
          }
        }
      }
    }

    // Learn DM conversation JIDs from chat metadata (pnJid/lidJid)
    // This helps re-route history-synced DMs that lack pushName/remoteJidAlt.
    const dmPartners = new Map(); // chatId → resolvedPhoneJid
    if (data.chats?.length && ownerPhoneJid) {
      for (const chat of data.chats) {
        const pn = chat.pnJid || chat.phoneNumber;
        const lid = chat.lidJid || chat.accountLid;
        if (pn && pn !== ownerPhoneJid) {
          dmPartners.set(chat.id, pn.endsWith('@s.whatsapp.net') ? pn : `${pn}@s.whatsapp.net`);
        } else if (lid) {
          const resolved = resolveLid(lid.endsWith('@lid') ? lid : `${lid}@lid`);
          if (resolved && resolved !== ownerPhoneJid) {
            dmPartners.set(chat.id, resolved);
          }
        }
      }
      if (dmPartners.size) {
        console.log(`[history-sync] DM partners: ${[...dmPartners.entries()].map(([k,v]) => `${k}→${v}`).join(', ')}`);
      }
    }

    if (data.contacts?.length) learnContacts(data.contacts);
    if (data.messages?.length) {
      // For history-synced messages: inject DM partner context so parseMessages can re-route
      // Tag messages that come from known DM conversations
      for (const m of data.messages) {
        if (m.key && !m.key.fromMe && ownerPhoneJid) {
          const resolved = resolveLid(m.key.remoteJid);
          if (resolved === ownerPhoneJid && dmPartners.size === 1) {
            // Only one DM partner in this batch — attribute to them
            const [, partnerJid] = [...dmPartners.entries()][0];
            m._dmPartnerJid = partnerJid;
          } else if (resolved === ownerPhoneJid && m.pushName) {
            // Multiple partners but we have pushName — reverseContactLookup will handle in parseMessages
          }
        }
      }
      const parsed = parseMessages(data.messages);
      console.log(`[history-sync] parsed ${parsed.length} messages (${data.messages.length - parsed.length} filtered)`);
      if (parsed.length) {
        pushMessages(parsed, { sort: true });
        updateWatermarks(parsed);
      }
    }
  });

  sock.ev.on('messages.upsert', ({ messages: incoming, type }) => {
    lastMessageTime = Date.now();
    console.log(`[messages.upsert] type=${type}, count=${incoming.length}`);
    const parsed = parseMessages(incoming);
    if (parsed.length) {
      pushMessages(parsed);
      updateWatermarks(parsed);
    }
  });
}

function parseMessages(incoming) {
  return incoming
    .filter(m => m.message && !m.key.fromMe || (m.key.fromMe && m.message))
    .map(m => {
      // Unwrap nested message containers via Baileys normalizer
      // Handles: ephemeral, viewOnce (v1/v2/ext), edited, documentWithCaption,
      //          associatedChild, groupStatus (v1/v2)
      let msg = normalizeMessageContent(m.message);

      // Skip protocol/system messages — not user content
      if (msg?.protocolMessage || msg?.senderKeyDistributionMessage ||
          msg?.encReaction || msg?.messageContextInfo && Object.keys(msg).length === 1) {
        return null;
      }
      let body = msg?.conversation || msg?.extendedTextMessage?.text || '';
      let mediaType = null;
      let media = null;
      const extractMedia = (msgObj, dlType) => {
        if (msgObj?.mediaKey) {
          media = {
            mediaKey: Buffer.from(msgObj.mediaKey).toString('base64'),
            directPath: msgObj.directPath,
            url: msgObj.url,
            mimetype: msgObj.mimetype,
            dlType,
          };
        }
      };
      if (msg?.imageMessage)         { mediaType = 'image';    body = msg.imageMessage.caption || ''; extractMedia(msg.imageMessage, 'image'); }
      else if (msg?.videoMessage)    { mediaType = 'video';    body = msg.videoMessage.caption || ''; extractMedia(msg.videoMessage, 'video'); }
      else if (msg?.audioMessage)    { mediaType = msg.audioMessage.ptt ? 'voice' : 'audio'; extractMedia(msg.audioMessage, msg.audioMessage.ptt ? 'ptt' : 'audio'); }
      else if (msg?.documentMessage) { mediaType = 'document'; body = msg.documentMessage.fileName || msg.documentMessage.caption || ''; extractMedia(msg.documentMessage, 'document'); }
      else if (msg?.stickerMessage)  { mediaType = 'sticker'; extractMedia(msg.stickerMessage, 'sticker'); }
      else if (msg?.contactMessage)  { mediaType = 'contact';  body = msg.contactMessage.displayName || ''; }
      else if (msg?.locationMessage) { mediaType = 'location'; body = `${msg.locationMessage.degreesLatitude},${msg.locationMessage.degreesLongitude}`; }
      else if (msg?.liveLocationMessage) { mediaType = 'live_location'; }
      else if (msg?.reactionMessage) { mediaType = 'reaction'; body = msg.reactionMessage.text || ''; }
      else if (msg?.pollCreationMessage || msg?.pollCreationMessageV2 || msg?.pollCreationMessageV3) { mediaType = 'poll'; body = msg.pollCreationMessage?.name || msg.pollCreationMessageV2?.name || msg.pollCreationMessageV3?.name || ''; }
      else if (msg?.ptvMessage)      { mediaType = 'video'; body = msg.ptvMessage.caption || ''; extractMedia(msg.ptvMessage, 'ptv'); }
      else if (msg?.groupInviteMessage) { mediaType = 'invite'; body = msg.groupInviteMessage.groupName || ''; }
      else if (msg?.callLogMessage || msg?.pinInChatMessage || msg?.keepInChatMessage) { return null; }
      else if (!body)                { mediaType = 'unknown'; }
      // Extract reply/quote context from any message type
      const ctxSources = [
        msg?.extendedTextMessage, msg?.imageMessage, msg?.videoMessage,
        msg?.audioMessage, msg?.documentMessage, msg?.stickerMessage,
      ];
      let quotedStanzaId = null;
      let quotedBody = null;
      let quotedParticipant = null;
      for (const src of ctxSources) {
        const ci = src?.contextInfo;
        if (ci?.stanzaId) {
          quotedStanzaId = ci.stanzaId;
          quotedParticipant = ci.participant || null;
          const qm = ci.quotedMessage;
          if (qm) {
            quotedBody = qm.conversation
              || qm.extendedTextMessage?.text
              || qm.imageMessage?.caption
              || qm.videoMessage?.caption
              || qm.documentMessage?.fileName
              || qm.documentMessage?.caption
              || (qm.audioMessage ? '[voice message]' : null)
              || null;
          }
          break;
        }
      }
      // Resolve sender JID — check participant (groups + some linked-device DMs), then remoteJid
      const rawParticipant = m.key.participant || m.participant || null;
      const rawFromJid = rawParticipant || m.key.remoteJid;
      let fromJid = resolveLid(rawFromJid);

      // Resolve @lid JIDs to @s.whatsapp.net using Baileys' auth mappings
      let chatJid = resolveLid(m.key.remoteJid);

      // FIX: Detect mis-routed DMs on linked devices.
      // On linked devices, 1:1 DM messages arrive with remoteJid = owner's own LID,
      // causing them to land in the owner's self-chat. Detect and re-route.
      const isGroup = chatJid?.endsWith('@g.us');
      const isMisroutedDm = !isGroup && !m.key.fromMe && ownerPhoneJid
        && (chatJid === ownerPhoneJid || chatJid === ownerLid);
      if (isMisroutedDm) {
        // Try to recover actual chat partner JID
        let resolvedPartner = null;

        // 1. remoteJidAlt — Baileys-specific field: sender's alternative JID
        //    (LID when addressingMode=pn, PN when addressingMode=lid)
        //    This is the same field Baileys' getKeyAuthor() uses internally.
        const alt = m.key.remoteJidAlt || m.key.participantAlt;
        if (alt) {
          const resolved = resolveLid(alt);
          if (resolved && resolved !== ownerPhoneJid && resolved !== ownerLid) {
            resolvedPartner = resolved;
          }
        }

        // 2. Check peerJid (WebMessageInfo field 39)
        if (!resolvedPartner && m.peerJid) {
          const resolved = resolveLid(m.peerJid);
          if (resolved !== ownerPhoneJid && resolved !== ownerLid) {
            resolvedPartner = resolved;
          }
        }

        // 3. Check participant field (some Baileys paths)
        if (!resolvedPartner && rawParticipant) {
          const resolved = resolveLid(rawParticipant);
          if (resolved !== ownerPhoneJid && resolved !== ownerLid) {
            resolvedPartner = resolved;
          }
        }

        // 4. Reverse lookup pushName in contacts to find the actual JID
        if (!resolvedPartner && m.pushName) {
          resolvedPartner = reverseContactLookup(m.pushName);
        }

        // 5. History-sync injected DM partner (from conversation metadata)
        if (!resolvedPartner && m._dmPartnerJid) {
          resolvedPartner = m._dmPartnerJid;
        }

        if (resolvedPartner) {
          chatJid = resolvedPartner;
          fromJid = resolvedPartner;
          const via = alt ? 'remoteJidAlt' : m.peerJid ? 'peerJid' : rawParticipant ? 'participant' : 'pushName';
          console.log(`[dm-fix] re-routed ${m.key.id} → ${chatJid} via ${via} (pushName=${m.pushName})`);
        } else if (m.pushName) {
          console.warn(`[dm-fix] UNRESOLVED DM from "${m.pushName}": remoteJidAlt=${alt}, key=${JSON.stringify(m.key)}`);
        }
        // No pushName + no alt JID = legitimate self-chat message (phone-synced media) — keep in owner's chat
      }

      if (m.pushName && fromJid && !m.key.fromMe) {
        contacts[fromJid] = m.pushName;
      }
      return {
        id: m.key.id,
        chat: chatJid,
        chatName: resolveContact(chatJid),
        from: fromJid,
        fromName: m.key.fromMe ? null : (m.pushName || resolveContact(fromJid)),
        fromMe: m.key.fromMe || false,
        body,
        mediaType,
        ...(media ? { media } : {}),
        ...(quotedStanzaId ? { quotedStanzaId, quotedBody, quotedParticipant } : {}),
        ts: m.messageTimestamp
          ? typeof m.messageTimestamp === 'number'
            ? m.messageTimestamp
            : Number(m.messageTimestamp)
          : Math.floor(Date.now() / 1000),
      };
    })
    .filter(Boolean);
}

let lastMessageTime = Date.now();


await connectWA();

// Zombie connection watchdog: force reconnect if no messages.upsert for 5 min
setInterval(() => {
  const silentMin = (Date.now() - lastMessageTime) / 60000;
  if (silentMin > 5 && connectionState === 'open') {
    console.warn(`[watchdog] No messages for ${Math.round(silentMin)}min despite open socket. Forcing reconnect.`);
    sock.end(new Error('zombie session detected'));
  }
}, 60_000);



// --- Helpers ---
function json(res, data, status = 200) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

function parseBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString())); }
      catch { reject(new Error('invalid json')); }
    });
  });
}

// Auto-detect cuDNN for GPU-accelerated whisper
function findCudnnDir() {
  // Search common pip/venv locations for nvidia-cudnn libs
  const candidates = [];
  const home = process.env.HOME || '/root';
  // Site-packages patterns: venvs, user pip, system pip
  const globs = [
    join(home, '.local/lib'),
    join(home, '.venv/lib'),
    '/usr/local/lib',
    '/usr/lib',
  ];
  // Also search any venvs in common locations
  try {
    for (const d of readdirSync(home)) {
      const vlib = join(home, d, '.venv/lib');
      try { accessSync(vlib); globs.push(vlib); } catch {}
    }
  } catch {}
  for (const base of globs) {
    try {
      const pyDirs = readdirSync(base).filter(d => d.startsWith('python'));
      for (const py of pyDirs) {
        const cudnnLib = join(base, py, 'site-packages/nvidia/cudnn/lib');
        try { accessSync(join(cudnnLib, 'libcudnn_ops.so.9')); return cudnnLib; } catch {}
      }
    } catch {}
  }
  return null;
}

const CUDNN_DIR = findCudnnDir();
const WHISPER_ENV = CUDNN_DIR
  ? { ...process.env, LD_LIBRARY_PATH: `${CUDNN_DIR}:${process.env.LD_LIBRARY_PATH || ''}` }
  : process.env;

// Mutex to serialize whisper transcriptions (medium uses ~3GB RAM per process)
let _whisperLock = Promise.resolve();
function withWhisperLock(fn) {
  const prev = _whisperLock;
  let releaseFn;
  _whisperLock = new Promise(r => { releaseFn = r; });
  return prev.then(fn).finally(releaseFn);
}

async function downloadToFile(mediaInfo, outPath) {
  await mkdir(MEDIA_DIR, { recursive: true });
  const dlMsg = {
    mediaKey: Buffer.from(mediaInfo.mediaKey, 'base64'),
    directPath: mediaInfo.directPath,
    url: mediaInfo.url,
  };
  const stream = await downloadContentFromMessage(dlMsg, mediaInfo.dlType);
  const ws = createWriteStream(outPath);
  await new Promise((resolve, reject) => {
    stream.on('error', reject);
    ws.on('error', reject);
    ws.on('finish', resolve);
    stream.pipe(ws);
  });
}

function mimeToExt(mimetype) {
  const map = {
    'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif',
    'video/mp4': 'mp4', 'video/3gpp': '3gp',
    'audio/ogg; codecs=opus': 'ogg', 'audio/mpeg': 'mp3', 'audio/mp4': 'm4a', 'audio/aac': 'aac',
    'audio/ogg': 'ogg',
    'application/pdf': 'pdf',
  };
  return map[mimetype] || mimetype?.split('/')?.[1]?.split(';')?.[0] || 'bin';
}

// --- HTTP API ---
const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const path = url.pathname;

  try {
    if (path === '/status') {
      return json(res, { status: connectionState, messages: messages.length });
    }

    if (path === '/chats') {
      const chatMap = new Map();
      for (const m of messages) {
        const existing = chatMap.get(m.chat);
        if (!existing || m.ts > existing.ts) {
          chatMap.set(m.chat, {
            chat: m.chat,
            name: resolveContact(m.chat) || m.chatName || m.fromName,
            lastMessage: m.body,
            ts: m.ts,
          });
        }
      }
      if (sock && connectionState === 'open') {
        for (const [jid, chat] of chatMap) {
          if (jid.endsWith('@g.us') && !contacts[jid]) {
            try {
              const meta = await sock.groupMetadata(jid);
              if (meta?.subject) {
                contacts[jid] = meta.subject;
                chat.name = meta.subject;
              }
            } catch {}
          }
        }
        saveContacts();
      }
      const chats = [...chatMap.values()]
        .map(c => ({ ...c, name: contacts[c.chat] || c.name || null }))
        .sort((a, b) => b.ts - a.ts);
      return json(res, chats);
    }

    if (path === '/contacts') {
      return json(res, contacts);
    }

    if (path === '/watermarks') {
      return json(res, watermarks);
    }

    if (path === '/messages') {
      const chat = url.searchParams.get('chat');
      const since = url.searchParams.get('since');
      const limit = parseInt(url.searchParams.get('limit') || '50', 10);
      const search = url.searchParams.get('search')?.toLowerCase();

      let filtered = messages;
      if (chat) {
        const chatLower = chat.toLowerCase();
        filtered = filtered.filter(m =>
          m.chat.includes(chat) ||
          (contacts[m.chat] || m.chatName || '').toLowerCase().includes(chatLower)
        );
      }
      if (since) {
        const sinceTs = parseSince(since);
        filtered = filtered.filter(m => m.ts >= sinceTs);
      }
      if (search) filtered = filtered.filter(m => m.body.toLowerCase().includes(search));
      filtered = filtered.slice(-limit).map(m => ({
        ...m,
        fromName: m.fromMe ? null : (contacts[m.from] || m.fromName || null),
        chatName: contacts[m.chat] || m.chatName || null,
      }));
      if (chat && filtered.length) updateWatermarks(filtered);
      return json(res, filtered);
    }

    if (path === '/send' && req.method === 'POST') {
      if (!sock || connectionState !== 'open') {
        return json(res, { error: 'not connected' }, 503);
      }
      const body = await parseBody(req);
      if (!body.chat || !body.text) {
        return json(res, { error: 'chat and text required' }, 400);
      }
      let jid = body.chat;
      if (!jid.includes('@')) {
        // Resolve name/number to JID via contacts map
        const chatLower = jid.toLowerCase();
        const match = Object.entries(contacts).find(([k, v]) =>
          v.toLowerCase().includes(chatLower) || k.includes(jid)
        );
        if (match) {
          jid = match[0];
        } else {
          // Fallback: search message history for a matching chat
          const msgMatch = messages.find(m =>
            (m.chatName || '').toLowerCase().includes(chatLower)
          );
          jid = msgMatch ? msgMatch.chat : `${body.chat}@s.whatsapp.net`;
        }
      }
      await sock.sendMessage(jid, { text: body.text });
      return json(res, { ok: true, to: jid, name: contacts[jid] || null });
    }

    // GET /fetch-history?chat=xxx&count=N — request older history from WhatsApp
    if (path === '/fetch-history') {
      if (!sock || connectionState !== 'open') {
        return json(res, { error: 'not connected' }, 503);
      }
      const chatParam = url.searchParams.get('chat');
      const count = parseInt(url.searchParams.get('count') || '100', 10);
      if (!chatParam) return json(res, { error: 'chat required' }, 400);

      // Resolve chat name to JID
      let jid = chatParam;
      if (!jid.includes('@')) {
        const chatLower = jid.toLowerCase();
        const contactMatch = Object.entries(contacts).find(([k, v]) =>
          v.toLowerCase().includes(chatLower) || k.includes(chatParam)
        );
        if (contactMatch) {
          jid = contactMatch[0];
        } else {
          const msgMatch = messages.find(m =>
            (m.chatName || '').toLowerCase().includes(chatLower)
          );
          jid = msgMatch ? msgMatch.chat : `${chatParam}@s.whatsapp.net`;
        }
      }

      // Find oldest known message for this chat as cursor
      const chatMsgs = messages.filter(m => m.chat === jid).sort((a, b) => a.ts - b.ts);
      const oldest = chatMsgs[0];

      let oldestKey, oldestTs;
      if (oldest) {
        oldestKey = { remoteJid: jid, fromMe: oldest.fromMe, id: oldest.id };
        oldestTs = oldest.ts * 1000;
      } else {
        // No messages — use sentinel to get most recent history
        oldestKey = { remoteJid: jid, fromMe: false, id: 'AAAAAAAAAAAAAAAA' };
        oldestTs = Date.now() - (365 * 24 * 3600 * 1000);
      }

      try {
        const sessionId = await sock.fetchMessageHistory(count, oldestKey, oldestTs);
        return json(res, {
          ok: true, jid, name: contacts[jid] || null,
          existingMessages: chatMsgs.length, requested: count, sessionId,
          note: 'History arrives asynchronously — wait a few seconds then check messages',
        });
      } catch (e) {
        return json(res, { error: e.message }, 500);
      }
    }

    if (path === '/media') {
      const id = url.searchParams.get('id');
      if (!id) return json(res, { error: 'id required' }, 400);
      const msg = messages.find(m => m.id === id);
      if (!msg) return json(res, { error: 'message not found' }, 404);
      if (!msg.media) return json(res, { error: 'message has no downloadable media' }, 400);

      const ext = mimeToExt(msg.media.mimetype);
      const outPath = join(MEDIA_DIR, `${id}.${ext}`);
      try {
        await access(outPath);
        return json(res, { path: outPath, mimetype: msg.media.mimetype });
      } catch {}

      await downloadToFile(msg.media, outPath);
      return json(res, { path: outPath, mimetype: msg.media.mimetype });
    }

    if (path === '/transcribe') {
      const id = url.searchParams.get('id');
      if (!id) return json(res, { error: 'id required' }, 400);
      const msg = messages.find(m => m.id === id);
      if (!msg) return json(res, { error: 'message not found' }, 404);
      if (!msg.media) return json(res, { error: 'message has no downloadable media' }, 400);
      if (!['voice', 'audio', 'video'].includes(msg.mediaType)) {
        return json(res, { error: `cannot transcribe ${msg.mediaType} messages` }, 400);
      }

      const ext = mimeToExt(msg.media.mimetype);
      const mediaPath = join(MEDIA_DIR, `${id}.${ext}`);
      try { await access(mediaPath); } catch {
        await downloadToFile(msg.media, mediaPath);
      }

      // Pre-convert to WAV (fast, <2s) so python reads a stable file
      const wavPath = mediaPath.replace(/\.[^.]+$/, ".wav");
      try { await access(wavPath); } catch {
        await new Promise((res, rej) => {
          execFile("ffmpeg", ["-i", mediaPath, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wavPath, "-y", "-loglevel", "error"], { timeout: 30000 }, (e) => e ? rej(e) : res());
        });
      }
      // Serialize whisper calls — each loads ~3GB; concurrent runs cause OOM kills
      const text = await withWhisperLock(() => new Promise((resolve, reject) => {
        const pyCode = [
          "import os",
          "from faster_whisper import WhisperModel",
          "model_name = os.environ.get(\"WA_WHISPER_MODEL\", \"small\")",
          "lang = os.environ.get(\"WA_WHISPER_LANG\", \"\")",
          "device = \"cpu\"",
          "m = WhisperModel(model_name, device=device, compute_type=\"int8\")",
          "kwargs = {\"language\": lang} if lang else {}",
          "segs, _ = m.transcribe(\"" + wavPath + "\", **kwargs)",
          "print(\" \".join(s.text.strip() for s in segs))",
        ].join("\n");
        execFile("python3", ["-c", pyCode], { timeout: 600000, maxBuffer: 10 * 1024 * 1024, env: WHISPER_ENV }, (err, stdout, stderr) => {
          if (err) {
            const detail = stderr ? stderr.trim().split('\n').slice(-3).join(' | ') : '';
            const sig = err.signal ? ` signal=${err.signal}` : '';
            const code = err.code != null ? ` code=${err.code}` : '';
            reject(new Error(`whisper failed:${code}${sig} ${detail || 'no stderr (possible OOM kill)'}`));
          } else resolve(stdout.trim());
        });
      }));
      return json(res, { text, mediaType: msg.mediaType, path: mediaPath });
    }

    if (path === '/export') {
      const chat = url.searchParams.get('chat');
      if (!chat) return json(res, { error: 'chat required' }, 400);
      const exclude = (url.searchParams.get('exclude') || '').split(',').filter(Boolean);
      const include = (url.searchParams.get('include') || '').split(',').filter(Boolean);
      const doTranscribe = url.searchParams.get('transcribe') === '1';
      const since = url.searchParams.get('since');

      const chatLower = chat.toLowerCase();
      let filtered = messages.filter(m =>
        m.chat.includes(chat) ||
        (contacts[m.chat] || m.chatName || '').toLowerCase().includes(chatLower)
      );
      if (since) {
        const sinceTs = parseSince(since);
        filtered = filtered.filter(m => m.ts >= sinceTs);
      }
      if (include.length) {
        filtered = filtered.filter(m => include.includes(m.mediaType) || (include.includes('text') && !m.mediaType));
      }
      if (exclude.length) {
        filtered = filtered.filter(m => !exclude.includes(m.mediaType));
      }
      filtered = filtered.map(m => ({
        ...m,
        fromName: m.fromMe ? null : (contacts[m.from] || m.fromName || null),
        chatName: contacts[m.chat] || m.chatName || null,
      }));

      const transcriptions = {};
      if (doTranscribe) {
        const toTranscribe = filtered.filter(m =>
          m.media && ['voice', 'audio', 'video'].includes(m.mediaType)
        );
        if (toTranscribe.length) {
          await mkdir(MEDIA_DIR, { recursive: true });
          const fileMap = {};
          for (const m of toTranscribe) {
            const ext = mimeToExt(m.media.mimetype);
            const mediaPath = join(MEDIA_DIR, `${m.id}.${ext}`);
            try { await access(mediaPath); } catch {
              await downloadToFile(m.media, mediaPath);
            }
            fileMap[m.id] = mediaPath;
          }
          const scriptPath = join(import.meta.dirname, 'transcribe-batch.py');
          const result = await withWhisperLock(() => new Promise((resolve, reject) => {
            const proc = execFile('python3', [scriptPath], {
              timeout: 600000,
              maxBuffer: 10 * 1024 * 1024,
              env: WHISPER_ENV,
            }, (err, stdout, stderr) => {
              if (err) {
                const detail = stderr ? stderr.trim().split('\n').slice(-3).join(' | ') : '';
                const sig = err.signal ? ` signal=${err.signal}` : '';
                const code = err.code != null ? ` code=${err.code}` : '';
                reject(new Error(`batch whisper failed:${code}${sig} ${detail || 'no stderr (possible OOM kill)'}`));
              } else {
                try { resolve(JSON.parse(stdout)); }
                catch { reject(new Error('batch transcription output parse error')); }
              }
            });
            proc.stdin.write(JSON.stringify(fileMap));
            proc.stdin.end();
          }));
          Object.assign(transcriptions, result);
        }
      }

      const chatName = filtered[0]?.chatName || chat;
      const lines = [];
      lines.push(`# ${chatName}`);
      const stats = { total: filtered.length, transcribed: Object.keys(transcriptions).length };
      if (exclude.length) stats.excluded = exclude.join(', ');
      lines.push(`# ${stats.total} messages${stats.transcribed ? ` | ${stats.transcribed} transcribed` : ''}${stats.excluded ? ` | excluded: ${stats.excluded}` : ''}`);
      lines.push('');
      for (const m of filtered) {
        const date = new Date(m.ts * 1000).toISOString().replace('T', ' ').slice(0, 16);
        const who = m.fromMe ? 'you' : (m.fromName || m.from?.replace(/@.*/, '') || '?');
        if (transcriptions[m.id]) {
          lines.push(`[${date}] ${who}: [${m.mediaType} transcribed] ${transcriptions[m.id]}`);
        } else if (m.mediaType && m.mediaType !== 'reaction' && !m.body) {
          lines.push(`[${date}] ${who}: [${m.mediaType}]`);
        } else if (m.mediaType === 'reaction') {
          lines.push(`[${date}] ${who}: reacted ${m.body}`);
        } else {
          lines.push(`[${date}] ${who}: ${m.body}`);
        }
      }

      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(lines.join('\n') + '\n');
      return;
    }

    json(res, { error: 'not found' }, 404);
  } catch (e) {
    json(res, { error: e.message }, 500);
  }
});

function parseSince(val) {
  if (/^\d+$/.test(val)) return parseInt(val, 10);
  const match = val.match(/^(\d+)([smhd])$/);
  if (!match) return 0;
  const n = parseInt(match[1], 10);
  const unit = { s: 1, m: 60, h: 3600, d: 86400 }[match[2]];
  return Math.floor(Date.now() / 1000) - n * unit;
}

server.requestTimeout = 660000;  // 11min — higher than transcribe timeout
server.headersTimeout = 120000;
server.listen(PORT, '127.0.0.1', () => {
  console.log(`WhatsApp API listening on http://127.0.0.1:${PORT}`);
});

process.on('SIGINT', async () => { await flushToDisk(); process.exit(0); });
process.on('SIGTERM', async () => { await flushToDisk(); process.exit(0); });
