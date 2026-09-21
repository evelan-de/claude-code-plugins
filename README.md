# Evelan Claude Code Plugins

Shared Claude Code skills and commands for the Evelan team.

## Installation

### First-time setup

1. Add the Evelan marketplace in Claude Code:
   ```
   /plugin marketplace add evelan-de/claude-code-plugins
   ```

2. Install the plugin:
   ```
   /plugin install evelan@evelan-plugins
   ```

### Local testing

To test the plugin locally without installing from GitHub:
```bash
claude --plugin-dir /path/to/claude-code-plugins
```

### Auto-prompt for team projects

To have team members automatically prompted to install the plugin when they open a project, add this to the project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "evelan-plugins": {
      "source": {
        "source": "github",
        "repo": "evelan-de/claude-code-plugins"
      }
    }
  },
  "enabledPlugins": {
    "evelan@evelan-plugins": true
  }
}
```

### Updates

Plugin updates are distributed automatically when the repo is updated. To manually refresh:
```
/plugin marketplace update evelan-plugins
```

## Skills

### update-dependencies

Smart dependency updater using ncu (npm-check-updates). Goes beyond simple version bumps - for major updates, it researches breaking changes and can auto-migrate your code.

**Features:**
- Runs `npx npm-check-updates` once and shows minor and major candidates together
- Dry-run preview before any changes
- Parallel subagent research for major updates - finds breaking changes and migration guides
- Per-package opt-out after reviewing breaking changes
- Two execution modes:
  - **Apply now** - updates packages and auto-migrates code based on migration guides
  - **Create plan** - writes a detailed migration plan to `docs/plans/` for later execution
- Always pins exact versions (no `^` or `~`)
- Runs build/test/lint after migrations to catch regressions

**Trigger phrases:** "update dependencies", "aktualisiere dependencies", "upgrade packages", "check outdated", "Pakete aktualisieren"

### slim-claude-md

Turns a long project `CLAUDE.md` into a short always-loaded core (target under 150 lines)
plus path-scoped rules in `.claude/rules/` that load only when an agent touches matching
files, skills for procedures reached on demand, and pointers to docs that already exist.
Everything Claude can read off the repo (directory listings, package lists, tech stack,
file-by-file descriptions, history) is deleted. The skill classifies every block into one of
five buckets (DELETE, POINTER, SKILL, RULE, CORE), condenses what stays, shows the mapping
table and the sizes for a go before writing, verifies that every old heading and every
distinctive string landed somewhere on purpose, and opens one PR per project. Follows the
official guidance: under 200 lines per file, rules over imports (imports still load at
launch), "would removing this line cause a mistake?".

**Usage:** `/slim-claude-md` in the project, or "CLAUDE.md eindampfen", "split CLAUDE.md".

### port-from-repo

Controlled, exact-copy workflow for porting a component, style, layout, or feature from one repo into another. Kills the failure mode of approximating from memory instead of reading and copying the real source.

**Two modes, separable by instruction:**
- **exact** - reproduce look AND behaviour verbatim (copy classes and tokens as-is; verify in-browser against the source)
- **structure-only** - take the logic/structure/ideas, but restyle with THIS project's own design system

**Workflow it enforces:** read the source in full first (component + its base primitives + tokens) -> delta-check the target's existing tokens/primitives and any divergent global CSS -> treat "looks wrong everywhere" as a global/token cause (measure computed style) -> verify visually in the logged-in browser before claiming done.

**Usage:** `/port-from-repo [exact | structure-only] <what to port + source repo>`

**Trigger phrases:** "port from X", "übernimm das aus X", "wie in Jexity", "1:1", "make it like the other project", "take the logic/structure from X".

### Workflow skills (interactive: from idea to spec to tickets)

Vendored from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, see `skills/THIRD-PARTY-NOTICES.md`) and renamed; maintained here as Evelan skills. They are the human-in-the-loop counterpart to autopilot: you decide, the agent asks.

| Skill | What it does |
| --- | --- |
| `/evelan:setup-workflow-skills` | One-time per repo: issue tracker (Jira via Atlassian MCP, GitHub Issues or local markdown; Jira is proposed when `atlassian.net` or ticket keys turn up in the repo, GitHub Issues otherwise), `docs/agents/` layout |
| `/evelan:question-me` | Relentless interview to sharpen a plan or idea; in a repo it writes `CONTEXT.md` and ADRs as it goes |
| `/evelan:to-spec` | Turn the conversation into a spec on the tracker |
| `/evelan:to-tasks` | Split a spec into tracer-bullet tasks (tickets on the tracker) with blocking edges |
| `/evelan:implement` | Implement a spec or ticket, driving `evelan:tdd`, closing with `evelan:code-review` |
| `evelan:tdd` | Test-first at pre-agreed seams, vertical slices, anti-pattern list |
| `evelan:code-review` | Review a diff on Standards and Spec in parallel subagents, plus a Codex cross-model review whenever the Codex CLI is installed (one "skipped" line in the report otherwise) |
| `evelan:diagnose-bug` | Diagnosis loop for hard bugs: tight feedback loop first, regression test last |
| `evelan:domain-model`, `evelan:codebase-design` | Vocabulary references: domain terms and ADRs; deep modules and seams |
| `/evelan:improve-architecture` | Scan for deepening opportunities, HTML report, then interview |
| `/evelan:handoff` | Write a hand-off document for a fresh agent |

**Rule for autonomous work:** the plan is written with you in the loop (`/evelan:autopilot-plan`, after `/evelan:question-me` for anything with open shape questions); the run itself asks nothing.

### Autonomous work: three building blocks

Measured on real sessions (see `docs/2026-09-19-token-efficiency-review.md` and `docs/2026-09-21-autopilot-v3.md`), a model acting as coordinator over other agents cost 28% of a session and multiplied agents (33 for one ticket). Version 2.0 removed the coordinator; version 3.0 makes every run headless and chained by the runner, moves the design work into the plan, and gives headless runs a browser.

| Block | What | Status |
| --- | --- | --- |
| `/evelan:autopilot-plan` | Writes `PLAN.md` for one topic with you in the loop, on Fable (Opus is fine): resolves the ticket or spec, reads the touched files whole, asks the shape questions once, records decisions, and writes each package at code level: `path:line` anchors with the anchor line quoted, signatures, the flow as pseudo-code, test cases with input → expected, exact commands, the browser checks. Plans with three or more packages get a fresh-context review (`evelan:autopilot-plan-reviewer`, which opens every anchor). Developers run it too. | shipped |
| `/evelan:autopilot` | Executes a plan unattended in one headless context, started by the runner: gate, branch, ticket In Progress (`jira start`), per package the plan's Implementation steps test-first with the gate green and a commit, one adversarial review on the whole branch (`evelan:autopilot-reviewer`), Codex cross-model review, the goal artifact exercised in the running app through `agent-browser` (headless, logged in via a saved state file where needed), `REPORT.md`, optional full gate (`gateFull`) before the push, PR with CI watched and the Claude review bot answered, ticket comment with the result. Outgrows its context → `HANDOFF.md`, and the runner starts the next session (up to five times). In an interactive session `/autopilot <session dir>` only enqueues and starts the runner. | shipped |
| `mission-control` | A script, not a model: runs `/autopilot` for every item of a machine-wide list and for every open PR labelled `autopilot-ready` in the configured repos, one after another, each in its own worktree, restarting after a hand-off, then marks the PR ready, swaps the label to `autopilot-done` or `autopilot-blocked`, posts the report and notifies (macOS with a sound, Slack). `mission-control start` runs the queue now inside the GUI session (installs its LaunchAgent on demand); `install-schedule 22:00` adds the nightly run. Docs: `skills/autopilot/references/mission-control.md`. | shipped |
| `/evelan:mission-control` | The control surface for that script from any Claude session: status (running item with its current package, the run's last tool call and context size, and the diff size), add, retry, stop, log, start, pause, doctor, schedule. Runs locally, or over SSH on the machine named in `~/.claude/mission-control/host`; a machine with a `host` file may run its own queue as well (status shows both). | shipped |

### autopilot

**Quickstart (once per project, then per ticket):**

```bash
# once per project: gate, hooks, review-bot label, agent-browser, jira
claude
> /autopilot init

# per ticket, in your normal session (Fable or Opus): the plan, with you in the loop
> /autopilot-plan WEB-1095

# then the run: on a machine with a queue, this enqueues and starts the runner
> /autopilot docs/autopilot/sessions/<date>-WEB-1095-<slug>
```

The run ends with a PR (or, in feature-branch mode, a pushed branch), `REPORT.md` in the session folder, a comment on the ticket and the `autopilot-usage` table in the item log. No interactive run: the runner (`mission-control`) starts every session and restarts it after a hand-off.

**Mission control.** The queue script is `mission-control` (plugin `bin/`). Setup once per queue machine (the office Mini for the nightly run and labelled PRs; the MacBook for runs started from a session): `mission-control doctor` (login, `gh`, labels), `~/.claude/mission-control/repos.txt` with one repo path per line (empty on the MacBook, so labelled PRs are processed by the Mini only), `~/.claude/mission-control/env` (mode 600) with `SLACK_WEBHOOK_URL` (a Slack app with "Incoming Webhooks" for the target channel, created once by a workspace admin; the URL goes only into that file, never into a chat or a ticket; without it notifications are macOS-only plus the PR comment), then `mission-control install-schedule 22:00` on the Mini. On the MacBook `~/.claude/mission-control/host` holds `office-mini`: `/evelan:mission-control` runs commands locally by default and on the Mini over SSH when you say "auf dem Mini"; `status` shows both queues. `mission-control pause [until <date> | <N>d]` skips the nightly run through that day (`start` still works), `resume` lifts it. On a machine without `~/.claude/mission-control` (a developer with the plugin) the skill and the queue commands refuse and point to the Mini and to `/autopilot-plan`. Commands and files: `skills/autopilot/references/mission-control.md`.

**Hand it to the queue instead of running it here:** at the end of `/autopilot-plan` answer "hand to the queue". The skill pushes the branch and opens a draft PR with the label `autopilot-ready`; the queue on the office Mini picks it up on its nightly run and reports back on the PR (label `autopilot-done` or `autopilot-blocked`, report comment) and in Slack. A topic without a ticket is fine: the plan skill creates the ticket through the project's tracker first.

**Browser in a headless run:** `agent-browser` (Vercel; `npm install -g agent-browser`, then `agent-browser install`). The run opens routes, reads accessibility snapshots, drives forms, reads console, errors and network, takes one screenshot per screen into the session folder. Projects with a login get a state file saved once by hand (`agent-browser --headed open <login url>`, log in, `agent-browser state save ~/.claude/autopilot/<repo>/state.json`) and referenced as `browserState` in `.claude/autopilot.json`; `/autopilot init` prints the recipe. Commands: `skills/autopilot/references/browser.md`.

**Ticket updates in a headless run:** the `jira` script (plugin `bin/`; `jira doctor | view | start | comment | transition | assign`), reading `~/.claude/jira/env` (mode 600: `JIRA_SITE`, `JIRA_EMAIL`, `JIRA_TOKEN`; optional `JIRA_START_STATUS`, default `In Progress|In Arbeit`). The run calls `jira start <KEY>` before its first commit and `jira comment <KEY> -` with the report head at the end; it never moves a ticket to a done or merged status. Without the env file the run says so in `REPORT.md` and touches no ticket. Python 3, standard library only; the token stays in memory and never reaches a command line, a temp file or the output.

**Usage details:**
- Prepare: `/autopilot-plan WEB-1095` (or a spec file, or a topic) → `docs/autopilot/sessions/<date>-<slug>/PLAN.md`, committed on the run's branch. Template: `skills/autopilot-plan/references/plan-template.md`.
- Run: `/autopilot docs/autopilot/sessions/<date>-<slug>` enqueues and starts the runner; the runner launches `claude -p` with `--model sonnet --effort <plan header> --advisor fable --fallback-model opus --max-budget-usd 60`. A ticket key also works when its plan exists. Without a plan the run writes one itself with conservative decisions and no questions.
- Docs are part of done: the run updates README, `docs/`, `CLAUDE.md`/`.claude/rules/` and doc comments the change made stale, and the reviewer flags a stale document as a gap.
- Options in the prompt: "defer PR" (no push, no PR), "ohne Codex" / "no Codex" (skips the Codex cross-model review, which otherwise runs by default after the Claude review whenever the Codex CLI is installed; its findings are fixed or rebutted in `REPORT.md`).
- Write-less rules are part of the skill (vendored from Ponytail, see `skills/THIRD-PARTY-NOTICES.md`): reuse before write, stdlib and platform before dependencies, shortest root-cause diff, no speculative abstractions.
- A step of the plan that does not fit the code any more (moved anchor, changed signature) is corrected with the smallest change and recorded in `DECISIONS.md` with the step number.

**Hand-off instead of compaction.** When the context-budget hook reports the budget (default 500k tokens, `contextBudget` in `.claude/autopilot.json`), the run commits, writes `HANDOFF.md` (state, verified evidence, open items, exact next step) and ends its turn. The runner starts the next session, which continues from `HANDOFF.md`; up to five restarts per item. Auto-compaction is never relied on.

**Context hygiene is part of the skill:** bounded reads, tailed outputs, one plan read, full gate once per package, one review per session.

**Per-project hooks:** `/autopilot init` sets up four deterministic hooks in the current project. The `Stop` hook blocks a run from ending a turn while the gate (typecheck/lint/test) is red (sentinel-guarded, inert otherwise). The `PreToolUse` gate filter rewrites test/lint/typecheck/build commands so the model sees failures plus the summary instead of the full runner output, keeps the exit status, and appends an evidence line to `.claude/autopilot-gate.log`, which the reviewer may accept instead of re-running the suite. The `PostToolUse` context-budget hook measures the context the next turn will carry from the transcript of the agent it runs in, rewrites `.claude/.autopilot-status` after every tool call (shown by `mission-control status`, read by the watchdog as a liveness signal) and, above the budget, injects the hand-off instruction, naming the measured file. The `SessionStart` hook (matcher `compact`) re-injects the session folder pointer if compaction happens anyway. Init auto-detects the package manager, writes the gate to `.claude/autopilot.json` (plus `gateFull` when the project has a full gate script), copies the hooks into `.claude/hooks/`, safe-merges them into `.claude/settings.json`, checks `agent-browser` and `jira doctor`, and checks for the Claude review workflow and its `claude-re-review` label (created when missing). The filter and budget hooks need `jq`; put `# raw` in a command to bypass the filter.

**Artifacts:** each session writes to `docs/autopilot/` (committed, part of the PR): an `INDEX.md` history plus a per-session folder with `PLAN.md`, `DECISIONS.md`, `HANDOFF.md` (transient), `REPORT.md`, `MANUAL_TESTING.md` and `screenshots/`.

**Measuring a session:** `autopilot-usage <main transcript.jsonl>` (plugin binary on PATH, needs `jq`) prints one line per agent of a session: API requests, first/last/max context, cache reads, cache writes, output. Every run prints it at the end.

**Trigger phrases:** "/autopilot", "autopilot", "autonom umsetzen", "autonome Session", "arbeite das selbstständig ab"


### preview

Switches to the `preview` development branch, pulls the latest changes, and optionally cleans up the branch you were on.

**Features:**
- Warns about uncommitted changes first and offers stash / discard / abort
- `git fetch --prune`, then detects when the current branch is gone on the remote
- Offers to delete the old local branch after switching
- Prints a short summary of what changed

**Trigger phrases:** "Wechsel zu Preview", "switch to preview", "checkout preview", "geh auf preview", "zurück zu preview", "pull preview", "/preview"

### codex-imagegen

Generates raster images (hero shots, product mockups, illustrations, textures, icons, social/OG cards, backgrounds) by delegating to the Codex CLI's built-in imagegen skill, which runs OpenAI's gpt-image-2 model. Manually invoked only.

**Features:**
- Structured image brief (use case, subject, composition, lighting, palette, exact text, constraints)
- Runs Codex headless in auto-review mode; robust file copy-out if the sandbox blocks Codex's own write
- Reference images via `--image` for edits and compositing (e.g. a real UI screenshot onto a device screen)
- Sizing guidance and a chroma-key path for cutouts with transparency

**Trigger phrases:** "codex-imagegen", "generate images with Codex", "through the Codex CLI", "using gpt-image-2". Does not auto-trigger on a generic image request unless tied to Codex.

### codex-review

Cross-model code review: delegates a review of your local diff to the Codex CLI (`codex review`) and relays its findings verbatim - no summarizing, no filtering, no auto-fixing. Useful as an independent second opinion next to the normal Claude review flow, which stays untouched.

**Features:**
- Scope auto-detection: dirty tree -> `--uncommitted`, clean feature branch -> `--base <default branch>`, or a specific `--commit <sha>` - an explicit argument always wins
- Preflight guards: Codex binary resolution, git-repo check, empty-diff abort (no wasted model calls)
- Runs in the background with a log file (reviews can take minutes); the untouched log path is always reported
- Output is passed through raw - only tool-call noise and sandbox warnings are stripped
- Falls back to a normal Claude review when Codex is rate-limited or unavailable (standalone use only; when `code-review` or `autopilot` call it, they already have a Claude review and just record the skip)
- Optional model choice - say "mit Astra" / "mit Sol" / "nutze Luna" and the slug is resolved and validated against the live Codex catalog before the run (hidden catalog entries are never offered)
- Never fixes anything on its own; asks which findings to act on

**Usage:** `/codex-review [--uncommitted | --base <branch> | --commit <sha>] [--model <name>] [focus instructions]`

**Trigger phrases:** "Codex-Review", "lass Codex reviewen", "lass Codex drüberschauen", "zweite Meinung von Codex", "Cross-Model-Review". A generic "review this" does NOT trigger it.

### codex-ask

General-purpose delegation to the Codex CLI (`codex exec`): writes a structured brief (goal, context, constraints, expected result, definition of done), runs Codex in the `workspace-write` sandbox with auto-review escalations, and reports back the answer plus everything Codex changed on disk.

**Features:**
- Structured stdin brief - Codex has no access to the conversation, so the skill briefs it properly instead of forwarding a one-liner
- Write-safety: git state recorded before the run, dirty-tree warning, post-run `git status` + diffstat so changes are never silent
- Clean final answer captured via `-o` and relayed verbatim
- Optional `--output-schema` for structured JSON answers
- Optional model choice - name a model ("nutze Astra", "mit Sol", "nutze Luna") and it is resolved to a real slug and validated against the live Codex catalog before the run, instead of failing with a backend 400 minutes in
- Never auto-triggered - only when you explicitly route work to Codex

**Trigger phrases:** "frag Codex", "was sagt Codex zu ...", "lass Codex das machen", "delegiere das an Codex", "ask Codex", "delegate this to Codex"

### e2e-demo

Verifies a finished task against the real running system instead of a read-through of the code, then produces a narrated MP4 and a published web-artifact report from that real run. Two tracks: a real E2E test (Playwright or whatever the project already uses) for browser-facing changes, or a real recorded terminal session (`asciinema` + `agg`) for CLI/infra work like Docker setups and install instructions - either or both, concatenated as sequential cuts when a task needs both.

**Features:**
- Real run first, always - an E2E test against the real app, or the actual documented commands actually executed, never a mock or a read-through
- Assertions read back real persisted state (DB row, API response), never just a UI toast or a zero exit code
- Narrated MP4: real video (test framework's own recording, or a terminal session rendered via `agg`) + real synthesized voice from a self-hosted TTS server (`openai-edge-tts` recommended - no OpenAI account or billing)
- Narration and the artifact's results table are derived strictly from what the run actually proved - nothing narrated that wasn't checked
- Human-gated steps (a real browser login, an approval) are named plainly, never faked or automated around
- Published artifact: goal/issue, what changed, a results table, real screenshots, the narration script
- Project-agnostic - finds and follows whatever E2E/testing conventions the current project already has rather than assuming Playwright, a specific fixture pattern, or a specific report publisher

**Trigger phrases:** "test this properly", "make sure this works", "show me a demo", "I want a report for this", "verify the instructions actually work for a client", "teste das richtig", "zeig mir eine Demo", "beweise dass das funktioniert", "ich will einen Report dazu"

## Contributing to this plugin

Before a release: `sh bin/plugin-lint` (frontmatter, reference files, `evelan:` cross-references, agents list, em dashes, README coverage, removed concepts), then every `bin/*.test.sh` and `skills/autopilot/hooks/*.test.sh` with bash, then `claude plugin validate .` and the version bump in `.claude-plugin/plugin.json`. Helpers in `bin/` are POSIX sh with a test next to each.
