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

### autopilot

Runs an autonomous, unattended development loop for **one topic per session**: spec → plan → TDD implementation → adversarial review → quality gate → PR (CI watched until green).

**Usage:**
- Run a task: `/autopilot <task, ticket key, or spec file>`
  e.g. `/autopilot DNA-901 add rate limiting to the contact route`
- Cost-efficient implementation (delegates coding to a Sonnet subagent): add "with sonnet" / "kosteneffizient" / "schnell" to the prompt.
- Thorough review (adds clean-code + reusability lenses): add "thorough review".

The orchestrator runs at your **session model** (Opus recommended). Review always runs on Opus (`evelan:autopilot-reviewer`); implementation delegates to `evelan:autopilot-implementer` (Sonnet) only when you ask for it.

**Optional hard gate (per project):** `/autopilot init` sets up a deterministic `Stop` hook in the current project that blocks the model from ending a turn while the gate (typecheck/lint/test) is red. It auto-detects the package manager (npm/pnpm/yarn/bun), writes the gate to `.claude/autopilot.json`, copies the hook into `.claude/hooks/`, and safe-merges the hook into `.claude/settings.json` (idempotent, never overwrites). The hook is inert outside autopilot runs (sentinel-guarded).

**Artifacts:** each session writes to `docs/autopilot/` (committed, part of the PR): an `INDEX.md` history plus a per-session folder with `PLAN.md`, `DECISIONS.md`, `REPORT.md`, and `MANUAL_TESTING.md`.

For unattended runs, launch with `--permission-mode auto`.

**Trigger phrases:** "/autopilot", "autopilot", "autonom umsetzen", "autonome Session", "arbeite das selbstständig ab"

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
