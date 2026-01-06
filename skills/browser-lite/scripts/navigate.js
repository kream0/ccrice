#!/usr/bin/env node
/**
 * navigate.js - Navigate to URL and wait for load
 */

import browser from './browser.js';

function parseArgs(args) {
  const result = {
    url: null,
    waitFor: null,
    timeout: 30000
  };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--url' && args[i + 1]) result.url = args[i + 1];
    if (args[i] === '--wait-for' && args[i + 1]) result.waitFor = args[i + 1];
    if (args[i] === '--timeout' && args[i + 1]) result.timeout = parseInt(args[i + 1]);
  }
  return result;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (!opts.url) {
    console.log(JSON.stringify({ error: 'Missing --url parameter' }));
    process.exit(1);
  }

  try {
    const { reused } = await browser.connect();
    const page = await browser.getPage();

    const startTime = Date.now();
    await page.goto(opts.url, {
      waitUntil: 'networkidle2',
      timeout: opts.timeout
    });

    let waitResult = null;
    if (opts.waitFor) {
      try {
        await page.waitForSelector(opts.waitFor, { timeout: opts.timeout });
        waitResult = 'found';
      } catch {
        waitResult = 'timeout';
      }
    }

    const loadTime = Date.now() - startTime;
    const title = await page.title();

    // Quick console check
    const messages = browser.getConsoleMessages();
    const recentErrors = messages.filter(m =>
      m.level === 'error' && m.timestamp > startTime
    ).length;

    // Quick network check
    const requests = browser.getNetworkRequests();
    const failedRequests = requests.filter(r =>
      r.timestamp > startTime && (r.status === 0 || r.status >= 400)
    ).length;

    await browser.saveConsoleBuffer();

    console.log(JSON.stringify({
      status: 'success',
      url: opts.url,
      title: title,
      load_time_ms: loadTime,
      wait_element: opts.waitFor ? `${opts.waitFor} (${waitResult})` : null,
      console_errors: recentErrors,
      network_failed: failedRequests,
      browser_reused: reused
    }, null, 2));

  } catch (err) {
    console.log(JSON.stringify({
      status: 'error',
      url: opts.url,
      error: err.message
    }));
    process.exit(1);
  }
}

main();
