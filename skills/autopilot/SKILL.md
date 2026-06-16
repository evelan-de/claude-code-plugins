---
name: autopilot
description: Use for autonomous, unattended development of one topic — spec → plan → TDD → adversarial review → quality gate → PR. Triggers on "/autopilot", "autopilot", "autonom umsetzen", "autonome Session", "arbeite das selbstständig ab", "setze das eigenständig um". Also handles "autopilot init" to set up the per-project quality-gate hook.
user-invocable: true
argument-hint: "[init | <task | TICKET-KEY | spec file>]   (add 'with sonnet' for cost-efficient implementation)"
---

# Autopilot

You run **unattended**: no human will answer questions until the session is reviewed.
Optimize for **correct, reviewed, committed** work — never volume. One fully verified,
green-CI, merge-ready PR is the goal.

**Input:** `$ARGUMENTS`

## Routing

- If `$ARGUMENTS` begins with `init` → **Init mode**: follow `references/init.md` exactly and stop.
- Otherwise → **Run mode** (below).

## Operating principles (non-negotiable)

- **You are not the verification loop.** Every change must pass a gate that *you* run and read.
- **Never assert success.** Show evidence — the exact command and its output.
- **Prefer reversible actions.** NEVER force-push, edit `migrations/`, secrets, env files,
  production config, or CI credentials, and never touch other people's branches. A task needing
  any of these is skipped and logged.
- **One session = one topic = one branch = one PR.** All work packages are commits on that one branch.
- **No questions — decide.** On ambiguity, pick the conservative, easily-reversible option and
  record it in `DECISIONS.md`.
- Use the Superpowers skills (brainstorming, writing-plans, test-driven-development,
  systematic-debugging, requesting-code-review) when they are installed; otherwise follow the
  equivalent workflow described here. Do not hard-depend on them.

## Model strategy

- **You (the orchestrator) are the session model** (Opus by default): explore, spec, plan,
  review adjudication, all decisions, commit/PR/CI.
- **Implementation:** by default you implement directly. **Only if the prompt signals cost/speed
  intent** — "with sonnet", "cost-efficient", "fast", "cheap" (DE: "mit Sonnet",
  "kosteneffizient", "schnell", "günstig") — delegate each work package to the
  `evelan:autopilot-implementer` subagent (Sonnet). Inspect its returned block; resolve any
  `needs_review` item yourself before accepting the package.
- **Review:** always use the `evelan:autopilot-reviewer` subagent (fresh context).

## Run-mode workflow

Work ONE topic end to end. Phases run in order per package; a trivial one-line task may collapse them.

### 0. Resolve input (cascade)
1. A spec is provided / referenced / already in the repo (`SPEC.md` or equivalent) → use it.
2. Only a rough idea → write a self-contained spec into `PLAN.md` (problem/goal, scope + non-goals,
   functional requirements with acceptance criteria, affected areas, edge/error cases). Answer
   open questions with conservative assumptions → `DECISIONS.md`.
3. No task given at all → derive the task from project context (open TODOs, leftover plan files,
   issues, obviously unfinished features); record the choice in `DECISIONS.md`; then proceed as (2).

### 1. Project context & gate
If `.claude/autopilot.json` exists, use its `gate`. Otherwise detect the package manager and the
exact lint/typecheck/test/build commands (see `references/init.md` for the detection algorithm) —
never assume. If a test runner is missing, set one up minimally and project-consistently **before**
implementing. Existing conventions win over generic best practices.

### 2. Branch
Create one session branch following the project's convention:
- Prefix: infer from existing branches / git history (`git branch -a`, recent merges); fall back to `feature/`.
- Ticket: if the prompt has a key (`DNA-901`, `WEB-123`, `PAUL-…`, `EL-…`), include it (original casing) → `<prefix>/DNA-901-<slug>`; else `<prefix>/<slug>`.
- Slug: lowercase, hyphen-separated, from the topic.

### 3. Explore (read-only)
Delegate wide reading to a subagent so it does not flood your context. Get back files, patterns,
risks — not full file contents.

### 4. Plan → `PLAN.md`
Self-contained: files/interfaces touched, explicit out-of-scope, concrete verification criteria
(test cases with inputs/expected outputs, expected typecheck/lint/build result), and an
end-to-end check. Break into small, dependency-ordered packages, each with a Definition of Done
and a status marker `[ ] / [~] / [x] / [!]`.

### 5. Implement (TDD)
Per package: failing test first (confirm it fails for the right reason) → minimal code to green →
refactor. Everything sensibly unit-testable gets tests (utils, hooks, business logic, data
transforms, API handlers, validation); UI components are tested by behavior. Run the **cheap gate**
(typecheck/lint/full test suite) after each meaningful change and show its output. What cannot be
auto-tested → `MANUAL_TESTING.md` with concrete steps, then continue. In Sonnet mode, delegate the
package to `evelan:autopilot-implementer`.

### 6. Review (fresh context, hybrid depth)
- **Always:** dispatch `evelan:autopilot-reviewer` with the diff + `PLAN.md`. Fix every gap it
  reports that affects correctness, requirements, or safety — test-driven, then re-gate.
- **On demand:** if the prompt asks ("thorough review", "architecture review", "Code-Qualität") or
  the diff is large, additionally fan out **clean-code** and **reusability** lenses as parallel
  subagents. Prioritize findings (critical / important / nice-to-have); fix critical + important,
  record nice-to-have in `REPORT.md` with rationale.
- Max 2 review cycles; unresolved real gaps → mark the package `[!]`, log it, move on.

### 7. Full gate + commit
Run cheap gate + `build`; paste the summary. Only if fully green: commit (Conventional Commits,
referencing the topic/ticket).

### 8. Keep `PLAN.md` / `DECISIONS.md` current.

### At session end (topic fully implemented):

### 9. UI / E2E verification (when applicable)
Only when ALL hold: (a) it is a web UI, (b) a local dev server is startable (`npm run dev`),
(c) a browser tool is available (Chrome plugin / browser MCP / Preview MCP). Then: start the dev
server, drive the acceptance criteria, submit forms with valid AND invalid input, provoke error
states, check console + network for errors, work through browser-checkable `MANUAL_TESTING.md`
items, fix findings test-driven and re-verify, stop the server cleanly. If any precondition is
missing → skip silently, note it in `REPORT.md`. **Never a blocker.**

### 10. PR + CI
Push the branch and open **one PR** automatically (GitHub `gh pr create`; Bitbucket via API, ticket
key in title). The PR is for review — **never auto-merge**. Then wait for CI (`gh run watch`); on
red, read `gh run view --log-failed`, fix, re-push, re-check until green and merge-ready.

### 11. Finalize artifacts
Write `REPORT.md` and prepend the session one-liner to `docs/autopilot/INDEX.md`.

## Stop conditions (abort the whole session, write `REPORT.md`)
- The gate cannot be made green without a destructive action or human input.
- The task would require anything on the never-list.
- No package remains implementable.

## Artifacts — `docs/autopilot/` (committed, part of the PR)

```
docs/autopilot/
  INDEX.md                                # newest-first, one line + link per session
  sessions/YYYY-MM-DD-<slug>/
    PLAN.md          # spec + plan + verification criteria + per-package status
    DECISIONS.md     # conservative assumptions, each with rationale
    REPORT.md        # shipped work, test coverage, review findings (fixed + deferred), PR link, CI status, open items
    MANUAL_TESTING.md  # only when something cannot be auto-tested
```

`INDEX.md` uses an insert marker; prepend, never sort or rewrite:
```
<!-- NEW ENTRIES GO IMMEDIATELY BELOW THIS LINE -->
- **YYYY-MM-DD HH:MM** — <title> — <one-line summary> — [PR](<url>) [→](./sessions/<slug>/REPORT.md)
```
Create `docs/autopilot/` and seed `INDEX.md` with that header + marker if missing.

## Permissions
For unattended runs, `--permission-mode auto` is recommended (the user sets this at launch — you
cannot change it). The Stop-hook hard gate (via `/autopilot init`) is optional and complements
your own gate runs.
