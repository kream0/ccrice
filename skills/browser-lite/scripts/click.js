#!/usr/bin/env node
/**
 * click.js - Click element and report result
 */

import browser from './browser.js';

function parseArgs(args) {
  const result = { selector: null, waitAfter: 1000 };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--selector' && args[i + 1]) result.selector = args[i + 1];
    if (args[i] === '--wait-after' && args[i + 1]) result.waitAfter = parseInt(args[i + 1]);
  }
  return result;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (!opts.selector) {
    console.log(JSON.stringify({ error: 'Missing --selector parameter' }));
    process.exit(1);
  }

  try {
    await browser.connect();
    const page = await browser.getPage();

    const urlBefore = page.url();
    const startTime = Date.now();

    // Find element
    const element = await page.$(opts.selector);
    if (!element) {
      console.log(JSON.stringify({
        status: 'error',
        error: `Element not found: ${opts.selector}`,
        url: urlBefore
      }));
      process.exit(1);
    }

    // Get element info before clicking
    const elementInfo = await element.evaluate(el => ({
      text: (el.textContent || el.value || '').trim().substring(0, 50),
      tag: el.tagName.toLowerCase(),
      type: el.type || null
    }));

    // Click
    await element.click();

    // Wait for potential navigation or effects
    await new Promise(r => setTimeout(r, opts.waitAfter));

    const urlAfter = page.url();
    const navigationOccurred = urlBefore !== urlAfter;

    // Check for new console errors
    const messages = browser.getConsoleMessages();
    const errorsAfter = messages.filter(m =>
      m.level === 'error' && m.timestamp > startTime
    ).length;

    await browser.saveConsoleBuffer();

    console.log(JSON.stringify({
      status: 'clicked',
      selector: opts.selector,
      element_text: elementInfo.text,
      element_type: `${elementInfo.tag}${elementInfo.type ? `[${elementInfo.type}]` : ''}`,
      navigation_occurred: navigationOccurred,
      new_url: navigationOccurred ? urlAfter : null,
      console_errors_after: errorsAfter
    }, null, 2));

  } catch (err) {
    console.log(JSON.stringify({ status: 'error', error: err.message }));
    process.exit(1);
  }
}

main();
