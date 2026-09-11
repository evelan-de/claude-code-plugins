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

Smart dependency updater using ncu (npm-check-updates). Goes beyond simple version bumps — for major updates, it researches breaking changes and can auto-migrate your code.

**Features:**
- Automatic `ncu` installation check (offers global install or npx fallback)
- Dry-run preview before any changes
- Parallel subagent research for major updates — finds breaking changes and migration guides
- Per-package opt-out after reviewing breaking changes
- Two execution modes:
  - **Apply now** — updates packages and auto-migrates code based on migration guides
  - **Create plan** — writes a detailed migration plan to `docs/plans/` for later execution
- Always pins exact versions (no `^` or `~`)
- Runs build/test/lint after migrations to catch regressions

**Trigger phrases:** "update dependencies", "aktualisiere dependencies", "upgrade packages", "check outdated", "Pakete aktualisieren"

### port-from-repo

Controlled, exact-copy workflow for porting a component, style, layout, or feature from one repo into another. Kills the failure mode of approximating from memory instead of reading and copying the real source.

**Two modes, separable by instruction:**
- **exact** - reproduce look AND behaviour verbatim (copy classes and tokens as-is; verify in-browser against the source)
- **structure-only** - take the logic/structure/ideas, but restyle with THIS project's own design system

**Workflow it enforces:** read the source in full first (component + its base primitives + tokens) -> delta-check the target's existing tokens/primitives and any divergent global CSS -> treat "looks wrong everywhere" as a global/token cause (measure computed style) -> verify visually in the logged-in browser before claiming done.

**Usage:** `/port-from-repo [exact | structure-only] <what to port + source repo>`

**Trigger phrases:** "port from X", "übernimm das aus X", "wie in Jexity", "1:1", "make it like the other project", "take the logic/structure from X".

### autopilot

Runs an autonomous, unattended development loop for **one topic per session**: spec → plan → TDD implementation → adversarial review → quality gate → PR (CI watched until green).

**Usage:**
- Run a task: `/autopilot <task, ticket key, or spec file>`
  e.g. `/autopilot DNA-901 add rate limiting to the contact route`
- Cost-efficient implementation (delegates coding to a Sonnet subagent): add "with sonnet" / "kosteneffizient" / "schnell" to the prompt.
- Thorough review (adds clean-code + reusability lenses): add "thorough review".
- Coordinated runs (mission-control dispatches always do this): add "defer PR" — the session never pushes and never opens a PR; the coordinator owns push, PR and CI after its own verification. A prepared session directory (`docs/autopilot/sessions/<slug>/` with `PLAN.md`) can be passed as input and is adopted verbatim.

The session lead runs at your **session model** — standalone that is whatever you started the session with; dispatched by mission-control it is the model the coordinator passes (Opus). Review always runs on Opus (`evelan:autopilot-reviewer`); implementation delegates to `evelan:autopilot-implementer` (Sonnet) only when you ask for it.

**Optional hard gate (per project):** `/autopilot init` sets up a deterministic `Stop` hook in the current project that blocks the model from ending a turn while the gate (typecheck/lint/test) is red. It auto-detects the package manager (npm/pnpm/yarn/bun), writes the gate to `.claude/autopilot.json`, copies the hook into `.claude/hooks/`, and safe-merges the hook into `.claude/settings.json` (idempotent, never overwrites). The hook is inert outside autopilot runs (sentinel-guarded).

**Artifacts:** each session writes to `docs/autopilot/` (committed, part of the PR): an `INDEX.md` history plus a per-session folder with `PLAN.md`, `DECISIONS.md`, `REPORT.md`, and `MANUAL_TESTING.md`.

For unattended runs, launch with `--permission-mode auto`.

**Trigger phrases:** "/autopilot", "autopilot", "autonom umsetzen", "autonome Session", "arbeite das selbstständig ab"

### mission-control

Coordinates an autonomous development session **without implementing anything itself**: it
resolves the task and pins down the user-verifiable **goal artifact** (feature running in
the local app, a generated report, a finished PDF, …), prepares the autopilot session
folder (`docs/autopilot/sessions/<slug>/PLAN.md`) in the main context, has the plan
reviewed by a fresh-context agent **and** cross-model via `evelan:codex-ask` (fixing the
findings itself), then dispatches **one** background implementation subagent (**Opus model
override**, general-purpose type) that runs `evelan:autopilot` on that session directory
with "nutze Codex als Reviewer" and **"defer PR"**. A ~10-minute watchdog nudges a stalled
agent and replaces it if it stays stuck. At the end mission control verifies the result
independently (re-runs the gate, exercises the goal artifact), and only then pushes, opens
the PR and watches CI — red CI goes back to the subagent as file-level instructions. The
final report uses simplified technical language (ASD-STE100 style) in the language of the
user's prompt.

**Usage:** `/mission-control <task, ticket key, or spec file>`

Best started with the strongest available session model (Fable 5) — the skill plans in the
main context and cannot switch the session model itself — and with a permissive permission
mode (e.g. `--permission-mode auto`), which the dispatched subagents inherit.

**Trigger phrases:** "/mission-control", "mission control", "orchestriere", "als Orchestrator", "Orchestrator-Session", "koordiniere die Umsetzung"

### reflect-on-changes

Runs a short self-reflection check after a round of code changes is complete, before declaring the work done. Forces Claude to honestly interrogate its own work — surfacing what it's least confident about and what it might be missing — so problems get caught before the user finds them.

**Features:**
- Triggers automatically after meaningful changes (features, refactors, bug fixes, multi-file edits) — not for trivial one-line tweaks
- Answers two grounded questions before the closing summary:
  - **What am I least confident about?** — a specific function, assumption, untested path, or guessed dependency
  - **What might I be missing?** — unstated context, ambiguous requirements, team conventions, or unknown unknowns
- Presented as a short, clearly-labeled section with no vague hedging
- Escalates real concerns into a proposed fix or a question instead of burying them in a checklist

**Trigger phrases:** "done", "finished", "that should do it", "ready for review", "let me know what you think"

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
- Falls back to a normal Claude review when Codex is rate-limited or unavailable (never leaves you with no review)
- Never fixes anything on its own; asks which findings to act on

**Usage:** `/codex-review [--uncommitted | --base <branch> | --commit <sha>] [focus instructions]`

**Trigger phrases:** "Codex-Review", "lass Codex reviewen", "lass Codex drüberschauen", "zweite Meinung von Codex", "Cross-Model-Review". A generic "review this" does NOT trigger it.

### codex-ask

General-purpose delegation to the Codex CLI (`codex exec`): writes a structured brief (goal, context, constraints, expected result, definition of done), runs Codex in the `workspace-write` sandbox with auto-review escalations, and reports back the answer plus everything Codex changed on disk.

**Features:**
- Structured stdin brief - Codex has no access to the conversation, so the skill briefs it properly instead of forwarding a one-liner
- Write-safety: git state recorded before the run, dirty-tree warning, post-run `git status` + diffstat so changes are never silent
- Clean final answer captured via `-o` and relayed verbatim
- Optional `--output-schema` for structured JSON answers
- Never auto-triggered - only when you explicitly route work to Codex

**Trigger phrases:** "frag Codex", "was sagt Codex zu ...", "lass Codex das machen", "delegiere das an Codex", "ask Codex", "delegate this to Codex"

### e2e-demo

Verifies a finished task against the real running system instead of a read-through of the code, then produces a narrated MP4 and a published web-artifact report from that real run. Two tracks: a real E2E test (Playwright or whatever the project already uses) for browser-facing changes, or a real recorded terminal session (`asciinema` + `agg`) for CLI/infra work like Docker setups and install instructions — either or both, concatenated as sequential cuts when a task needs both.

**Features:**
- Real run first, always — an E2E test against the real app, or the actual documented commands actually executed, never a mock or a read-through
- Assertions read back real persisted state (DB row, API response), never just a UI toast or a zero exit code
- Narrated MP4: real video (test framework's own recording, or a terminal session rendered via `agg`) + real synthesized voice from a self-hosted TTS server (`openai-edge-tts` recommended — no OpenAI account or billing)
- Narration and the artifact's results table are derived strictly from what the run actually proved — nothing narrated that wasn't checked
- Human-gated steps (a real browser login, an approval) are named plainly, never faked or automated around
- Published artifact: goal/issue, what changed, a results table, real screenshots, the narration script
- Project-agnostic — finds and follows whatever E2E/testing conventions the current project already has rather than assuming Playwright, a specific fixture pattern, or a specific report publisher

**Trigger phrases:** "test this properly", "make sure this works", "show me a demo", "I want a report for this", "verify the instructions actually work for a client", "teste das richtig", "zeig mir eine Demo", "beweise dass das funktioniert", "ich will einen Report dazu"
