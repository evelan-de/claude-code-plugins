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

Measured on real sessions (see `docs/2026-09-19-token-efficiency-review.md`), a model acting as coordinator over other agents cost 28% of a session and multiplied agents (33 for one ticket). Anthropic's own guidance says multi-agent setups pay off for parallel research, not for coding. Version 2.0 therefore has no coordinator model: a plan skill, an executor, and a script.

| Block | What | Status |
| --- | --- | --- |
| `/evelan:autopilot-plan` | Writes `PLAN.md` for one topic with you in the loop: resolves the ticket or spec, explores with bounded reads, asks the shape questions once, records decisions, lists packages with seams and verification criteria, commits the plan. Developers run it too. Optional fresh-context plan review (`evelan:autopilot-plan-reviewer`). | shipped |
| `/evelan:autopilot` | Executes a plan unattended in one context: gate, branch, per package test-first with the gate green and a commit, one adversarial review on the whole branch (`evelan:autopilot-reviewer`), the goal artifact exercised in the running app, `REPORT.md`, optional full gate (`gateFull`) before the push, PR with CI watched and the Claude review bot answered (findings fixed or rebutted, re-review requested via label). Outgrows its context → `HANDOFF.md` and a fresh session resumes. No sub-agents for implementation. | shipped |
| `autopilot-queue` | A script, not a model: takes a list of prepared sessions (or tickets) and runs `/autopilot` for each in turn, in a worktree, restarting on hand-off, notifying you on completion or blockers. Zero tokens for coordination. | design in `docs/2026-09-20-autopilot-v2.md`, format to be agreed |

### autopilot

**Quickstart (once per project, then per ticket):**

```bash
# once per project: gate, hooks, review-bot label
claude
> /autopilot init

# per ticket, in your normal session: the plan, with you in the loop
> /autopilot-plan WEB-1095

# then the run, in a fresh terminal (the plan's hand-over prints this exact line)
claude --model sonnet --effort medium --advisor fable --fallback-model opus --permission-mode auto
> /autopilot docs/autopilot/sessions/<date>-WEB-1095-<slug>
```

The run ends with a PR (or, in feature-branch mode, a pushed branch), `REPORT.md` in the session folder and the `autopilot-usage` table. If it ran out of context it ends with `Resume with /autopilot <session directory>`: start a fresh session and paste that line.

**Usage details:**
- Prepare: `/autopilot-plan WEB-1095` (or a spec file, or a topic) → `docs/autopilot/sessions/<date>-<slug>/PLAN.md`, committed on the run's branch.
- Run: `/autopilot docs/autopilot/sessions/<date>-<slug>` in a fresh session started with the launch line above. Model, effort and advisor are launch parameters (a mid-run switch throws away the cache); effort defaults to `medium` for autopilot runs and is written into the plan header. Turn and dollar caps (`--max-turns`, `--max-budget-usd`) exist only in headless mode (`claude -p`), which the queue runner uses. A ticket key also works when its plan exists. Without a plan the run writes one itself with conservative decisions and no questions.
- Docs are part of done: the run updates README, `docs/`, `CLAUDE.md`/`.claude/rules/` and doc comments the change made stale, and the reviewer flags a stale document as a gap.
- Options in the prompt: "defer PR" (no push, no PR), "ohne Codex" / "no Codex" (skips the Codex cross-model review, which otherwise runs by default after the Claude review whenever the Codex CLI is installed; its findings are fixed or rebutted in `REPORT.md`).
- Write-less rules are part of the skill (vendored from Ponytail, see `skills/THIRD-PARTY-NOTICES.md`): reuse before write, stdlib and platform before dependencies, shortest root-cause diff, no speculative abstractions. JetBrains measured about 10% lower cost with unchanged quality when the rules sit in the context for the whole session, which is what the skill does.
- Continue after a hand-off: the same command; the run finds `HANDOFF.md`.

**Hand-off instead of compaction.** When the context-budget hook reports the budget, the run commits, writes `HANDOFF.md` (state, verified evidence, open items, exact next step) and ends its turn with `Resume with /autopilot <session directory>`. Auto-compaction is never relied on.

**Context hygiene is part of the skill:** bounded reads, tailed outputs, one plan read, full gate once per package, one review per session.

**Optional per-project hooks:** `/autopilot init` sets up four deterministic hooks in the current project. The `Stop` hook blocks a run from ending a turn while the gate (typecheck/lint/test) is red (sentinel-guarded, inert otherwise). The `PreToolUse` gate filter rewrites test/lint/typecheck/build commands so the model sees failures plus the summary instead of the full runner output, keeps the exit status, and appends an evidence line to `.claude/autopilot-gate.log`, which the reviewer may accept instead of re-running the suite. The `PostToolUse` context-budget hook measures the context the next turn will carry from the transcript of the agent it runs in and, above the budget (default 250k, `contextBudget` in `.claude/autopilot.json`), injects the hand-off instruction, naming the measured file. The `SessionStart` hook (matcher `compact`) re-injects the session folder pointer if compaction happens anyway. Init auto-detects the package manager, writes the gate to `.claude/autopilot.json` (plus `gateFull` when the project has a full gate script), copies the hooks into `.claude/hooks/`, safe-merges them into `.claude/settings.json`, and checks for the Claude review workflow and its `claude-re-review` label (created when missing). The filter and budget hooks need `jq`; put `# raw` in a command to bypass the filter.

**Artifacts:** each session writes to `docs/autopilot/` (committed, part of the PR): an `INDEX.md` history plus a per-session folder with `PLAN.md`, `DECISIONS.md`, `HANDOFF.md` (transient), `REPORT.md`, and `MANUAL_TESTING.md`.

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
