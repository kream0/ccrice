#!/usr/bin/env node
/**
 * screenshot.js - Take screenshot with text description (not base64)
 * Saves PNG to file, returns DOM-based description for context efficiency
 */

import browser from './browser.js';
import fs from 'fs/promises';
import path from 'path';

function parseArgs(args) {
  const result = { name: 'screenshot', selector: null, fullPage: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--name' && args[i + 1]) result.name = args[i + 1];
    if (args[i] === '--selector' && args[i + 1]) result.selector = args[i + 1];
    if (args[i] === '--full-page') result.fullPage = true;
  }
  return result;
}

async function describePageDOM(page) {
  return await page.evaluate(() => {
    const result = {
      title: document.title,
      url: location.href,
      headings: [],
      forms: [],
      buttons: [],
      links: [],
      errors: [],
      images: [],
      layout: []
    };

    // Visible check helper
    const isVisible = el => {
      if (!el.offsetParent && el.style?.display !== 'fixed') return false;
      const rect = el.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    };

    // Headings (first 3)
    document.querySelectorAll('h1, h2, h3').forEach((el, i) => {
      if (i < 3 && isVisible(el)) {
        result.headings.push(el.textContent.trim().substring(0, 60));
      }
    });

    // Form inputs
    document.querySelectorAll('input:not([type="hidden"]), select, textarea').forEach(el => {
      if (isVisible(el)) {
        result.forms.push({
          type: el.tagName.toLowerCase() + (el.type ? `[${el.type}]` : ''),
          id: el.id || el.name || el.placeholder || null,
          hasValue: !!el.value,
          required: el.required
        });
      }
    });

    // Buttons
    document.querySelectorAll('button, [role="button"], input[type="submit"], input[type="button"]').forEach(el => {
      if (isVisible(el)) {
        const text = (el.textContent || el.value || '').trim().substring(0, 30);
        if (text) result.buttons.push(text);
      }
    });

    // Error messages (common patterns)
    const errorSelectors = '.error, .alert-danger, .alert-error, [role="alert"], .invalid-feedback, .form-error, .field-error, .text-danger, .text-red-500, .text-red-600';
    document.querySelectorAll(errorSelectors).forEach(el => {
      if (isVisible(el) && el.textContent.trim()) {
        result.errors.push(el.textContent.trim().substring(0, 100));
      }
    });

    // Layout detection
    if (document.querySelector('header, [role="banner"], nav')) result.layout.push('header');
    if (document.querySelector('aside, [role="complementary"]')) result.layout.push('sidebar');
    if (document.querySelector('footer, [role="contentinfo"]')) result.layout.push('footer');
    if (document.querySelector('dialog[open], .modal.show, [role="dialog"]')) result.layout.push('modal-open');

    // Loading states
    if (document.querySelector('.loading, .spinner, [aria-busy="true"], .skeleton')) {
      result.layout.push('loading-indicator');
    }

    return result;
  });
}

function generateDescription(dom) {
  const parts = [];

  // Title/URL
  if (dom.title) parts.push(`Page: "${dom.title}"`);

  // Headings
  if (dom.headings.length) {
    parts.push(`Headings: ${dom.headings.slice(0, 2).join(', ')}`);
  }

  // Layout
  if (dom.layout.length) {
    parts.push(`Layout: ${dom.layout.join(', ')}`);
  }

  // Forms
  if (dom.forms.length) {
    const formDesc = dom.forms.slice(0, 5).map(f => f.id || f.type).join(', ');
    parts.push(`Form inputs (${dom.forms.length}): ${formDesc}`);
  }

  // Buttons
  if (dom.buttons.length) {
    parts.push(`Buttons: ${dom.buttons.slice(0, 4).join(', ')}`);
  }

  // ERRORS - highlighted
  if (dom.errors.length) {
    parts.push(`ERRORS VISIBLE: "${dom.errors[0]}"`);
  }

  return parts.join('. ') + '.';
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  try {
    const { reused } = await browser.connect();
    const page = await browser.getPage();

    // Generate filename
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-').substring(0, 19);
    const filename = `${opts.name}-${timestamp}.png`;
    const filepath = path.join('.browser-debug', 'screenshots', filename);

    // Take screenshot
    const screenshotOpts = { path: filepath, fullPage: opts.fullPage };
    if (opts.selector) {
      const element = await page.$(opts.selector);
      if (element) {
        await element.screenshot(screenshotOpts);
      } else {
        console.log(JSON.stringify({
          error: `Selector not found: ${opts.selector}`,
          url: page.url()
        }));
        process.exit(1);
      }
    } else {
      await page.screenshot(screenshotOpts);
    }

    // Get DOM description
    const dom = await describePageDOM(page);
    const description = generateDescription(dom);

    // Save console buffer for later retrieval
    await browser.saveConsoleBuffer();

    // Output minimal JSON
    console.log(JSON.stringify({
      saved: filepath,
      url: dom.url,
      description: description,
      elements: {
        forms: dom.forms.length,
        buttons: dom.buttons.length,
        errors: dom.errors.length
      },
      actionable: dom.errors.length > 0 ? `Error visible: "${dom.errors[0]}"` : null,
      browser_reused: reused
    }, null, 2));

  } catch (err) {
    console.log(JSON.stringify({ error: err.message }));
    process.exit(1);
  }
}

main();
