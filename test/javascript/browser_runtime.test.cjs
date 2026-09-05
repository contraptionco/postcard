const assert = require('node:assert/strict');
const test = require('node:test');
const puppeteer = require('puppeteer');

test('the installed browser renders an Open Graph-sized PNG', async () => {
  const browser = await puppeteer.launch({
    headless: true,
    args: process.env.GROVER_NO_SANDBOX === 'true' ? ['--no-sandbox'] : [],
  });

  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1128, height: 600 });
    await page.setContent('<!doctype html><html><body><h1>Postcard</h1></body></html>');
    const png = Buffer.from(await page.screenshot({ type: 'png' }));

    assert.equal(await page.$eval('h1', (heading) => heading.textContent), 'Postcard');
    assert.deepEqual(png.subarray(0, 8), Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
    assert.equal(png.readUInt32BE(16), 1128);
    assert.equal(png.readUInt32BE(20), 600);
  } finally {
    await browser.close();
  }
});
