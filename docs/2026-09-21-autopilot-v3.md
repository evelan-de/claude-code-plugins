# Autopilot v3: headless only, code-level plans, a browser that exists (2026-09-21)

## Why

Two days of v2 produced these facts:

- **A hand-off into nothing.** `2026-09-19-website-a-wave` (local-recording, 12 packages) ran
  interactively on the MacBook, reached the context budget after P4 and wrote `HANDOFF.md`.
  Nobody started the next session: mission-control restarts only items it started itself.
  Andreas found a stalled branch the next morning.
- **Headless runs have no browser.** The one real queue run (jexity-chatbot, WEB-1101
  finalize, 143 turns, $12.06) finished every package and then ended
  `blocked - E2E needs a logged-in dashboard session`: the browser tools the skill names
  (`read_page`, `get_page_text`) belong to the desktop app and do not exist in `claude -p`.
  Every UI ticket would end the same way.
- **Plans say what, not how.** The template capped `PLAN.md` at 200 lines and the planner at
  80-line reads. The 465-line v2 plan for website-a-wave lists files and contents per package,
  but no insertion points, signatures, flows or assertions. Sonnet had to invent all of it,
  which is where the 250k context per package went.
- **Ticket updates need the desktop app.** Jira and Slack are desktop-app connectors, not in
  `~/.claude.json`; a headless run cannot set a ticket In Progress or comment on it. The
  four servers that ARE global (Sanity, firecrawl, notebooklm, nanobanana) are the ones no
  run needs.

Measured (`autopilot-usage`, local-recording): v1 with lead subagents cost ~45M cache-read
tokens per package; v2 ~9M. The slimming worked. The v2 session ran on Opus because it was
started interactively with the default model; headless runs are Sonnet by construction.

Reference points Andreas asked about: AgentSystemLabs' MissionControl (Electron board with
terminals) and its successor nebula (a 4 MB Rust TUI: project → worktree → session tree,
status dots fed by agent hooks, a daemon that keeps sessions alive when the UI closes,
"needs feedback" with a sound). Both are observation tools for a human who watches many
interactive sessions; neither has plans, hand-off chaining, headless verification or a
review loop. Four ideas carry over (status from the agent's own hook, "blocked" as a loud
state, sessions that survive the UI, the diff size at a glance); the rest does not.

## Decisions (Andreas, 2026-09-21)

1. **Headless only.** Autopilot runs only through the runner (`mission-control run`), on the
   Mini and on the MacBook. `/autopilot <session dir>` in an interactive session enqueues the
   item and starts the runner in the GUI session; it never implements in the interactive
   context. The runner restarts hand-offs, up to **5** times. Andreas never restarts by hand.
2. **Plans at code level, from Fable.** Per package: insertion points (`file:line` plus the
   anchor line quoted), function signatures, the flow as pseudo-code, test cases with
   assertions, exact commands. Not the finished code: Sonnet writes that. No line cap on the
   plan, no read cap on the planner: it reads the touched files whole.
3. **Browser: `agent-browser` (Vercel), never Playwright.** Login projects get a state file
   saved once by Andreas (`agent-browser state save`), path in `.claude/autopilot.json`.
4. **Context budget 500k, 5 restarts.** Checked against the pricing page: Claude 4.6+ bills
   the full 1M window at the standard rate (no long-context premium; the premium cited in
   the discussion on 2026-09-21 does not exist). A 500k session reads roughly twice the cache tokens of a 250k one
   in its upper half, about +$2 per package on Sonnet 5 ($0.20/MTok cache read), and halves
   the number of hand-offs. To be measured: whether Sonnet's failed-attempt rate rises above
   300k context; that would be the only reason to lower it again.
5. **Jira through a script, not through the MCP.** A headless run needs four operations
   (view, start = In Progress + assign, comment, transition). That is a `jira` script with
   an API token in a mode-600 file, not 100+ MCP tools. Slack stays with the runner (webhook).
   The four global MCP servers leave `~/.claude.json`; Sanity moves into the projects that
   use it.

## What changes

### `/autopilot-plan` (skill)

- Runs on Fable by default, Opus is fine; the skill says so
  in one line on Sonnet or Haiku.
- Explore without the 80-line cap: read every file a package touches, whole. Verify every
  anchor, signature and type against the file before writing it down.
- New per-package sections in the template: **Implementation** (numbered steps; each step
  names `path:line` and quotes the anchor line, gives the signature to add or change, the
  flow in pseudo-code, and which existing helper to reuse) and **Tests** (test file, test
  names, each with input → expected assertion; the seam it hits). "Files", "Seams",
  "Verify", "Edge cases" stay.
- Package sizing rule: one package touches at most ~6 files and ~300 diff lines; larger →
  split. A package must fit in one run session comfortably.
- Plan review by `evelan:autopilot-plan-reviewer` runs by default for every plan with three
  or more packages (cost measured at 1.3M cache reads, negligible).
- Hand-over: no interactive launch line any more. The only two ways to run: "hand to the
  queue" (draft PR with label, for developers and for the Mini) or, on a machine with a
  local queue, `/autopilot <session dir>` which enqueues and starts.

### `/autopilot` (skill)

- **Interactive session** (no `.claude/.autopilot-active`, and a queue exists on this
  machine): `mission-control add <repo> <session dir>` then `mission-control start`; print
  the item, the log path and `/mission-control status`; stop. No implementation in this
  context. No local queue (a developer) → point to "hand to the queue" in `/autopilot-plan`.
- **Headless run** (started by the runner): as v2, with these changes:
  - Browser checks with `agent-browser` (`references/browser.md`): open, `snapshot -i`,
    `get text`, `screenshot`, `console`, `errors`, `network requests`, `set viewport`;
    `--state <browserState>` when `.claude/autopilot.json` names one. The desktop-app browser
    tools are not available and are not named any more.
  - Ticket updates with the `jira` script when `~/.claude/jira/env` exists: `jira start
    <KEY>` before the first commit, `jira comment <KEY>` with the report head and the PR link
    at the end, `jira transition <KEY> "<merge status>"` never (that is the merge, Andreas'
    call). Without the env file: one line in `REPORT.md`, no ticket update.
  - The run follows the plan's Implementation steps; a step that turns out wrong (anchor
    moved, signature does not compile) is corrected and recorded in `DECISIONS.md` with the
    plan step number, never silently.
  - Hand-off unchanged, restarts by the runner.

### `mission-control` (script)

- `MISSION_CONTROL_MAX_RESTARTS` default 5.
- `start`: starts a run now on this machine inside the GUI session. Installs the
  LaunchAgent on demand without a schedule (`install-schedule` without a time = agent with no
  `StartCalendarInterval`), then `launchctl kickstart`. `kickstart` becomes an alias.
  Refuses while a run is active, like today.
- `status` gains, for the running item: the current package (`[~]` line of `PLAN.md`), the
  run's own status line (`.claude/.autopilot-status`: ISO time, context tokens, last tool),
  and the diff size against the base (`git diff --shortstat`).
- Watchdog: a tick is progress when the status file changed since the last tick OR a commit
  or plan change happened. A hung process (no tool call for four ticks) is a stall even when
  it committed earlier.
- Notifications: `blocked`, `handoff-limit`, `timeout` and `stalled` play a sound
  (`Sosumi`); `done` plays `Glass`. Slack unchanged.
- Skill routing (Andreas, review round 1): local is the default wherever
  `~/.claude/mission-control` exists; the Mini over SSH only when the request names it
  ("auf dem Mini"); `status` shows both. The MacBook keeps `host` for reaching the Mini and
  gets its own queue directory for local runs; its `repos.txt` stays empty so labelled PRs
  are processed by the Mini only.
- The runner creates `.claude/.autopilot-active` in the worktree before every attempt: that
  sentinel is how the skill tells a run from an interactive `/autopilot` (review round 1,
  spec finding).
- Run options ("defer PR", "no Codex") live in the plan header `Options:`; an interactive
  `/autopilot` with options writes that line and commits it before enqueueing (review round
  1, Codex finding).

### Context-budget hook

- Default budget 500000. After every tool call the hook also writes
  `.claude/.autopilot-status` (`<ISO> ctx=<n> tool=<name>`), gitignored by `init`, read by
  `status` and the watchdog.

### `bin/jira` (new)

Python 3 (standard library: `urllib`, `json`; Andreas, 2026-09-21: helper scripts in Python, not sh; `mission-control` and the watchdog follow). Config `~/.claude/jira/env` (mode 600): `JIRA_SITE=https://evelan.atlassian.net`,
`JIRA_EMAIL`, `JIRA_TOKEN`. Commands: `view <KEY>` (summary, status, assignee, description),
`start <KEY>` (transition to the status named "In Progress"/"In Arbeit", assign to the token
owner), `comment <KEY> <text | ->` (plain text; Jira wiki markup is what REST v2 renders, so
the run posts short factual comments, never Markdown headings), `transition <KEY> <status
name>` (matched against the transitions' target status, case-insensitive), `assign <KEY>
[me | <accountId>]`. Every write reads back and compares (status name, assignee id, comment
body); exits 1 on any failure or mismatch; never prints the token. Test suite with a fake
transport (`bin/jira_test.py`, run by `bin/jira.test.sh`).

### `/autopilot init`

Adds: `agent-browser --version` check (install line when missing:
`npm install -g agent-browser` then `agent-browser install`), optional `browserState` in
`.claude/autopilot.json` with the recipe to create it (`agent-browser --headed open <login
url>`, log in by hand, `agent-browser state save ~/.claude/autopilot/<repo>/state.json`),
`.claude/.autopilot-status` in `.gitignore`, and a note that Jira updates need
`~/.claude/jira/env` on the queue machine.

### First real run (PAUL-2649, paul, 2026-09-21), folded in

Run 1 ($9.99): three packages committed, reviewer fix committed, then the run started the
Codex review in the background and ended its turn "to wait": in `claude -p` that ends the
process. Fixes: the skill forbids ending a turn to wait (everything in the foreground, Codex
with a 10-minute timeout); the Stop hook blocks a turn end while the newest session has
neither `REPORT.md` nor `HANDOFF.md`; the runner restarts a clean exit without artifacts
like a hand-off. Run 2 ($6.00, 89 turns): Codex found that the gate filter's tree hash
started from an empty index and missed tracked-but-ignored files (fixed, seeded from HEAD;
the same hash was also empty in paul because `git add` failed on `core.safecrlf`, fixed
with `-c core.safecrlf=false`); PR #304, CI green, label `autopilot-done`. Two skill steps
the run skipped: the Jira comment and the review-bot loop. Now the runner does the ticket
bookkeeping itself (`jira start` before, `jira comment` after, `jira-failed` in
`done.txt`), counts review-bot comments on the PR (`review-comments=N`), and the Stop hook
refuses a done report without a `## Review bot` section when the project has the review
workflow. Also seen: the claude.ai connectors (Jira, Slack) ARE available in `claude -p`;
the run used the Atlassian MCP for the In Progress transition. The skill now says the run
makes no tracker call at all.

`/autopilot init` in paul: `.claude` is gitignored there, so hooks written by init existed
in one checkout only; init now force-adds them (`git add -f`) when `.claude` is ignored.

### Divergence from the vendored `to-tasks`

Upstream `to-tickets` ends with "No file paths or code snippets in tickets; they go stale
fast": tickets that wait for weeks and are picked up by a strong model that explores by
itself. An autopilot plan is consumed within hours by a cheaper model on the same branch, so
it carries anchors, signatures, pseudo-code and assertions; the run corrects a moved anchor
and records it in `DECISIONS.md`. `to-tasks` itself keeps the upstream rule.

### Review round 2 (Fable, 2026-09-21), folded in

Blockers: the run got a detached worktree when the plan branch was checked out in the
user's checkout (now: `checkout --ignore-other-worktrees` in the worktree, and the
interactive route switches the user's checkout to the base first); a continuation that
aborted left `HANDOFF.md` next to `REPORT.md` and the runner restarted it five times (now:
a newer `REPORT.md` wins, the abort path deletes `HANDOFF.md`). Important: the timeout was
wall clock over all restarts (now per attempt); no warning without the context-budget hook
(now a line at the start and a stall reason that names tool calls); `start` from a dev
checkout silently ran the marketplace copy (now a warning when the two differ); runtime
files stayed in a kept worktree (now removed after every attempt); a crash without
`HANDOFF.md` had no rule (now: reset the `[~]` package, restart it); `~` in `browserState`
was expanded by nobody (now `$HOME`, `--state` before the subcommand). Minor: the plan
template gets `UI:` and `Copy/i18n:` lines per package; a stale sentinel in an interactive
checkout is deleted.

### Removed

The interactive launch line (`claude --model sonnet --effort medium --advisor fable ...`) from
the plan skill, the README quickstart and the autopilot skill; the desktop-browser tool names
from the autopilot skill; the "under 200 lines" and "80 lines at most" rules from the plan
skill.

## Expected effect

- No stranded branches: every session, interactive start or queue, is chained by the runner.
- UI tickets finish headless: the goal-artifact check runs in agent-browser, logged-in where
  a state file exists.
- Fewer turns per package: Sonnet executes steps instead of designing them. To measure on
  the first three runs with `autopilot-usage`: cache reads per package (v2: ~9M) and
  failed attempts per package.
