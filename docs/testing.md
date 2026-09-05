# Testing Postcard

The Rails suite exercises requests, persisted records, background jobs, and rendered email. Run it in both `APP_MODE=SOLO` and `APP_MODE=MULTIUSER`: hosting, subscriber approval, email addressing, and account boundaries differ between the modes.

## Run the suite

Install the dependencies listed in the README, then run:

```sh
bundle install
npm ci
RAILS_ENV=test bin/rails db:prepare
APP_MODE=SOLO COVERAGE=1 bin/test
APP_MODE=MULTIUSER COVERAGE=1 bin/test
npm test
```

Use a dedicated test database. Rails uses `postcard_test` by default, but an exported `DATABASE_URL` takes precedence. Do not point tests at a development or production database. Test configuration uses local attachment storage and the test adapters for Action Mailer and Active Job.

For a focused run, pass a file or a line number:

```sh
APP_MODE=MULTIUSER bin/test test/controllers/post_publishing_flow_test.rb
APP_MODE=SOLO bin/test test/integration/newsletter_delivery_test.rb
node --test test/javascript/editable_controller.test.cjs
```

The JavaScript tests launch Puppeteer's Chrome and use the actual Stimulus controller and vendored dependencies. They need no running Rails server, compiled assets, or external website. `npm ci` installs the browser through Puppeteer; if browser downloading was disabled during installation, run `npx puppeteer browsers install chrome` before testing. Set `PUPPETEER_EXECUTABLE_PATH` to use an existing compatible Chrome installation.

## What the regression tests protect

| Area | Contracts checked |
| --- | --- |
| Publishing | Blank drafts, incomplete saves, Turbo autosave, review, valid and invalid publication, published edits, repeated publish requests, draft deletion, and published archival |
| Account boundaries | Guest and foreign-account requests cannot read or mutate another account's drafts, subscriber imports, or exports |
| Public discovery | Public versus hidden, unlisted, draft, and archived posts; empty archives; valid sitemap entries; `llms.txt` visibility |
| Newsletter delivery | Rendered subject, sender, reply-to, author and custom-domain links, unsubscribe token, recipient selection, delivery history, and consent changes while a job is queued |
| CSV imports | Approval at enqueue and execution, normalized addresses, duplicate imports, and preservation of existing unsubscribe and verification choices |
| Browser editing | Literal title text, input autosave, Enter handling, reconnect cleanup, and cancellation of pending saves after disconnect |

These supplement the existing domain verification, authentication, account update, account deletion, and configuration tests. They do not prove retry-safe newsletter delivery after partial failure, live provider behavior, payment processing, or browser compatibility beyond Chrome.

## Coverage

`COVERAGE=1` produces HTML and JSON reports in `coverage/SOLO/` or `coverage/MULTIUSER/`. Open the corresponding `index.html` to inspect line and branch coverage. CI uploads the reports produced during the run as the `rails-coverage` artifact, including when a test fails. Coverage files are ignored by Git.

Each invocation replaces its mode's report; focused runs do not combine with old results. Run `bin/test` without arguments in both modes for a complete report. This entry point starts coverage before Rails test preparation can load application code; starting coverage only in `test_helper` can miss boot-loaded models. The reports include unloaded Ruby files under `app/` and `lib/`, so untouched code remains visible. Coverage measures Ruby execution; the Chrome assertions run separately. There is no percentage gate: useful assertions and regressions take priority over raising a number.

## Add a regression

- Start with the smallest request, job, model, or browser test that fails for the reported behavior. Assert the visible response and persisted state, including rejected requests that must not change records or enqueue work.
- Use real test mail delivery when email content matters. Inspect the rendered URLs and the actual recipients; a mocked mailer method cannot verify either.
- Stub external services at their boundary. WebMock blocks unexpected HTTP requests in the Rails suite, including localhost. Add an explicit, narrowly matched stub for each expected request. The mail tests stub the stylesheet fetched by Premailer while keeping real template rendering.
- Keep tests independent. Restore any changed global configuration, clear job and mail queues, use a fixed clock for time-sensitive behavior, and avoid depending on execution order.
- Run both boot modes after changing shared behavior. A test that temporarily changes a configuration flag does not replace booting the suite in each mode.
