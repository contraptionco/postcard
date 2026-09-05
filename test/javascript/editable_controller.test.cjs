const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { before, after, test } = require('node:test');

const root = path.join(__dirname, '../..');
let browser;

before(async () => {
  const { default: puppeteer } = await import('puppeteer');
  browser = await puppeteer.launch({
    headless: true,
    args: process.env.GROVER_NO_SANDBOX === 'true' ? ['--no-sandbox'] : [],
  });
});

after(async () => {
  if (browser) await browser.close();
});

// Use the same vendored ES modules as Rails' import map. Request interception
// serves this tiny editor document without a server or access to the network.
async function editorPage(t, title = '') {
  const page = await browser.newPage();
  t.after(() => page.close());
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  t.after(() => assert.deepEqual(errors, [], 'the editor must not raise browser errors'));

  const escapedTitle = title.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  const html = `<!doctype html><html><head>
    <script type="importmap">{"imports":{"@hotwired/stimulus":"/stimulus.js","lodash.debounce":"/debounce.js"}}</script>
    </head><body><form id="post-form">
      <div id="editor" data-controller="editable">
        <h1 id="title" contenteditable data-editable-target="content"
          data-action="keyup->editable#changed keyup->editable#debouncedSave"></h1>
        <input id="post-title" type="hidden" data-editable-target="input" value="${escapedTitle}">
      </div>
    </form><script type="module">
      import { Application } from '@hotwired/stimulus';
      import EditableController from '/editable_controller.js';
      window.submittedTitles = [];
      document.querySelector('form').addEventListener('submit', (event) => {
        event.preventDefault();
        window.submittedTitles.push(document.querySelector('#post-title').value);
      });
      window.application = Application.start();
      window.application.register('editable', EditableController);
    </script></body></html>`;
  const responses = new Map([
    ['https://postcard.test/', { contentType: 'text/html', body: html }],
    ['https://postcard.test/stimulus.js', { contentType: 'text/javascript', body: readFileSync(path.join(root, 'vendor/javascript/@hotwired--stimulus.js'), 'utf8') }],
    ['https://postcard.test/debounce.js', { contentType: 'text/javascript', body: readFileSync(path.join(root, 'vendor/javascript/lodash.debounce.js'), 'utf8') }],
    ['https://postcard.test/editable_controller.js', { contentType: 'text/javascript', body: readFileSync(path.join(root, 'app/javascript/controllers/editable_controller.js'), 'utf8') }],
  ]);
  await page.setRequestInterception(true);
  page.on('request', (request) => {
    const response = responses.get(request.url());
    if (response) return request.respond(response);
    return request.abort();
  });
  await page.goto('https://postcard.test/');
  await page.waitForFunction(() => window.application?.getControllerForElementAndIdentifier(document.querySelector('#editor'), 'editable'));
  return page;
}

async function setConnected(page, connected) {
  await page.evaluate((connected) => {
    const editor = document.querySelector('#editor');
    if (connected) editor.setAttribute('data-controller', 'editable');
    else editor.removeAttribute('data-controller');
  }, connected);
  await page.waitForFunction((connected) => {
    return Boolean(window.application.getControllerForElementAndIdentifier(document.querySelector('#editor'), 'editable')) === connected;
  }, {}, connected);
}

// Count calls to the native event method, rather than inspecting or replacing
// the controller, so a leaked listener is observable after a real reconnect.
async function enterHandlers(page) {
  return page.evaluate(() => {
    const event = new KeyboardEvent('keypress', { key: 'Enter', which: 13, keyCode: 13, bubbles: true, cancelable: true });
    let calls = 0;
    const preventDefault = event.preventDefault.bind(event);
    event.preventDefault = () => { calls += 1; preventDefault(); };
    document.querySelector('#title').dispatchEvent(event);
    return { calls, prevented: event.defaultPrevented };
  });
}

test('saved titles render literally, including HTML-looking text', async (t) => {
  const title = '<em>hello</em><img src="/unexpected" onerror="window.titleExecuted=true">';
  const page = await editorPage(t, title);
  assert.deepEqual(await page.$eval('#title', (element) => ({ text: element.textContent, children: element.children.length })), { text: title, children: 0 });
  assert.equal(await page.evaluate(() => Boolean(window.titleExecuted)), false);
});

test('typing updates the title, Enter stays on one line, and autosave submits the latest text once', async (t) => {
  const page = await editorPage(t, 'Hello');
  await page.focus('#title');
  await page.keyboard.press('End');
  await page.keyboard.type(' postcard');
  await page.keyboard.press('Enter');
  await page.keyboard.type('!');
  assert.equal(await page.$eval('#title', (element) => element.textContent), 'Hello postcard!');
  assert.equal(await page.$eval('#post-title', (element) => element.value), 'Hello postcard!');
  await page.waitForFunction(() => window.submittedTitles.length === 1);
  assert.deepEqual(await page.evaluate(() => window.submittedTitles), ['Hello postcard!']);

  await page.$eval('#title', (element) => {
    element.textContent = 'One\r\nTwo\nThree';
    element.dispatchEvent(new KeyboardEvent('keyup', { key: 'v', bubbles: true }));
  });
  assert.equal(await page.$eval('#post-title', (element) => element.value), 'OneTwoThree');
  await page.waitForFunction(() => window.submittedTitles.length === 2);
  assert.deepEqual(await page.evaluate(() => window.submittedTitles), ['Hello postcard!', 'OneTwoThree']);
});

test('disconnect removes the Enter listener and reconnects attach it only once', async (t) => {
  const page = await editorPage(t, 'Hello');
  assert.deepEqual(await enterHandlers(page), { calls: 1, prevented: true });
  for (let cycle = 0; cycle < 3; cycle += 1) {
    await setConnected(page, false);
    assert.deepEqual(await enterHandlers(page), { calls: 0, prevented: false });
    await setConnected(page, true);
    assert.deepEqual(await enterHandlers(page), { calls: 1, prevented: true });
  }
});

test('disconnect cancels pending autosave while a reconnected editor can still save', async (t) => {
  const page = await editorPage(t);
  await page.type('#title', 'Abandoned');
  await setConnected(page, false);
  await new Promise((resolve) => setTimeout(resolve, 1700));
  assert.deepEqual(await page.evaluate(() => window.submittedTitles), []);

  await setConnected(page, true);
  await page.focus('#title');
  await page.keyboard.press('End');
  await page.keyboard.type(' revision');
  await page.waitForFunction(() => window.submittedTitles.length === 1);
  assert.deepEqual(await page.evaluate(() => window.submittedTitles), ['Abandoned revision']);
});
