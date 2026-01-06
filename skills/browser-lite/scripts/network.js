#!/usr/bin/env node
/**
 * network.js - Network request summary with filtering
 */

import browser from './browser.js';
import fs from 'fs/promises';
import path from 'path';

function parseArgs(args) {
  const result = {
    since: 0,
    failedOnly: false,
    limit: 20,
    verbose: false
  };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--since' && args[i + 1]) {
      const val = args[i + 1];
      if (val.endsWith('s')) result.since = parseInt(val) * 1000;
      else if (val.endsWith('m')) result.since = parseInt(val) * 60000;
      else result.since = parseInt(val);
    }
    if (args[i] === '--failed-only' || args[i] === '--failed') result.failedOnly = true;
    if (args[i] === '--limit' && args[i + 1]) result.limit = parseInt(args[i + 1]);
    if (args[i] === '--verbose') result.verbose = true;
  }
  return result;
}

function shortenUrl(url) {
  try {
    const u = new URL(url);
    return u.pathname + (u.search ? '?' + u.search.substring(0, 20) : '');
  } catch {
    return url.substring(0, 60);
  }
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  try {
    await browser.connect();
    const requests = browser.getNetworkRequests();

    // Filter by time
    const now = Date.now();
    const cutoff = opts.since > 0 ? now - opts.since : 0;
    let filtered = requests.filter(r => r.timestamp >= cutoff);

    // Categorize
    const failed = filtered.filter(r => r.status === 0 || r.status >= 400);
    const slow = filtered.filter(r => r.timing?.receiveHeadersEnd > 2000);

    if (opts.failedOnly) {
      filtered = failed;
    }

    // Save full log
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-').substring(0, 19);
    const logPath = path.join('.browser-debug', 'network', `network-${timestamp}.json`);
    await fs.mkdir(path.dirname(logPath), { recursive: true });
    await fs.writeFile(logPath, JSON.stringify(filtered, null, 2));

    const output = {
      summary: {
        total_requests: requests.length,
        in_window: filtered.length,
        failed: failed.length,
        slow: slow.length
      },
      failed: failed.slice(0, 10).map(r => ({
        url: shortenUrl(r.url),
        method: r.method,
        status: r.status || 'failed',
        error: r.failure || null
      })),
      slow: slow.slice(0, 5).map(r => ({
        url: shortenUrl(r.url),
        duration_ms: Math.round(r.timing?.receiveHeadersEnd || 0),
        status: r.status
      })),
      full_log: logPath
    };

    if (opts.verbose) {
      output.recent = filtered.slice(-opts.limit).map(r => ({
        url: shortenUrl(r.url),
        method: r.method,
        status: r.status
      }));
    }

    console.log(JSON.stringify(output, null, 2));

  } catch (err) {
    console.log(JSON.stringify({ error: err.message }));
    process.exit(1);
  }
}

main();
