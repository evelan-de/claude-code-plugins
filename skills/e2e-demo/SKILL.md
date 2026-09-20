---
name: e2e-demo
description: >-
  Verify a finished task against the real running system - a browser feature via a real E2E test
  (Playwright, or whatever this project already uses), or a CLI/infra task (Docker setup, deploy
  script, install instructions) via a real recorded terminal session - never just "looks right in
  the code". Use when a finished task should be proven: "test this properly",
  "make sure this works", "show me a demo", "I want a report for this", "verify the instructions
  actually work for a client", "show me before and after", "teste das richtig", "zeig mir eine
  Demo", "beweise dass das funktioniert", "ich will einen Report dazu", "zeig vorher und nachher".
---

# E2E Demo and Verification

Output: a real run (E2E test or recorded terminal session), a narrated MP4 of
that run, and a published artifact report (goal, issue, what changed, results
table, visuals, both videos for Before/After). Everything runs on the
developer's own machine: no remote, staging or production environment, no
push, no CI trigger. The only outward step is the gated PR comment (Phase 6).

References in this folder: `track-browser.md` (Playwright track),
`track-cli.md` (terminal recording), `tts.md` (voice), `assemble.md`
(ffmpeg, report embedding).

## Inputs

First message, before any other work, ask once for: the app URL and port
(the developer starts the app, not this skill), a login to use (theirs or a
test account; Track A only), and optionally the PR and the JIRA/ticket link.
Acknowledge what was already given. When the task reads as a bug fix, add the
Before/After offer to the same message. A missing PR link means work from
the current diff; a missing ticket means framing from the request. A missing
running app or missing login blocks: wait for the reply.

The ticket, when given or found in the branch name or PR description, is the
source for the report's Goal/Issue and for the acceptance criteria in Phase 6.

## Two tracks

| | Track A: Browser | Track B: CLI / infra |
| --- | --- | --- |
| For | A page, form, button, anything a browser user sees | Docker Compose, deploy scripts, install instructions, migrations |
| Real run | An E2E test against the real app in the project's own framework | A terminal session running the documented commands |
| Video | The framework's own recording (Playwright, Cypress) | `asciinema` rendered by `agg` |
| Screenshots | The suite's own captures or the framework's step screenshots | Terminal frames, dashboard pages when the tool has a web UI |

A task can need both (install instructions plus the web UI they stand up):
record each on its own track, concatenate as sequential cuts in assemble.md.
Never record the whole OS screen or drive the real desktop with simulated
input.

Track A has two modes, resolved in Phase 0: verify-only (default, zero
footprint in the project) and coverage (a permanent test, only when asked on
the user's own work). Details in track-browser.md.

## Before / After

Offer it for a bug fix (ticket type Bug, or "X does the wrong thing"
descriptions) when a before-state exists. Do not offer it for new work. Ask
when ambiguous.

The before-state runs in a separate git worktree; the live app is never
touched, checked out, stashed or restarted:

1. Ref: the PR's base/destination branch (`preview`, `develop`, whatever this
   repo uses), or the merge-base when the PR branch drifted. A specific commit
   only when the developer wants one sub-change isolated; ask which.
2. `git worktree add <path> <ref>`, stand the app up there on different
   ports with the project's documented setup commands (this is the one place
   this skill starts an app; tell the developer it may need troubleshooting).
3. Record the before-run there.
4. Tear down and `git worktree remove <path>`. The after-run is the
   developer's already-running app.

Not practical (infrastructure that cannot run twice): say so and deliver an
after-only video.

## Phases

0. Read the diff or the instructions. Name the concrete thing to run: page and
   action, or commands and expected outcome. Nothing concrete, or a pure
   backend change with no observable surface, or a trivial copy fix: wrong
   skill. Pick the track(s); for Track A resolve verify-only vs coverage.
1. Track A: track-browser.md. Track B: track-cli.md. Confirm the video file
   exists.
2. Narration script from the real run only: read the actual assertions
   (Track A) or the actual `session.cast` output and exit codes (Track B),
   note when each beat happens, write 1-3 spoken sentences per beat naming
   what was verified and how. Unverified observations are caveats, not
   narrated facts. Language per the project's audience. Save as text with
   `[00:00]` timestamps.
3. Synthesize per beat (tts.md), assemble and verify the MP4 (assemble.md).
4. Report: load the `artifact-design` skill, build an HTML page with Goal /
   Issue, What changed (`path:line` references), a results table (one row
   per check: what, how, pass/fail, from the real test or script output),
   the embedded video(s), real screenshots, the narration script, and a
   manual-step callout when a step needed a human. Embed per assemble.md.
   Publish with the `Artifact` tool.
5. Deliver in one message: the artifact link and two or three sentences on
   what was proven and what is open or was manual.
6. (Skipped when no PR was identified.) Comment on the PR only when every
   acceptance criterion is verified passing (from the ticket, else the PR
   description, else the developer's stated defect) or the developer asks
   for the comment. Partial verification: no comment, report the gap. Say
   before posting that you are about to comment and why. Use the project's
   PR tooling (`gh pr comment`, `bb pr comment`). Keep it short: what was
   verified, the report link, the criteria met.

## Non-negotiables

- Never say "tested" or "verified" for something only read in code or docs.
  A step that could not run is reported as a gap.
- Assertions read back persisted state: DB row, file, API response, health
  check. A toast or a zero exit code is not proof.
- A human-gated step (OAuth, magic link) stays human-gated and is named as
  such in narration and report.
- No simulated desktop input, no OS screen recording.
- Narration and results table come from the real run only.
- The project's own conventions bind; every framework, path and script named
  here is illustrative.
- Verify-only mode: no file under the project created, edited or staged, not
  even temporarily.
- Never guess, cycle through, reset or fabricate login credentials. Ask once.
- Never start the app under test yourself, except the Before/After worktree
  instance.
- Nothing touches a remote, staging or production environment, pushes, or
  triggers CI.
- The PR comment is gated (all criteria verified or explicit request) and
  announced before posting.
