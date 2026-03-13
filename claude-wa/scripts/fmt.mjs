// Formats JSON API responses into human-readable text
import { readFileSync } from 'node:fs';

const cmd = process.argv[2];
const raw = readFileSync('/dev/stdin', 'utf8').trim();
if (!raw) { process.exit(0); }
const data = JSON.parse(raw);

function ts(epoch) {
  return new Date(epoch * 1000).toLocaleString('en-GB', {
    day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false,
  });
}

function who(msg) {
  if (msg.fromMe) return 'you';
  return msg.fromName || msg.from?.replace(/@.*/, '') || '?';
}

function chatLabel(c) {
  return c.name || c.chat?.replace('@s.whatsapp.net', '').replace('@g.us', ' (group)') || '?';
}

function pad(str, len) {
  str = String(str);
  return str.length > len ? str.slice(0, len - 1) + '…' : str.padEnd(len);
}

function table(headers, rows, widths) {
  const sep = widths.map(w => '─'.repeat(w)).join('─┼─');
  const hdr = headers.map((h, i) => pad(h, widths[i])).join(' │ ');
  const lines = [hdr, sep];
  for (const row of rows) {
    lines.push(row.map((c, i) => pad(c, widths[i])).join(' │ '));
  }
  return lines.join('\n');
}

if (cmd === 'status') {
  console.log(`Status: ${data.status} | Messages stored: ${data.messages}`);

} else if (cmd === 'chats') {
  if (!data.length) { console.log('No chats yet.'); process.exit(0); }
  const rows = data.map(c => [chatLabel(c), ts(c.ts), c.lastMessage?.slice(0, 50) || '']);
  console.log(table(['Chat', 'Last Active', 'Last Message'], rows, [22, 16, 50]));

} else if (cmd === 'messages') {
  if (!data.length) { console.log('No messages found.'); process.exit(0); }
  const rows = data.map(m => [
    ts(m.ts),
    who(m),
    m.mediaType || 'text',
    m.body || '',
  ]);
  console.log(table(['Time', 'From', 'Type', 'Content'], rows, [16, 15, 8, 60]));

} else if (cmd === 'send') {
  if (data.ok) console.log(`Sent to ${data.name || data.to}`);
  else console.log(`Error: ${data.error}`);

} else if (cmd === 'media') {
  if (data.error) console.log(`Error: ${data.error}`);
  else console.log(`Downloaded: ${data.path}\nMIME type: ${data.mimetype}`);

} else if (cmd === 'transcribe') {
  if (data.error) console.log(`Error: ${data.error}`);
  else console.log(`Transcription (${data.mediaType}):\n${data.text}`);

} else {
  console.log(JSON.stringify(data, null, 2));
}
