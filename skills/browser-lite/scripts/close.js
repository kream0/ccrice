#!/usr/bin/env node
/**
 * close.js - Close browser and clean up state
 */

import browser from './browser.js';

async function main() {
  try {
    await browser.connect();
    await browser.close();
    console.log(JSON.stringify({
      status: 'closed',
      message: 'Browser closed and state cleaned up'
    }));
  } catch (err) {
    console.log(JSON.stringify({
      status: 'already_closed',
      message: 'No browser was running'
    }));
  }
}

main();
