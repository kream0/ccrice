#!/usr/bin/env node
/**
 * evaluate.js - Run JavaScript in page context with truncated output
 */

import browser from './browser.js';
import fs from 'fs/promises';
import path from 'path';

function parseArgs(args) {
  const result = { script: null, verbose: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--script' && args[i + 1]) result.script = args[i + 1];
    if (args[i] === '--verbose') result.verbose = true;
  }
  return result;
}

function truncateValue(value, maxLength = 500) {
  const str = JSON.stringify(value);
  if (str.length > maxLength) {
    return str.substring(0, maxLength) + '... (truncated)';
  }
  return value;
}

function summarizeValue(value) {
  if (value === null) return { type: 'null', value: null };
  if (value === undefined) return { type: 'undefined', value: null };

  const type = typeof value;

  if (type === 'number' || type === 'boolean' || type === 'string') {
    return {
      type,
      value: type === 'string' && value.length > 200
        ? value.substring(0, 200) + '...'
        : value
    };
  }

  if (Array.isArray(value)) {
    return {
      type: 'array',
      length: value.length,
      preview: value.slice(0, 3).map(v => truncateValue(v, 100)),
      value: value.length <= 5 ? value : `[Array(${value.length})]`
    };
  }

  if (type === 'object') {
    const keys = Object.keys(value);
    return {
      type: 'object',
      keys: keys.length,
      preview: keys.slice(0, 5),
      value: keys.length <= 3 ? truncateValue(value, 300) : `{Object with ${keys.length} keys}`
    };
  }

  return { type, value: String(value).substring(0, 100) };
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (!opts.script) {
    console.log(JSON.stringify({ error: 'Missing --script parameter' }));
    process.exit(1);
  }

  try {
    await browser.connect();
    const page = await browser.getPage();

    const startTime = Date.now();

    // Execute script
    const result = await page.evaluate(opts.script);

    const execTime = Date.now() - startTime;
    const summary = summarizeValue(result);

    // Save full result if it's large
    let fullOutputPath = null;
    const fullStr = JSON.stringify(result);
    if (fullStr && fullStr.length > 500) {
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-').substring(0, 19);
      fullOutputPath = path.join('.browser-debug', 'eval', `eval-${timestamp}.json`);
      await fs.mkdir(path.dirname(fullOutputPath), { recursive: true });
      await fs.writeFile(fullOutputPath, JSON.stringify(result, null, 2));
    }

    const output = {
      result: summary.value,
      type: summary.type,
      execution_time_ms: execTime
    };

    if (summary.length !== undefined) output.length = summary.length;
    if (summary.keys !== undefined) output.keys = summary.keys;
    if (summary.preview) output.preview = summary.preview;
    if (fullOutputPath) output.full_output = fullOutputPath;

    if (opts.verbose && result !== undefined) {
      output.raw = result;
    }

    console.log(JSON.stringify(output, null, 2));

  } catch (err) {
    console.log(JSON.stringify({
      status: 'error',
      error: err.message,
      script: opts.script.substring(0, 100)
    }));
    process.exit(1);
  }
}

main();
