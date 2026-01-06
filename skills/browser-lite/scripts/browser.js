/**
 * Browser Manager - Singleton pattern for persistent browser sessions
 * Reuses browser across CLI invocations to avoid 2-3s startup each time
 */

import puppeteer from 'puppeteer';
import fs from 'fs/promises';
import path from 'path';

const STATE_FILE = '.browser-debug/state.json';
const CONSOLE_FILE = '.browser-debug/console-buffer.json';

class BrowserManager {
  constructor() {
    this.browser = null;
    this.page = null;
    this.consoleMessages = [];
    this.networkRequests = [];
  }

  async ensureDebugDir() {
    await fs.mkdir('.browser-debug/screenshots', { recursive: true });
    await fs.mkdir('.browser-debug/console', { recursive: true });
    await fs.mkdir('.browser-debug/network', { recursive: true });
  }

  async loadState() {
    try {
      const data = await fs.readFile(STATE_FILE, 'utf-8');
      return JSON.parse(data);
    } catch {
      return null;
    }
  }

  async saveState(state) {
    await this.ensureDebugDir();
    await fs.writeFile(STATE_FILE, JSON.stringify(state, null, 2));
  }

  async connect() {
    const state = await this.loadState();

    if (state?.wsEndpoint) {
      try {
        this.browser = await puppeteer.connect({
          browserWSEndpoint: state.wsEndpoint
        });
        const pages = await this.browser.pages();
        this.page = pages[0] || await this.browser.newPage();
        await this.setupPageListeners();
        await this.loadConsoleBuffer();
        return { reused: true, url: this.page.url() };
      } catch {
        // Browser died, launch new
      }
    }

    return this.launch();
  }

  async launch() {
    await this.ensureDebugDir();

    this.browser = await puppeteer.launch({
      headless: false, // Visible for debugging
      defaultViewport: { width: 1920, height: 1080 },
      args: ['--no-sandbox', '--disable-setuid-sandbox']
    });

    await this.saveState({
      wsEndpoint: this.browser.wsEndpoint(),
      startedAt: new Date().toISOString()
    });

    this.page = await this.browser.newPage();
    await this.setupPageListeners();

    return { reused: false, url: 'about:blank' };
  }

  async setupPageListeners() {
    // Console message collection
    this.page.on('console', msg => {
      const entry = {
        level: msg.type(),
        text: msg.text(),
        location: msg.location(),
        timestamp: Date.now()
      };
      this.consoleMessages.push(entry);
      // Keep last 1000 messages
      if (this.consoleMessages.length > 1000) {
        this.consoleMessages.shift();
      }
    });

    // Network request collection
    this.page.on('requestfinished', async req => {
      try {
        const response = req.response();
        this.networkRequests.push({
          url: req.url(),
          method: req.method(),
          status: response?.status(),
          timing: req.timing(),
          timestamp: Date.now()
        });
        if (this.networkRequests.length > 500) {
          this.networkRequests.shift();
        }
      } catch {}
    });

    this.page.on('requestfailed', req => {
      this.networkRequests.push({
        url: req.url(),
        method: req.method(),
        status: 0,
        failure: req.failure()?.errorText,
        timestamp: Date.now()
      });
    });
  }

  async loadConsoleBuffer() {
    try {
      const data = await fs.readFile(CONSOLE_FILE, 'utf-8');
      this.consoleMessages = JSON.parse(data);
    } catch {
      this.consoleMessages = [];
    }
  }

  async saveConsoleBuffer() {
    await fs.writeFile(CONSOLE_FILE, JSON.stringify(this.consoleMessages));
  }

  async getPage() {
    if (!this.page) {
      await this.connect();
    }
    return this.page;
  }

  getConsoleMessages() {
    return this.consoleMessages;
  }

  getNetworkRequests() {
    return this.networkRequests;
  }

  async close() {
    if (this.browser) {
      await this.browser.close();
      try {
        await fs.unlink(STATE_FILE);
      } catch {}
    }
  }
}

// Singleton export
const manager = new BrowserManager();
export default manager;
