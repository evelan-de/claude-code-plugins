---
name: e2e-demo
description: >-
  Verify a finished task against the real running system - a browser feature via a real E2E test
  (Playwright, or whatever this project already uses), or a CLI/infra task (Docker setup, deploy
  script, install instructions) via a real recorded terminal session - never just "looks right in
  the code" or "should work." Produces a narrated MP4 (real screen capture, real voice), embedded
  directly and playable in a published web-artifact report (goal, issue, what changed, a results
  table, visuals) from that real run - optionally a Before/After pair for a bug fix, both videos in
  the same report. Runs entirely on the developer's own local machine - never against a remote,
  staging, or production environment. Asks the developer for login credentials when an authenticated
  session is needed, and optionally for the PR and JIRA/ticket link being verified. Can post a
  comment on that PR linking the report, but only when every acceptance criterion is verified
  passing or the developer explicitly asks for the comment. Use this when a finished task is
  otherwise ready to hand back and the user wants it proven - "test this properly", "make sure this
  works", "show me a demo", "I want a report for this", "verify the instructions actually work for a
  client", "show me before and after", "teste das richtig", "zeig mir eine Demo",
  "beweise dass das funktioniert", "ich will einen Report dazu", "zeig vorher und nachher". Works for
  both browser-facing changes and CLI/infra-only changes; pick the matching track in Phase 0.
---

# E2E Demo & Verification

Turns "I tested it" into three things a reviewer can actually check: a real run against the real
system (an E2E test against a real app, or a real recorded terminal session running the real
commands), a narrated MP4 walking through what it proved, and a published artifact report tying the
run back to the original task. Every claim in the video and the report traces back to something this
skill actually ran - nothing here is written from "this should work."

This exists because of a real, recurring failure mode: an assistant says "tested and working" after
only reading the code, or after a UI action that reports success without checking the actual
persisted result. If a step in this skill cannot be run for real, that is reported as a gap, not
smoothed over.

**This skill is project-agnostic by design.** It never assumes a specific test framework, folder
layout, or scripts beyond what a project's own README/CLAUDE.md documents. Where the project has its
own conventions (a fixtures pattern, a report publisher, a QA-annotation format), find and follow
them rather than inventing something generic - a project's own testing docs are always the binding
authority, this skill is the procedure around them.

## Local-only, by design

This skill runs entirely on the developer's own machine, against their own local environment. It
never touches anything remote or shared: no deployed/staging/production environment, no pushing
commits, no triggering CI/CD, no calling a remote API beyond what the task under test already calls
locally on its own (a local TTS container is fine; a shared staging server is not). The one
deliberate exception is Phase 8's PR comment - gated, visible, and never an implicit side effect of
"testing locally."

## Inputs - what to gather, and how to ask for it

**The developer invoking this skill has no way to already know it needs these things.** Nothing
about typing `/e2e-demo` or "test this properly" tells them a login is coming. Don't wait to
discover a gap mid-run and don't only ask when something happens to be missing - state what this
run needs, every time, as the *first* thing you say, before any other Phase 0 work:

> To verify this properly: (1) is the app already running locally, and where - I won't start it from
> scratch myself; (2) a login I can use - yours or a test account. If there's a PR or JIRA ticket for
> this, send those too (optional, but they save me guessing at scope and acceptance criteria). Reply
> with what you've got and I'll fill in the rest myself.

**When the task reads as a bug fix** (see "Before / After" below for the judgment call), append the
before/after offer to this same message rather than sending a second one - e.g. "...also, this looks
like a bug fix - want a before/after comparison, or just the fix confirmed?" One upfront message,
everything relevant in it.

Then:

1. **Read what the developer already gave you**, in this message or the one that triggered the
   skill - a PR number or link, a JIRA key, a URL, "use my login". Fold that into the same upfront
   message as an acknowledgment ("Got the PR link, thanks - still need a login") rather than asking
   again for it.
2. **A running app and, for Track A, credentials are the two genuinely required inputs; everything
   else is optional and degrades gracefully.** If nothing answers at the expected URL, or Track A
   needs an authenticated session and no credential has been given, stop and wait for the reply -
   don't start the app yourself and don't proceed on a guessed login. A missing PR link means work
   from the current diff instead; a missing JIRA link means pull goal/issue framing from the request
   itself instead. Neither of those blocks anything.
3. **Never guess, never try multiple existing accounts, never reset or fabricate a password directly
   in a database to work around missing credentials.** All three of these actually happened during
   this skill's own development and are exactly the failure mode this rule exists to close - each
   one cost real time and, once, briefly locked the developer out of their own session. A
   developer's own real working login is always the right answer over any project seed/test account
   guess - asking costs one message; guessing wrong costs an investigation.
4. **The JIRA/ticket link, when given (or found in the branch name/PR description), replaces
   guesswork for two things**: Phase 6's Goal/Issue framing (pull it from the ticket, don't
   paraphrase from memory) and Phase 8's acceptance-criteria gate (read the ticket's actual AC list,
   don't invent one).

Never proceed past Phase 0 on a guessed credential.

## Two modes: coverage vs. verify-only

**This distinction is not optional and must be resolved before Track A starts.** Track A can either
add a real, permanent test to the project (**coverage mode**) or drive the app live without touching
the project's files at all (**verify-only mode**). Get this backwards and the skill silently commits
you to changes nobody asked for - see "Non-negotiable rules."

- **Verify-only is the default.** Use it whenever the goal is proving something already works - a
  colleague's PR, a feature someone else finished, a demo for a client or reviewer. Nothing under
  the project's own source tree is written, ever.
- **Coverage mode only when explicitly asked**, or when it's unambiguously the current user's own
  finished work and they want lasting test coverage as part of it. If genuinely unclear which is
  wanted, ask - don't default to writing code into a codebase, especially one that isn't currently
  the user's own change.
- **A strong signal for verify-only: the current branch/PR is not the user's own work** (reviewing a
  colleague's PR, checking out someone else's branch to confirm it). Never add or extend a test file
  on a branch that isn't the user's without being explicitly asked to contribute coverage back.

Track B has no equivalent split - a recorded terminal session never touches the project's source
either way.

## Before / After (offered by judgment, not left for the developer to think to ask)

When the task is a bug fix, a single "here's the fix working" video proves less than a pair: the
same real steps run once against the broken code and once against the fixed code, so the reviewer
sees the actual defect and the actual fix, back to back - not just a claim that one exists.

**Don't wait for the developer to already know this feature exists and ask for it by name.** Judge
it yourself, as part of the same upfront Inputs message (see "Inputs"), from what's actually being
verified:

- **Task reads as a bug fix** (the ticket type is Bug, or the description is shaped like "X does the
  wrong thing" / "shows Y instead of Z" / references broken behavior being corrected) **and** a
  meaningful before-state exists (a base/destination branch to diff against, a specific commit) -
  **offer it explicitly**: "This looks like a bug fix - want a before/after comparison, or just the
  fix confirmed?" Never silently commit to the extra setup time without that offer landing first;
  it's real added cost (a second isolated instance, per "Before / After" below), not a free upgrade.
- **Task reads as new work** (a feature that didn't exist before, an addition rather than a
  correction) - there is no meaningful "before" to show, so don't offer it at all; asking about a
  before-state that can't exist just adds noise.
- **Genuinely ambiguous** - ask plainly rather than guessing either way.

**Never capture "before" by touching the project's actual running state - checking out an older
commit or stashing the fix in the real working tree, then restarting whatever dev server backs it.**
That risks exactly the failure this skill exists to avoid on the *user's own environment*: a
restarted dev server can invalidate live sessions, in-memory secrets, or anything else that isn't
re-derived identically on the next boot. Use an isolated git worktree instead:

1. **Pick the "before" ref: default to the PR's own base/destination branch, not a hand-picked
   commit.** Most projects merge PRs into one shared branch ahead of the true default branch (often
   named `preview`, `develop`, `staging`, or similar - check what this repo actually calls it, don't
   assume the name) - that branch, right now, *is* "before": the reviewer's actual mental model is
   "what's live today" vs. "what my PR changes it to," not archaeology through the PR's own commit
   history to isolate one sub-change. Use `git worktree add <path> <base-branch>` (or the merge-base
   of the PR branch and that base branch, if the PR branch has drifted). Only fall back to hunting
   for a specific commit when the PR bundles many unrelated changes and the developer wants to
   isolate just one of them for this demo - treat that as the exception, not the default, and ask
   rather than assume which commit they mean.
2. Stand up whatever the task needs *inside that worktree, on different ports* than what's already
   running (a second dev server, a second Docker stack) - never reuse or restart the user's live
   instance for this.
3. Record the "before" run there (Track A and/or B, exactly as normal).
4. Tear down what you stood up in the worktree and remove the worktree (`git worktree remove`).
   **"After" needs no checkout of any kind** - it's the developer's own already-running app on the
   PR branch (see "Prerequisites": this skill doesn't start or switch branches on their real
   environment at all), recorded exactly as a single after-only run would be.

If standing up an isolated before-state isn't practical (the app needs infrastructure that can't
reasonably run twice, e.g. a single shared external service), say so plainly and fall back to a
single after-only video rather than touching the user's live environment to get a before-shot -
this trade-off is explicit, not silently skipped.

## Two tracks, one method

| | **Track A: Browser** | **Track B: CLI / infra** |
| --- | --- | --- |
| For | A page, form, button - anything a browser user sees | Docker Compose, deploy scripts, install instructions, migrations - anything with no UI |
| Real run | An E2E test against the real app, in whatever framework this project already uses | A real terminal session running the real documented commands |
| Real video source | The test framework's own video recording (Playwright, Cypress, etc. all support this) | `asciinema` recording rendered to video by `agg` |
| Screenshots | Whatever this project's E2E suite already captures, or the test framework's own on-failure/on-step screenshots | Terminal frames / dashboard pages if the tool has a web UI to view results in |

A task can need **both** - e.g. "verify these on-premise install instructions": Track B records the
terminal (`docker compose up`, a deploy command, ...) and Track A records a real browser visiting
that instance's own web UI to show the result. When both apply, record each on its own track, then
**concatenate as sequential cuts** in Phase 5 (terminal action → cut to the browser result) - never
fake a split-screen or attempt live desktop automation, see "Why not full screen recording" below.

Everything from Phase 4 onward (narration, muxing, the artifact) is shared between both tracks.

## Why not full OS-level screen recording

Most OSes can record the whole screen, and window-switching could in principle be automated (e.g.
AppleScript/`osascript` on macOS driving System Events). **Don't do this.** It means simulating real
clicks and keystrokes on the user's actual desktop, typically needs elevated/accessibility
permissions, is fragile against any UI change, and has no undo if it clicks the wrong thing. Track A
(the test framework's own isolated browser) and Track B (`asciinema`, a real but scoped terminal
session) give a fully real recording of both surfaces without ever touching the user's real
mouse/keyboard.

## Scope - when to run this

Run it for a task that is otherwise finished and has something concrete to verify against the real
system - a browser flow (Track A) or a set of real commands/instructions (Track B). Do not run it
for:

- Pure backend/library changes with no observable surface (write a unit/integration test instead,
  per the project's normal testing rules - not this skill).
- Trivial one-line fixes (a typo, a copy change with no behavior change).

## Prerequisites

- **The app under test should already be running, started by the developer, before this skill
  starts.** Don't start it from scratch yourself as a default move. A developer's own already-running
  dev server has the right env vars, the right build state, and the right ports already sorted out -
  none of which this skill can safely reconstruct blind. Starting a fresh instance risks exactly the
  problems this skill's own development actually hit: missing workspace builds, missing dependencies
  a "clean" install still didn't pull in, Prisma/codegen steps undocumented outside the project's own
  setup docs - each a real, time-consuming rabbit hole unrelated to the task being verified. Ask for
  the URL/port it's running on as part of the same batched Inputs question if it isn't obviously
  `localhost:3000` or equivalent; if nothing is running, ask the developer to start it rather than
  attempting it yourself.
  **The one deliberate exception is Before/After's isolated worktree instance** (see that section) -
  standing up a second, throwaway instance there is unavoidable. Even there, use the project's own
  documented setup commands (README/CLAUDE.md - install, build, codegen) rather than improvising, and
  tell the developer up front that this step can need real troubleshooting since it's a genuinely
  fresh environment, not a shortcut.
- **Track A**: this project's own E2E suite set up and runnable - its own README/CLAUDE.md says how
  (install steps, env vars, a running app or environment to point at). Find that doc first; don't
  guess.
- **Track B**: `asciinema` and `agg` (`brew install asciinema agg` on macOS; see
  <https://asciinema.org> and <https://github.com/asciinema/agg> for other platforms).
- **Both tracks**: a local, self-hosted TTS server reachable over HTTP with an OpenAI-compatible
  `/v1/audio/speech` endpoint. This plugin ships one at `docker/openai-edge-tts/` (a copy of
  [travisvn/openai-edge-tts](https://github.com/travisvn/openai-edge-tts) wired up as a standalone
  compose service - fully self-hosted, no OpenAI account or billing; see that directory's own
  README, including its note that synthesis itself calls out to Microsoft's Edge TTS backend over
  the internet - not fully air-gapped). One instance can serve every project using this skill, so
  check first whether it's already running (`curl -s http://localhost:5060/v1/voices ...` or just
  `docker ps | grep openai-edge-tts`) before starting a new one. If it's not running and the user
  hasn't said to skip narration, bring it up yourself rather than asking (`cd
  <this-plugin-checkout>/docker/openai-edge-tts && cp .env.example .env && docker compose up -d`,
  once) - bringing up an already-configured local service is not a decision that needs a pause. A
  project may also already have its own copy of this same service under its own `docker/` for
  historical reasons - reuse that one instead of starting a second if so.
- `ffmpeg` on the machine running this skill (`which ffmpeg`; `brew install ffmpeg` if missing) - do
  not fabricate a narrated video without it.

## Phase 0: Confirm there's something real to verify, pick the track(s) and the mode

Read the actual diff or the actual instructions being verified before writing anything. Identify the
specific, concrete thing that changed or needs proving - the exact page and action (Track A), or the
exact commands and expected real-world outcome (Track B), or both. If you can't point at something
concrete to run, this is the wrong skill (see Scope).

**If Track A applies, also resolve coverage vs. verify-only now** (see "Two modes" above) - before
touching any project file. Check whose work this is (the user's own uncommitted/in-progress change,
vs. someone else's branch/PR being reviewed) and whether lasting test coverage was actually asked
for.

---

## Track A: Browser feature

### A1a: Coverage mode - write or extend a real E2E test

Only when Phase 0 resolved to coverage mode.

**Find this project's own E2E conventions first** (its test directory's own README, or a section in
CLAUDE.md) and follow them exactly - they are the binding authority, not a suggestion. Look for:
existing fixtures/helpers for auth and data setup (never hand-roll a login flow if the project
already has one), an existing pattern for creating real test data, and any existing
metadata/annotation convention for describing what a test proves (some projects attach a
human-readable description to each test for a QA-facing report - if this project has one, populate
it; if not, don't invent one).

Regardless of framework, these are non-negotiable (see "Non-negotiable rules" below too):

- **Assert against real persisted state, not just UI text/toasts.** Prefer reading back the actual
  DB row / API response over a status badge - a badge can flip to "success" while the write
  silently no-ops.
- **Use real data through the project's own real data-seeding path** (an API fixture, a factory,
  whatever it already has) - don't bypass the code path being demoed with hand-seeded fixtures.
- If a test covering this flow already exists, extend it rather than duplicating.
- Keep the **demo scope to one test** (or a short, tightly related pair) - most frameworks record
  one video per test, and this skill does not stitch multiple unrelated test videos together.
- Run the project's own type-check/lint on the new/changed test before running it for real.

Then continue with A2's "coverage mode" path.

### A1b: Verify-only mode - drive the app live, touch nothing in the project

Only when Phase 0 resolved to verify-only mode (the default). **No file under the project's source
tree is created, modified, or extended at any point in this mode** - not a new spec, not an edit to
an existing one, nothing staged, nothing left in the working tree when this skill finishes.

Write a small, throwaway script **outside the project's own test directory** (a scratch/tmp location
- never inside `apps/e2e`, `cypress/`, `tests/`, or wherever the project's real suite lives) that
uses the project's already-installed test framework library directly, not its test runner:

```ts
// scratch script, e.g. /tmp/verify-run.ts - NOT saved into the project
import { chromium } from '@playwright/test';

const browser = await chromium.launch();
const context = await browser.newContext({ recordVideo: { dir: '/tmp/verify-video' } });
const page = await context.newPage();

// ... perform the real actions: navigate, fill, click, wait for real UI state ...
// ... assert real persisted state directly - hit the app's own API/DB the same way

await context.close(); // flushes the video file
await browser.close();
```

This still has to meet every rule in "Non-negotiable rules" - real actions, real assertions against
real persisted state, no UI-toast-only checks - it just never becomes a permanent part of the
project. Reuse the project's own auth/data-seeding helpers by importing them into the scratch script
where practical (still not writing project files), rather than hand-rolling a login flow.

Then continue with A2's "verify-only mode" path.

### A2: Run it for real, with video

**Coverage mode**: find how this project turns on video capture for an E2E run - many wire it
through an env var read by the test config (check the config file and the README/CI workflow for
one), some frameworks support it as a run flag. If the project has no such switch, temporarily
enable video recording in its test config for this run only (e.g. Playwright's `use: { video: 'on'
}` in `playwright.config.ts`), then revert the config change afterward - don't leave an unrelated
permanent change behind.

**Verify-only mode**: video capture is already set directly in the scratch script's own
`recordVideo` context option (A1b) - nothing to configure at the project level.

Either mode: do not proceed if something fails - fix the underlying issue (or the script/test, if
that's what's wrong) and re-run. Never edit an assertion to make a real failure disappear. Confirm
the video file actually exists before continuing.

### A3: Gather real screenshots

**Coverage mode**: if the project has its own way of publishing/viewing an E2E run as a report with
screenshots (check its `package.json` scripts and README - some projects build this specifically),
use it; it's real captures of the real run, never illustrations. Otherwise, most frameworks' own
HTML report and on-failure/on-step screenshots are enough.

**Verify-only mode**: call `page.screenshot({ path: ... })` at meaningful moments directly in the
scratch script - same principle (real captures, not illustrations), just captured by the script
itself since there's no project-level report tooling in play.

Either mode: keep the resulting file paths for Phases 4 and 6. When this skill finishes in
verify-only mode, delete the scratch script and its temp output directory once the video/screenshots
have been copied wherever Phase 5-7 needs them - nothing about the run should be left behind.

---

## Track B: CLI / infra task

### B1: Script the real commands

Write the exact sequence of real commands this task's own instructions specify (a README, a
CLAUDE.md section, a runbook) into a shell script. Do not invent shortcuts or skip steps the real
instructions include - the point is proving those exact instructions work, not a simplified version
of them.

**Name the human-gated steps up front, don't try to script around them.** Some steps genuinely need
a real person (e.g. a browser-based login/magic-link flow, approving a dashboard prompt). List these
separately; the recorded script runs everything else and the narration/artifact calls these out
explicitly (see "Non-negotiable rules"). If a prior real run already completed a one-time step whose
state persists (e.g. a login token, a created project) and redoing it would only re-demand the same
human action for no new information, it's fine to build on that persisted state - say so plainly in
the narration rather than implying the recording started from literally nothing.

### B2: Record it for real

```bash
asciinema rec -c "bash the-script.sh" session.cast
```

`-c` runs the script non-interactively while still capturing real terminal output with real timing -
this is not a re-enactment, it's the actual commands actually running. If a step's output is
noisy/huge, that's fine, it's real; don't edit the transcript afterward except to trim dead time
(long waits) with `asciinema`'s own idle-time-limit options, never to change what happened.

### B3: Render to video

```bash
agg --idle-time-limit 1.5 session.cast session.gif
ffmpeg -i session.gif -movflags faststart -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -y terminal.mp4
```

`--idle-time-limit` compresses real dead air (a polling loop, a long build wait) without altering
the timing of anything that's actually happening - prefer it over uniformly speeding up the whole
recording, which distorts real command durations along with the dead time.

If Track A also applies (a web UI to view the result in, e.g. a dashboard), record that portion with
the project's own test framework the normal way (A1-A2, using it to *view* real state rather than to
assert - a lighter touch than a full test is fine here, e.g. a short script using the framework
directly to navigate and screenshot/record) and keep `terminal.mp4` and the browser segment separate
for now; they're concatenated in Phase 5.

---

## Phase 4: Write the narration script from the real run only

Build a short, timestamped narration script **strictly from what the recorded run actually proved**:

1. Track A: read the real report/test metadata for the actual assertions made. Track B: read the
   actual `session.cast` output and the script's real results (exit codes, printed confirmations,
   e.g. a deploy command's own success line, or a health-check command's real output).
2. Note roughly when each meaningful beat happens in the video (a page transition, a command
   finishing) so narration lines are paced against real moments, not guessed.
3. Write 1-3 sentences per beat: what's happening on screen, then what was actually verified at that
   point, tied to the specific check (e.g. "and the worker actually pulled the image and ran the
   task - confirmed by the run completing with the matching output, not just the deploy command
   exiting zero").
4. Do not narrate anything that wasn't actually checked. If something looks right but wasn't
   verified, say so as a caveat, not as a narrated fact.
5. **Match the narration language to this project's actual audience**, not a reflexive default -
   check the project's README/CLAUDE.md for its target market/user base, or ask if genuinely
   unclear. Write natural spoken language, not text read verbatim from a written description (a
   description is written to be read, not heard).

Save the script as plain text with rough timestamps (`[00:00] ...`) - it also goes into the artifact
in Phase 6 so a reader can follow along without sound.

## Phase 5: Synthesize narration and assemble the final MP4

Synthesize each beat as its own clip - never one clip for the whole script - so the overlap check
below can work beat by beat:

```bash
curl -s -X POST http://localhost:<port>/v1/audio/speech \
  -H "Authorization: Bearer <API_KEY>" -H "Content-Type: application/json" \
  -d '{"input":"<beat text>","voice":"<a voice matching the narration language>","response_format":"mp3"}' \
  --output beat_1.mp3
```

Confirm each output is a real playable audio file, not an error body (`file beat_1.mp3` should say
`MPEG ADTS...`, not `ASCII text`).

**Before placing multiple beats on one track, compute non-overlapping start times from each clip's
real, measured duration - never from Phase 4's rough timestamps alone.** A beat's spoken length is
not known until it's synthesized, and a beat placed at the *next* real video moment can easily start
before the *previous* beat has finished speaking - that's audible as overlapping/talking-over-itself
in the output, and it's a bug every time it happens, not an acceptable first-pass artifact. For each
beat in order: `start = max(intended_timestamp, previous_start + previous_duration + 0.15s)`. Verify
before muxing:

```bash
for f in beat_*.mp3; do
  ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f"
done
```

Then place each with `adelay` at its *computed* start (in ms), mixed together:

```bash
ffmpeg -i beat_1.mp3 -i beat_2.mp3 -filter_complex \
  "[0:a]adelay=0|0[a0];[1:a]adelay=13000|13000[a1];[a0][a1]amix=inputs=2:duration=longest:dropout_transition=0[aout]" \
  -map "[aout]" -y narration.mp3
```

If a computed start had to move noticeably later than the intended video moment to avoid overlap,
that's the real pacing mismatch to disclose (see below) - not something to hide by trimming the beat
that ran long.

**Single video source** (pure Track A or pure Track B): mux directly -

```bash
ffmpeg -i video.webm -i narration.mp3 -c:v libx264 -c:a aac -shortest -y demo.mp4
```

**Both tracks** (sequential cuts, per "Two tracks" above): concatenate the real video segments
first, in the order the narration follows (e.g. terminal deploy → cut to browser dashboard showing
the deployed result), then mux:

```bash
ffmpeg -i terminal.mp4 -i browser.mp4 -filter_complex \
  "[0:v]scale=1280:720,setsar=1[v0];[1:v]scale=1280:720,setsar=1[v1];[v0][v1]concat=n=2:v=1:a=0[v]" \
  -map "[v]" -y combined.mp4
ffmpeg -i combined.mp4 -i narration.mp3 -c:v libx264 -c:a aac -shortest -y demo.mp4
```

Note the pacing honestly afterward - this is a first pass at sync, not frame-accurate editing. If
narration runs noticeably longer/shorter than the video, say so rather than silently trimming
content.

Verify the result is real before delivering it:

```bash
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1 demo.mp4
```

Then deliver it with `SendUserFile` (`status: "proactive"` if this wasn't the immediate last thing
asked for, `display: "attach"`).

## Phase 6: Build the artifact report

**Load the `artifact-design` skill before writing this** - not optional, same as any other artifact.
**Also load the `artifact-capabilities` skill before publishing** - the video is embedded in the page
itself (not just sent as a separate file), which needs the `assets` capability declared correctly.

Build an HTML page with:

- **Goal / issue**: what the task was, in plain language, and why (pull from the actual request,
  not a generic restatement).
- **What changed**: a short summary of the real diff - files touched, the behavioral change, with
  specific `path:line` references.
- **Results table**: one row per thing actually checked (a test assertion, or a real command's real
  output/exit code for Track B), columns for what was checked, how (be specific - real DB read, API
  response, command output, dashboard state), and pass/fail. Pull from the actual test file / report
  metadata / script output, not from memory of what was meant to be checked.
- **The video(s), embedded and playable in the page itself** - see "Embedding the video" below. If
  Before/After was captured, both videos belong in the same report, clearly labeled, not two
  separate hand-offs.
- **Visuals**: embed real captures - Track A's real screenshots, and/or Track B's terminal frames or
  dashboard screenshots. Never draw a mockup when a real capture exists.
- **The narration script** from Phase 4, so the report stands on its own without the video's audio.
- **A manual-step callout**, if any step genuinely needed a human (see "Non-negotiable rules") -
  name it plainly rather than implying full automation.

### Embedding the video

Publish the report first (so the artifact exists and has a URL), then upload each MP4 as an asset
and embed it as a real `<video>` element - never a link-out, never a giant base64 data URI for
anything beyond a small screenshot:

1. Declare the capability on publish: `capabilities: {"assets": {}}`.
2. Upload the video: `Artifact` action `upload_asset`, the report's own `url`, and the MP4's
   `file_path`. The result gives back a `url` for that asset.
3. Put that URL directly into a `<video controls src="...">` in the HTML (a poster frame - one of
   the real screenshots - is a nice touch, not required) and republish the same file over the same
   `url` so the embedded tag points at a real, already-uploaded asset.

If Before/After was captured, upload both and place them side by side (or stacked on narrow
viewports) under clearly labeled headings - "Before" and "After" - so the contrast is the point, not
buried in prose.

Publish it with the `Artifact` tool and hand the user the link.

## Phase 7: Deliver

Send, in one message: the artifact link (video already embedded and playable there - this is the
primary deliverable now, not an attachment), and a two-or-three-sentence summary of what was proven
and what (if anything) is still open or was manual. Sending the raw MP4(s) separately too is fine
but no longer the main way the video reaches the user.

## Phase 8: Comment on the PR - gated, never automatic

Skip this phase entirely unless a PR was identified in Phase 0/Inputs. When one was, comment on it
**only** when at least one of these is true:

- **Every acceptance criterion is verified passing.** Source the AC list from the JIRA ticket if one
  was given; otherwise from the PR's own description; otherwise from the specific defect/behavior
  the developer described when asking for this run. Partial verification does not qualify - if even
  one criterion is unverified or failing, do not comment; report the gap to the developer directly
  instead and let them decide what happens next.
- **The developer explicitly asks for the comment to be added**, regardless of AC status - they may
  want visibility on partial progress or a known-open issue, and that's their call to make, not this
  skill's.

If neither condition holds, stop at Phase 7 - the artifact and video go to the developer only, and
the PR stays untouched. This is the one step in the whole skill that becomes visible to other
people, so it never happens as a silent side effect of "testing locally":

1. Say plainly, before doing it, that you're about to comment on the PR and why (AC met, or asked).
2. Use whatever PR tooling this project already has (`gh pr comment`, `bb pr comment`, or similar -
   check what's actually available rather than assuming GitHub).
3. Keep the comment short: what was verified, a link to the artifact report, and - if this was the
   AC-met path - which criteria. Let the report itself carry the detail.

## Non-negotiable rules

- **Never say "tested"/"verified" for something only read through in the code or in a README.** If a
  step couldn't actually be run (no running app, tooling not installed, TTS down), say so explicitly
  and report what was and wasn't verified.
- **Assertions read back real state.** A UI success toast or a command's zero exit code alone is not
  proof; the underlying DB row, file, API response, or a real health check is.
- **A step that is inherently human-gated stays human-gated.** A real browser session required for a
  login (OAuth, magic-link) is a security property, not a tooling gap - this skill maximizes what's
  verified without a manual click, but never fakes or hides that a step needed one.
- **No simulated desktop input.** See "Why not full screen recording" - Track A and Track B cover
  real verification without ever taking over the user's actual mouse/keyboard.
- **Narration and the artifact's results table are derived from the real run, never invented** to
  sound more complete than the run actually was.
- **Never assume this repo's conventions are another project's conventions.** Every path, script
  name, and framework mentioned in this skill's examples (Playwright, a specific env var, a specific
  report publisher) is illustrative, not prescriptive - always find and follow what the current
  project actually uses.
- **Verify-only mode means zero footprint in the project, no exceptions.** No new file, no edit to
  an existing file, nothing staged - not even temporarily "to be cleaned up later." Resolve coverage
  vs. verify-only explicitly in Phase 0 before writing anything, default to verify-only, and treat
  writing to a colleague's branch or PR without being asked for coverage as a bug in this skill's
  execution, not an acceptable side effect of "doing E2E."
- **Never guess, cycle through, or fabricate login credentials.** Ask the developer once, batched
  with any other missing input (see "Inputs"). Never reset or write a password directly into a
  database to work around a missing credential - this is local-only test data manipulation that
  crosses into altering something a real person might depend on.
- **Don't start the app under test from scratch by default.** Ask whether it's already running and
  where, in the same batched question as credentials (see "Inputs" and "Prerequisites"). Starting one
  yourself is the exception (Before/After's isolated worktree instance only), not the default move.
- **Nothing here ever touches a remote/staging/production environment**, pushes a commit, or
  triggers CI, no exceptions - see "Local-only, by design."
- **The PR comment in Phase 8 is gated, never automatic.** Comment only on 100%-verified acceptance
  criteria or an explicit developer request - and say so plainly before posting either way.
