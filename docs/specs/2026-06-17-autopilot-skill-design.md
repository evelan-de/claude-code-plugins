# Autopilot Skill — Design

**Date:** 2026-06-17
**Status:** Approved design, ready for implementation plan
**Repo:** `claude-code-plugins` (the `evelan` plugin / marketplace)

## 1. Goal

Replace the current ad-hoc `~/.claude/commands/autopilot.md` with a shareable,
team-installable **`autopilot` skill** inside the `evelan` plugin. The skill runs an
autonomous development loop — spec → plan → TDD implementation → adversarial review →
quality gate → commit → PR → CI — for a single topic per session, with no human in the
loop, and packages an optional hard quality gate that teammates can enable per project.

The workflow `/autopilot <task>` stays the entry point the user already likes: open a
session, type the command, walk away. No shell launcher required.

### Why a rewrite

The current command was built quickly. This design folds in the strong ideas from the
"v2 kit" (adversarial fresh-context reviewer, deterministic Stop-hook gate,
evidence-over-assertion, reversible-action safety) and current Anthropic guidance on
orchestrator-worker architectures, while dropping the parts that do not fit the user's
workflow (shell launchers, `caffeinate`, a multi-task queue).

## 2. Form factor — one skill, two actions

A single skill `skills/autopilot/` routed by its `$ARGUMENTS`:

- **Run mode** (default): `/autopilot <task>` → the autonomous loop for one topic.
- **Init mode**: `/autopilot init` → set up the optional hard gate (Stop hook) in the
  *current* project.

The skill is `user-invocable`, so the team can type `/autopilot ...`, and it can also be
context-triggered via its description. The old `~/.claude/commands/autopilot.md` is removed.

## 3. Plugin layout

All component directories live at the plugin root (never under `.claude-plugin/`).

```
agents/                          # plugin root — auto-registered as evelan:autopilot-*
  autopilot-reviewer.md          # Opus — adversarial review, fresh context
  autopilot-implementer.md       # Sonnet — TDD implementation, escalates on uncertainty
skills/autopilot/
  SKILL.md                       # orchestrator workflow + routing (run | init)
  hooks/
    autopilot-gate.sh            # deterministic gate script (template, copied by init)
  references/
    settings-snippet.json        # the Stop-hook block init merges into a project
    init.md                      # detailed init procedure (kept out of SKILL.md to stay lean)
```

`plugin.json` already exposes `skills: "./skills/"`. The two subagents live at the **plugin
root `agents/`** so they auto-register as named agents with guaranteed `model:` frontmatter
(`evelan:autopilot-reviewer` = Opus, `evelan:autopilot-implementer` = Sonnet); the SKILL.md
dispatches them by name. The Stop-hook script is **not** registered as a plugin hook (plugin
hooks auto-register globally, which we do not want — see §7); it ships as a template that
`/autopilot init` copies into each project's `.claude/hooks/`.

## 4. Model orchestration

Grounded in Anthropic's
[multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system):
one capable orchestrator delegating to cheaper workers, workers flagging uncertainty back up.

- **Orchestrator = the session model (Opus by default).** The main session model is fixed
  for the session and cannot be switched mid-run, so the orchestrator always runs at
  whatever the user started with. It owns: explore, spec, plan, review adjudication, every
  real decision, commit/PR/CI.
- **Implementation model is conditional.** By default the orchestrator implements directly.
  **Only when the task prompt signals cost/speed intent** — "with Sonnet", "cost-efficient",
  "cheap", "fast" (DE: "mit Sonnet", "kosteneffizient", "schnell", "günstig") — each work
  package is delegated to a fresh **Sonnet** subagent (`autopilot-implementer`).
- **Review = Opus subagent** (`autopilot-reviewer`) in a fresh context.

### Escalation pattern

There is no built-in "worker calls Opus" mechanism. The implementer subagent is instructed
to **never guess** on hard or ambiguous decisions. Instead it either:
1. makes the **conservative, easily-reversible** choice and records it in `DECISIONS.md`, or
2. returns a structured result with `needs_review: true` plus the open question.

The Opus orchestrator inspects every subagent result and resolves any flagged item itself
before accepting the package.

Subagent model is set via the `model:` frontmatter field (`opus` / `sonnet` / `inherit`)
and/or a per-invocation model override when the orchestrator spawns the agent.

## 5. Run-mode workflow

One session works **one topic** end to end. Phases run in order per work package; trivial
one-line tasks may collapse phases.

0. **Resolve input (cascade).** Decide what to build before touching anything:
   1. A spec is provided in the prompt / referenced as a file / already exists in the repo
      (`SPEC.md` or equivalent) → use it.
   2. Only a rough idea → write a self-contained spec first (problem/goal, scope + explicit
      non-goals, functional requirements with acceptance criteria, affected areas, edge and
      error cases). Open questions are answered with conservative assumptions → `DECISIONS.md`.
   3. **No task given at all** → derive the task from project context (open TODOs, leftover
      plan files, issues, obviously unfinished features), record the choice in `DECISIONS.md`,
      then proceed as in (2).
1. **Project context & gate commands.** If `.claude/autopilot.json` exists (from a prior
   `init`), use its `gate` as the source of truth. Otherwise detect the package manager and the
   **exact** lint / typecheck / test / build commands the same way `init` does (see §7) from
   `package.json`, `CLAUDE.md`, and tool configs — never assume, look them up. If a piece is
   missing (e.g. no test runner configured), set it up minimally and project-consistent
   **before** implementation, so TDD can run in the first package. Existing project conventions
   take precedence over general best practices.
2. **Branch.** Create a single session branch following the project's existing convention —
   never multiple branches per session.
   - **Prefix:** infer the project's usual feature-branch prefix from existing branches /
     git history (`git branch -a`, recent merged branch names); fall back to `feature/` when
     none is detectable.
   - **Ticket:** if the prompt contains a ticket key (e.g. `DNA-901`, `WEB-123`, `PAUL-…`,
     `EL-…`), include it (original casing) → `<prefix>/DNA-901-<slug>`. Otherwise
     `<prefix>/<slug>`.
   - **Slug:** lowercase, hyphen-separated, derived from the topic.
3. **Explore (read-only).** Delegate wide reading to a subagent so it does not flood the
   orchestrator context. Report files, patterns, risks — not full file contents.
4. **Plan → `PLAN.md`.** Self-contained: files/interfaces touched, explicit out-of-scope,
   concrete **verification criteria** (test cases with inputs/expected outputs, expected
   typecheck/lint/build result), and an **end-to-end check**. Break work into small,
   dependency-ordered packages with per-package Definition of Done and a status marker
   (`[ ]` / `[~]` / `[x]` / `[!]`).
5. **Implement (TDD).** Failing test first (confirm it fails for the right reason), then
   implement to green, then refactor. Everything sensibly unit-testable gets tests
   (utilities, hooks, business logic, data transforms, API handlers, validation); UI
   components are tested by behavior, not implementation detail. Run the **cheap gate**
   (typecheck/lint/**full** test suite, not just the new tests) after each meaningful change
   and **show the output** as evidence — never assert success. In Sonnet mode this package is
   delegated to `autopilot-implementer`.
6. **Review (fresh context, hybrid depth).**
   - **Always:** the adversarial `autopilot-reviewer` sees only the diff + `PLAN.md`. Order:
     Requirements → Verification → Correctness (incl. security) → Scope → Safety. It
     **re-runs the gate itself**. It reports only correctness/requirement/safety gaps, never
     style nits or speculative hardening. Verdict `PASS | GAPS`.
   - **On demand:** when the prompt asks for it ("thorough review", "architecture review",
     "Code-Qualität") or the diff is large, the orchestrator additionally fans out
     **clean-code** and **reusability** lenses as parallel Opus subagents, each with fresh
     context. Their findings are prioritized (critical / important / nice-to-have); only
     critical and important ones are fixed, nice-to-have are recorded in `REPORT.md` with a
     rationale.
   - Fix every real gap test-driven, then re-gate. Max 2 review cycles; unresolved real gaps
     after 2 → package marked `[!]`, logged, move on.
7. **Full gate + commit.** Run cheap gate + `build`, paste the summary. Only if fully green:
   commit (Conventional Commits, referencing the topic/issue key).
8. **Per-package journaling.** Keep `PLAN.md` / `DECISIONS.md` current.

At session end (the topic is fully implemented):

9. **UI / E2E verification (when applicable).** Runs only when **all three** hold:
   (a) the change is a **web UI**, (b) the project exposes a **locally startable dev server**
   (e.g. `npm run dev`), and (c) a **browser tool is available** in the session (Chrome plugin
   / browser MCP / Preview MCP). If so:
   - Start the dev server in the background and wait until it is reachable.
   - Drive the actual UI through the **acceptance criteria** in `PLAN.md`: click the flows,
     submit forms with valid **and** invalid input, provoke error states, and check the
     **console and network requests** for errors.
   - Work through the browser-checkable items in `MANUAL_TESTING.md` and mark them verified.
   - Treat findings like review gaps: fix test-driven, re-gate, re-verify in the browser.
   - Stop the dev server cleanly afterwards.
   If any precondition is not met (not a web UI, no dev server, no browser tool, server won't
   start) → **skip silently**, note the reason in `REPORT.md`, and continue. This step is
   **never a blocker**.
10. **PR + CI.** Push the session branch and open **one PR** automatically (GitHub `gh pr
    create`; Bitbucket via API, Jira key in title where relevant). The PR is opened for review,
    **never auto-merged**. Wait for CI (`gh run watch`); on red, read
    `gh run view --log-failed`, fix, re-push, re-check — until green and **merge-ready**.
11. **Finalize `REPORT.md`** and prepend the session one-liner to `docs/autopilot/INDEX.md`.

### Decisions & stop conditions

- **No questions — decide.** On any ambiguity, make the conservative choice (least breakage,
  easiest to reverse later) and record it in `DECISIONS.md`. Only when something is genuinely
  impossible (missing credentials, no external access) mark that package `[!]`, log why, and
  continue with the next package.
- **Abort the whole session** (write `REPORT.md`, do not force progress) when: the gate cannot
  be made green without a destructive action or human input; the task would require anything on
  the "never" list (§8); or no package remains implementable. (The v2 "2 consecutive blocked
  tasks" rule does not apply — a session is a single topic, not a queue.)

## 6. Artifacts — `docs/autopilot/` (journal-style)

Modeled on the proven `journal/` system in the `website-commander` repo: an index plus one
self-contained record per session, so files never grow unbounded.

```
docs/autopilot/
  INDEX.md                                   # history: newest-first, one line + link per session
  sessions/
    YYYY-MM-DD-<slug>/                        # = the session/branch topic, self-contained
      PLAN.md            # spec + plan + verification criteria + per-package status
      DECISIONS.md       # conservative assumptions, each with rationale
      REPORT.md          # final: shipped work, test coverage, review findings (fixed +
                         #   consciously-deferred), PR link, CI status, open/blocked items
      MANUAL_TESTING.md  # only when something cannot be automatically tested
```

- During the run, `PLAN.md` and `DECISIONS.md` are living documents.
- `INDEX.md` uses an insert marker (`<!-- NEW ENTRIES GO IMMEDIATELY BELOW THIS LINE -->`);
  entries are prepended, never sorted or rewritten. Format: `- **YYYY-MM-DD HH:MM** —
  <title> — <one-line summary> — [PR](<url>) [→](./sessions/<slug>/REPORT.md)`.
- These process docs **are committed to the session branch** and are part of the PR, so a
  reviewer sees spec, decisions, and report next to the code. The `INDEX.md` history is
  versioned and team-shared.
- Each session entry carries frontmatter (date, topic tags, status, PR, branch) to support
  later search. A `TOPICS.md` auto-index is a possible later addition, not part of v1.

## 7. Quality gate — two tiers

**Tier 1 — always on, zero setup (instruction-enforced).**
Baked into every run: a task is not DONE until (a) the orchestrator ran the full gate and
showed the output, and (b) `autopilot-reviewer` returned `PASS` after re-running the gate
itself. Opus follows this reliably but it remains an instruction, not a hard guarantee.

**Tier 2 — optional per project, hard-enforced (`/autopilot init`).**
A `Stop` hook (`autopilot-gate.sh`) the Claude Code engine runs at every turn-end. While a
run is active and the gate is red, it `exit 2`s with the failure on stderr, so the model
**cannot** end the turn until the gate is green. Mechanics:

- exit 0 → allow stop; exit 2 + stderr → block and feed the failure back to the model.
- Guarded by a sentinel file (`.claude/.autopilot-active`) the skill creates at run start and
  removes at end, so **normal interactive sessions are never gated**.
- The gate command is auto-detected at `init` time and stored in `.claude/autopilot.json`,
  which the hook reads (PM-agnostic — see init detection below).
- Note: the "~8 consecutive blocks" circuit breaker from the old kit was misattributed — it
  belongs to `auto` permission mode (3 consecutive / 20 total), not to Stop hooks.

### `init` behavior (safe-merge, chosen)

`/autopilot init`:
1. **Detect the package manager** (authoritative order, first hit wins):
   1. `packageManager` field in `package.json` (corepack standard: `pnpm@…` / `yarn@…` / `npm@…` / `bun@…`).
   2. Lockfile present: `pnpm-lock.yaml` → pnpm; `yarn.lock` → yarn; `bun.lockb` / `bun.lock` → bun;
      `package-lock.json` → npm.
   3. Fallback → `npm`.
2. **Select the gate steps** from `package.json` `scripts`, including only what actually exists,
   in the order typecheck → lint → test → build:
   - typecheck: a `typecheck` / `type-check` script if present, else fall back to `tsc --noEmit`
     when a `tsconfig.json` exists, else skip.
   - lint: a `lint` script if present, else skip.
   - test: a `test` script if present (the run-mode bootstraps one when missing; init only
     wires up what is there).
   - The cheap gate omits `build`; the full gate (run-mode, pre-commit) appends it when a
     `build` script exists.
   Each step is prefixed with the detected runner (e.g. `pnpm run lint`, `npm run lint`).
3. **Persist the resolved gate** to `.claude/autopilot.json`
   (`{ "gate": "pnpm run typecheck && pnpm run lint && pnpm test" }`). This file is the single
   source of truth read by both the Stop hook and the run-mode orchestrator — so the hook is
   PM-agnostic and never hardcodes pnpm/npm.
4. **Merge the hook** into `.claude/settings.json`: reads the existing file, **adds only** the
   autopilot `Stop`-hook block, leaves everything else untouched. Idempotent — re-running
   changes nothing.
5. Copies `autopilot-gate.sh` into the project's `.claude/hooks/` and `chmod +x`. The script
   reads the gate from `.claude/autopilot.json` (default fallback only if the file is absent).
6. Reports the detected package manager, the resolved gate command, and exactly what it added.

## 8. Safety & permissions

- Prefer reversible actions. **Never** force-push, edit `migrations/`, secrets, env files,
  production config, CI credentials, or other people's branches. A task needing any of these
  is skipped and logged.
- One topic = one branch = one PR.
- Recommended launch for unattended runs: `--permission-mode auto` (classifier gates risky
  actions, routine work proceeds). `bypassPermissions` only inside a sandbox/VM/throwaway
  worktree. This is a launch concern, documented in the README — the skill cannot set it.

## 9. Team-readiness

- The skill is **self-contained**: it *uses* Superpowers skills (brainstorming, writing-plans,
  TDD, systematic-debugging, code-review) when present, but does not hard-depend on them, so
  teammates without Superpowers still get a working autopilot.
- Content and docs in English; the skill recognizes German intent phrases in the prompt.
- UI / E2E browser verification is part of the run-mode workflow (§5 step 9), gated on a web
  UI + a local dev server + an available browser tool; skipped silently otherwise.

## 10. Non-goals (YAGNI)

- No multi-task queue, no `caffeinate`, no shell launchers, no fan-out-per-task scripts.
- No parallel implementation subagents / git worktrees in v1 (sequential, one package at a
  time — chosen for control and zero collision risk).
- No auto-generated `TOPICS.md` in v1.
- The skill does not change the session model or permission mode (engine constraints).

## 11. Open considerations

- Whether `init` should also offer a `--check` dry-run later (deferred; safe-merge is enough
  for v1).
- yarn / bun gate verbs differ slightly (`yarn lint` vs `yarn run lint`, `bun run`); npm and
  pnpm are the primary targets, yarn/bun are detected but verify their exact invocation during
  implementation.

## Sources

- Anthropic — [How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)
- Claude Code docs — Subagents, Hooks, Plugins reference, Skills, Permission modes
  (https://code.claude.com/docs)
- Existing pattern: `website-commander` `journal/` system (INDEX + per-session entries).
