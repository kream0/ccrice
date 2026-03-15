import { createServer } from 'node:http';
import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import { createWriteStream, accessSync, readdirSync } from 'node:fs';
import { execFile } from 'node:child_process';
import { join } from 'node:path';
import makeWASocket, {
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
  downloadContentFromMessage,
} from '@whiskeysockets/baileys';
import pino from 'pino';
import qrcode from 'qrcode-terminal';

const PORT = process.env.WA_PORT || 7777;
const DATA_DIR = join(import.meta.dirname, '.data');
const AUTH_DIR = join(DATA_DIR, 'auth');
const MSG_FILE = join(DATA_DIR, 'messages.jsonl');
const CONTACTS_FILE = join(DATA_DIR, 'contacts.json');
const MEDIA_DIR = join(DATA_DIR, 'media');

const logger = pino({ level: process.env.WA_LOG || 'silent' });

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

// --- WhatsApp connection ---
let sock = null;
let connectionState = 'disconnected';

async function connectWA() {
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version } = await fetchLatestBaileysVersion();

  sock = makeWASocket({
    version,
    auth: state,
    logger,
    browser: ['WhatsApp-Claude', 'Chrome', '1.0.0'],
    generateHighQualityLinkPreview: false,
    syncFullHistory: true,
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
    console.log(`[history-sync] received: ${data.messages?.length || 0} messages, ${data.contacts?.length || 0} contacts, isLatest=${data.isLatest}`);
    if (data.contacts?.length) learnContacts(data.contacts);
    if (data.messages?.length) {
      const parsed = parseMessages(data.messages);
      console.log(`[history-sync] parsed ${parsed.length} messages (${data.messages.length - parsed.length} filtered)`);
      if (parsed.length) pushMessages(parsed, { sort: true });
    }
  });

  sock.ev.on('messages.upsert', ({ messages: incoming, type }) => {
    const parsed = parseMessages(incoming);
    if (parsed.length) pushMessages(parsed);
  });
}

function parseMessages(incoming) {
  return incoming
    .filter(m => m.message && !m.key.fromMe || (m.key.fromMe && m.message))
    .map(m => {
      const msg = m.message;
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
      else if (!body)                { mediaType = 'unknown'; }
      const fromJid = m.key.participant || m.key.remoteJid;
      if (m.pushName && fromJid && !m.key.fromMe) {
        contacts[fromJid] = m.pushName;
      }
      return {
        id: m.key.id,
        chat: m.key.remoteJid,
        chatName: resolveContact(m.key.remoteJid),
        from: fromJid,
        fromName: m.key.fromMe ? null : (m.pushName || resolveContact(fromJid)),
        fromMe: m.key.fromMe || false,
        body,
        mediaType,
        ...(media ? { media } : {}),
        ts: m.messageTimestamp
          ? typeof m.messageTimestamp === 'number'
            ? m.messageTimestamp
            : Number(m.messageTimestamp)
          : Math.floor(Date.now() / 1000),
      };
    });
}

await connectWA();

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

      const scriptPath = join(import.meta.dirname, 'transcribe.sh');
      const text = await new Promise((resolve, reject) => {
        execFile('bash', [scriptPath, mediaPath], { timeout: 300000, env: WHISPER_ENV }, (err, stdout, stderr) => {
          if (err) reject(new Error(stderr || err.message));
          else resolve(stdout.trim());
        });
      });
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
          const result = await new Promise((resolve, reject) => {
            const proc = execFile('python3', [scriptPath], {
              timeout: 600000,
              maxBuffer: 10 * 1024 * 1024,
              env: WHISPER_ENV,
            }, (err, stdout, stderr) => {
              if (err) reject(new Error(stderr || err.message));
              else {
                try { resolve(JSON.parse(stdout)); }
                catch { reject(new Error('batch transcription output parse error')); }
              }
            });
            proc.stdin.write(JSON.stringify(fileMap));
            proc.stdin.end();
          });
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

server.listen(PORT, '127.0.0.1', () => {
  console.log(`WhatsApp API listening on http://127.0.0.1:${PORT}`);
});

process.on('SIGINT', async () => { await flushToDisk(); process.exit(0); });
process.on('SIGTERM', async () => { await flushToDisk(); process.exit(0); });
