const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const puppeteer = require('puppeteer');

test('the bundled editor preserves formatting and sanitizes pasted attachment attributes', async () => {
  const trixGem = execFileSync('bundle', ['show', 'action_text-trix'], { encoding: 'utf8' }).trim();
  const actionTextGem = execFileSync('bundle', ['show', 'actiontext'], { encoding: 'utf8' }).trim();
  const moduleUrl = (file) => `data:text/javascript;base64,${readFileSync(file).toString('base64')}`;
  const browser = await puppeteer.launch({
    headless: true,
    args: process.env.GROVER_NO_SANDBOX === 'true' ? ['--no-sandbox'] : [],
  });

  try {
    const page = await browser.newPage();
    const imports = {
      trix: moduleUrl(path.join(trixGem, 'app/assets/javascripts/trix.js')),
      '@rails/actiontext': moduleUrl(path.join(actionTextGem, 'app/assets/javascripts/actiontext.js')),
      '@rails/activestorage': moduleUrl(path.join(__dirname, '../../vendor/javascript/@rails--activestorage.js')),
    };
    await page.setContent(`<!doctype html><html><head><script type="importmap">${JSON.stringify({ imports })}</script></head><body><input id="content" type="hidden"><trix-editor input="content"></trix-editor></body></html>`);
    await page.evaluate(async (url) => { await import(url); }, moduleUrl(path.join(__dirname, '../../app/javascript/dashboard.js')));
    await page.waitForFunction(() => document.querySelector('trix-editor').editor);
    await page.waitForSelector('[data-trix-attribute="heading2"]');

    const result = await page.evaluate(() => {
      const editor = document.querySelector('trix-editor').editor;
      editor.insertHTML('<strong>A postcard</strong> <a href="https://example.com/story">Read more</a>');
      editor.insertHTML('<span data-trix-attachment="{}" data-trix-attributes=\'{"href":"javascript:window.__postcardXss=1"}\'>Malicious link</span>');
      return document.querySelector('#content').value;
    });

    assert.match(result, /<strong>A postcard<\/strong>/);
    assert.match(result, /href="https:\/\/example.com\/story"/);
    assert.match(result, /Malicious link/);
    assert.doesNotMatch(result, /javascript:|__postcardXss/i);
  } finally {
    await browser.close();
  }
});
