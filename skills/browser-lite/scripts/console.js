#!/usr/bin/env node
/**
 * console.js - Filtered and deduplicated console output
 * Returns summary, saves full log to file
 */

import browser from './browser.js';
import fs from 'fs/promises';
import path from 'path';

function parseArgs(args) {
  const result = {
    level: ['error', 'warn'],
    since: 0, // ms ago
    limit: 10,
    verbose: false
  };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--level' && args[i + 1]) {
      result.level = args[i + 1].split(',');
    }
    if (args[i] === '--since' && args[i + 1]) {
      const val = args[i + 1];
      if (val.endsWith('s')) result.since = parseInt(val) * 1000;
      else if (val.endsWith('m')) result.since = parseInt(val) * 60000;
      else result.since = parseInt(val);
    }
    if (args[i] === '--limit' && args[i + 1]) {
      result.limit = parseInt(args[i + 1]);
    }
    if (args[i] === '--verbose') result.verbose = true;
    if (args[i] === '--all') result.level = ['error', 'warn', 'log', 'info', 'debug'];
  }
  return result;
}

// Patterns to ignore (framework noise)
const IGNORE_PATTERNS = [
  /\[HMR\]/,
  /\[vite\]/i,
  /Download the React DevTools/,
  /Warning: componentWill(Mount|ReceiveProps|Update)/,
  /Compiled successfully/,
  /webpack.*compiled/i,
  /Hot Module Replacement/i,
  /DevTools failed to load/,
  /Autofocus processing/
];

function shouldIgnore(text) {
  return IGNORE_PATTERNS.some(p => p.test(text));
}

function truncateStack(text, maxLines = 4) {
  const lines = text.split('\n');
  if (lines.length > maxLines) {
    return lines.slice(0, maxLines).join('\n') + '\n  ... (truncated)';
  }
  return text;
}

function extractSource(location) {
  if (!location?.url) return 'unknown';
  const filename = location.url.split('/').pop().split('?')[0];
  return `${filename}:${location.lineNumber || '?'}`;
}

function dedupeMessages(messages) {
  const map = new Map();

  for (const msg of messages) {
    // Normalize for deduplication (remove timestamps, specific values)
    const key = `${msg.level}:${msg.text.replace(/\d+/g, 'N')}`;

    if (map.has(key)) {
      const existing = map.get(key);
      existing.count++;
      existing.lastSeen = msg.timestamp;
    } else {
      map.set(key, {
        level: msg.level,
        text: msg.text,
        source: extractSource(msg.location),
        count: 1,
        firstSeen: msg.timestamp,
        lastSeen: msg.timestamp
      });
    }
  }

  return Array.from(map.values());
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  try {
    await browser.connect();
    const messages = browser.getConsoleMessages();

    // Filter by time
    const now = Date.now();
    const cutoff = opts.since > 0 ? now - opts.since : 0;
    let filtered = messages.filter(m => m.timestamp >= cutoff);

    // Filter by level
    filtered = filtered.filter(m => opts.level.includes(m.level));

    // Filter noise
    filtered = filtered.filter(m => !shouldIgnore(m.text));

    // Deduplicate
    const deduped = dedupeMessages(filtered);

    // Sort: errors first, then by count
    deduped.sort((a, b) => {
      if (a.level === 'error' && b.level !== 'error') return -1;
      if (b.level === 'error' && a.level !== 'error') return 1;
      return b.count - a.count;
    });

    // Save full log
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-').substring(0, 19);
    const logPath = path.join('.browser-debug', 'console', `console-${timestamp}.json`);
    await fs.mkdir(path.dirname(logPath), { recursive: true });
    await fs.writeFile(logPath, JSON.stringify(filtered, null, 2));

    // Prepare summary
    const errors = deduped.filter(m => m.level === 'error');
    const warnings = deduped.filter(m => m.level === 'warn');

    const output = {
      summary: {
        total_captured: messages.length,
        after_filter: filtered.length,
        deduplicated: deduped.length,
        errors: errors.length,
        warnings: warnings.length
      },
      critical: errors.slice(0, opts.limit).map(m => ({
        message: truncateStack(m.text, 3),
        source: m.source,
        count: m.count
      })),
      warnings: warnings.slice(0, 5).map(m => ({
        message: m.text.substring(0, 150),
        source: m.source,
        count: m.count
      })),
      full_log: logPath
    };

    if (opts.verbose) {
      output.all = deduped.slice(0, 50);
    }

    console.log(JSON.stringify(output, null, 2));

  } catch (err) {
    console.log(JSON.stringify({ error: err.message }));
    process.exit(1);
  }
}

main();
