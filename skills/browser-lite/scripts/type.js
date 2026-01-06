#!/usr/bin/env node
/**
 * type.js - Type text into input element
 */

import browser from './browser.js';

function parseArgs(args) {
  const result = { selector: null, text: '', clearFirst: false, pressEnter: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--selector' && args[i + 1]) result.selector = args[i + 1];
    if (args[i] === '--text' && args[i + 1]) result.text = args[i + 1];
    if (args[i] === '--clear-first' || args[i] === '--clear') result.clearFirst = true;
    if (args[i] === '--enter' || args[i] === '--submit') result.pressEnter = true;
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

    // Find element
    const element = await page.$(opts.selector);
    if (!element) {
      console.log(JSON.stringify({
        status: 'error',
        error: `Element not found: ${opts.selector}`
      }));
      process.exit(1);
    }

    // Get element info
    const elementInfo = await element.evaluate(el => ({
      tag: el.tagName.toLowerCase(),
      type: el.type || null,
      name: el.name || el.id || null
    }));

    // Clear if requested
    if (opts.clearFirst) {
      await element.click({ clickCount: 3 });
      await page.keyboard.press('Backspace');
    }

    // Type
    await element.type(opts.text);

    // Press Enter if requested
    if (opts.pressEnter) {
      await page.keyboard.press('Enter');
      await new Promise(r => setTimeout(r, 500));
    }

    // Check validation state
    const validationState = await element.evaluate(el => {
      if (el.validity) {
        return el.validity.valid ? 'valid' : 'invalid';
      }
      return 'unknown';
    });

    console.log(JSON.stringify({
      status: 'typed',
      selector: opts.selector,
      text_length: opts.text.length,
      element_type: `${elementInfo.tag}${elementInfo.type ? `[${elementInfo.type}]` : ''}`,
      element_name: elementInfo.name,
      validation_state: validationState,
      pressed_enter: opts.pressEnter
    }, null, 2));

  } catch (err) {
    console.log(JSON.stringify({ status: 'error', error: err.message }));
    process.exit(1);
  }
}

main();
