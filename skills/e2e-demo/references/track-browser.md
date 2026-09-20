# Track A: browser feature

## Mode: verify-only (default) or coverage

- Verify-only: drive the running app with the project's installed test
  framework library, from a scratch script outside the project tree. No file
  under the project is created, edited or staged.
- Coverage: add or extend a real, permanent E2E test. Only when the user asked
  for lasting coverage on their own work. On someone else's branch or PR:
  verify-only unless explicitly asked to contribute coverage.

Unclear which: ask.

## A1a: coverage mode

Find the project's E2E conventions first (test directory README, CLAUDE.md
section) and follow them: existing auth and data fixtures, the data-seeding
pattern, any test-description annotation used for QA reports (populate it if
present, do not invent one).

- Assert against persisted state (DB row, API response), not toasts or badges.
- Seed real data through the project's own path (API fixture, factory).
- Extend an existing test of the flow instead of duplicating it.
- One test per demo (or a short, tightly related pair); one video per test.
- Run the project's type-check and lint on the test before running it.

Video: use the project's own switch for video capture (an env var read by the
test config, a run flag). None: enable it in the test config for this run
(Playwright: `use: { video: 'on' }`) and revert afterwards.

Screenshots: the project's own report publisher when it has one, otherwise
the framework's HTML report and on-step screenshots.

## A1b: verify-only mode

Scratch script in a temp location (never in `apps/e2e`, `cypress/`, `tests/`
or wherever the suite lives), using the framework library directly, not its
runner:

```ts
// /tmp/verify-run.ts (not saved into the project)
import { chromium } from '@playwright/test';

const browser = await chromium.launch();
const context = await browser.newContext({ recordVideo: { dir: '/tmp/verify-video' } });
const page = await context.newPage();

// real actions: navigate, fill, click, wait for real UI state
// real assertions: read persisted state through the app's own API or DB
// page.screenshot({ path: '/tmp/verify-video/step-1.png' }) at meaningful moments

await context.close(); // flushes the video file
await browser.close();
```

Import the project's auth and seeding helpers into the script where practical
instead of hand-rolling a login. Same assertion rules as coverage mode.

## A2: run

A failing step is fixed at the root (the app, or the script) and re-run. Never
edit an assertion to make a failure disappear. Confirm the video file exists.

Verify-only: delete the scratch script and its temp output once the report
has what it needs (video, screenshots).
