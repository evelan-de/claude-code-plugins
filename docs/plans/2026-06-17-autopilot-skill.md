# Autopilot Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ad-hoc `~/.claude/commands/autopilot.md` with a shareable `autopilot` skill in the `evelan` plugin: an Opus orchestrator that runs an autonomous spec→plan→TDD→review→gate→PR loop, delegates implementation to a Sonnet subagent on demand, reviews via a fresh-context adversarial subagent, and ships an optional per-project hard quality gate (Stop hook) set up by `/autopilot init`.

**Architecture:** One skill (`skills/autopilot/SKILL.md`) routed by `$ARGUMENTS` into **run** vs **init** mode. Two registered subagents at the plugin root (`agents/autopilot-reviewer.md` = Opus, `agents/autopilot-implementer.md` = Sonnet). A deterministic Stop-hook template (`skills/autopilot/hooks/autopilot-gate.sh`) that `init` copies into a target project, reading its gate command from `.claude/autopilot.json`. Session artifacts live under the target project's `docs/autopilot/` (INDEX + one folder per session).

**Tech Stack:** Claude Code plugin (skills + agents + hooks), Bash (gate script), Markdown skill/agent definitions, JSON config. Reference spec: `docs/specs/2026-06-17-autopilot-skill-design.md`.

**Note on scope:** Deliverables are mostly prompt/markdown/config files (not application code), so only the Bash gate script is genuinely unit-testable — it gets real `bash` tests (TDD). Markdown deliverables are verified structurally (valid frontmatter/JSON, required sections present) and by a final plugin-discovery check.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `agents/autopilot-reviewer.md` | Opus adversarial reviewer subagent (fresh context, re-runs gate). |
| `agents/autopilot-implementer.md` | Sonnet TDD implementer subagent (one package, escalates on uncertainty). |
| `skills/autopilot/SKILL.md` | Orchestrator workflow + run/init routing. The core deliverable. |
| `skills/autopilot/hooks/autopilot-gate.sh` | Stop-hook gate template (sentinel-guarded, reads `.claude/autopilot.json`). |
| `skills/autopilot/hooks/autopilot-gate.test.sh` | Bash tests for the gate script. |
| `skills/autopilot/references/settings-snippet.json` | The Stop-hook block `init` merges into a project's `.claude/settings.json`. |
| `skills/autopilot/references/init.md` | Detailed `init` procedure (detection algorithm, safe-merge), kept out of SKILL.md to stay lean. |
| `.claude-plugin/plugin.json` | Add `agents` key, bump version. |
| `README.md` | Document the skill, `init`, and team usage. |

---

## Task 1: Scaffold directories and wire the plugin

**Files:**
- Create: `agents/` (dir), `skills/autopilot/hooks/` (dir), `skills/autopilot/references/` (dir)
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Create the directories**

```bash
cd /Users/astraub/dev/tools/claude-code-plugins
mkdir -p agents skills/autopilot/hooks skills/autopilot/references
```

- [ ] **Step 2: Update `plugin.json` — add agents key, bump version**

Replace the file contents with:

```json
{
  "name": "evelan",
  "description": "Evelan team skills and commands for Claude Code",
  "version": "1.1.0",
  "author": {
    "name": "Evelan"
  },
  "skills": "./skills/",
  "agents": "./agents/"
}
```

- [ ] **Step 3: Verify JSON is valid**

Run: `jq . .claude-plugin/plugin.json`
Expected: pretty-printed JSON, exit 0.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: scaffold autopilot agents dir and bump evelan plugin to 1.1.0"
```

---

## Task 2: Gate hook script (TDD)

**Files:**
- Create: `skills/autopilot/hooks/autopilot-gate.sh`
- Test: `skills/autopilot/hooks/autopilot-gate.test.sh`

- [ ] **Step 1: Write the failing test**

Create `skills/autopilot/hooks/autopilot-gate.test.sh`:

```bash
#!/usr/bin/env bash
# Tests for autopilot-gate.sh. Run: bash skills/autopilot/hooks/autopilot-gate.test.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/autopilot-gate.sh"
PASS=0; FAIL=0

run_case() {
  # $1 desc  $2 expected_exit  $3 sentinel(yes/no)  $4 gate_command(or "")
  local desc="$1" want="$2" sentinel="$3" gate="$4"
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/.claude"
  [ "$sentinel" = "yes" ] && touch "$tmp/.claude/.autopilot-active"
  if [ -n "$gate" ]; then
    printf '{\n  "gate": "%s"\n}\n' "$gate" > "$tmp/.claude/autopilot.json"
  fi
  local err; err="$tmp/stderr.txt"
  CLAUDE_PROJECT_DIR="$tmp" bash "$HOOK" </dev/null 2>"$err"
  local got=$?
  if [ "$got" -eq "$want" ]; then
    echo "ok   - $desc (exit $got)"; PASS=$((PASS+1))
  else
    echo "FAIL - $desc (want $want, got $got)"; FAIL=$((FAIL+1))
  fi
  LAST_ERR="$(cat "$err")"
  rm -rf "$tmp"
}

run_case "no sentinel -> allow (exit 0) even with red gate" 0 no "false"
run_case "sentinel + green gate -> allow (exit 0)" 0 yes "true"
run_case "sentinel + red gate -> block (exit 2)" 2 yes "false"
case "$LAST_ERR" in
  *RED*) echo "ok   - red gate prints RED to stderr"; PASS=$((PASS+1));;
  *) echo "FAIL - red gate stderr missing 'RED'"; FAIL=$((FAIL+1));;
esac

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash skills/autopilot/hooks/autopilot-gate.test.sh`
Expected: FAIL — `autopilot-gate.sh` does not exist yet (`bash: ...: No such file or directory`).

- [ ] **Step 3: Write the gate script**

Create `skills/autopilot/hooks/autopilot-gate.sh`:

```bash
#!/usr/bin/env bash
# Autopilot Stop-hook gate (TEMPLATE).
# Copied into a project's .claude/hooks/ by `/autopilot init`.
#
# Blocks turn-end while an autopilot run is active AND the project gate is red,
# so the model cannot claim "done" on a red gate. Sentinel-guarded: inert in
# normal interactive sessions.
set -uo pipefail

cat >/dev/null 2>&1 || true   # drain the JSON Claude Code sends on stdin (unused)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SENTINEL="$PROJECT_DIR/.claude/.autopilot-active"

# Only gate during autopilot runs.
[ -f "$SENTINEL" ] || exit 0

CONFIG="$PROJECT_DIR/.claude/autopilot.json"
DEFAULT_GATE="npm run typecheck && npm run lint && npm test"
GATE=""
if [ -f "$CONFIG" ]; then
  if command -v jq >/dev/null 2>&1; then
    GATE="$(jq -r '.gate // empty' "$CONFIG" 2>/dev/null)"
  else
    GATE="$(sed -n 's/.*"gate"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$CONFIG" | head -n1)"
  fi
fi
GATE="${GATE:-$DEFAULT_GATE}"

cd "$PROJECT_DIR" || exit 0

if OUTPUT="$(bash -lc "$GATE" 2>&1)"; then
  exit 0   # green -> allow the turn to end
fi

# Red -> block the stop. exit 2 + stderr is the documented "block" signal.
{
  echo "Autopilot gate is RED — do not end the turn. Fix the root cause, then re-run the gate."
  echo "Do NOT skip tests, weaken assertions, or suppress errors to go green."
  echo "--- gate output (tail) ---"
  echo "$OUTPUT" | tail -n 40
} >&2
exit 2
```

- [ ] **Step 4: Make both scripts executable**

```bash
chmod +x skills/autopilot/hooks/autopilot-gate.sh skills/autopilot/hooks/autopilot-gate.test.sh
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash skills/autopilot/hooks/autopilot-gate.test.sh`
Expected: `PASS=4 FAIL=0`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add skills/autopilot/hooks/autopilot-gate.sh skills/autopilot/hooks/autopilot-gate.test.sh
git commit -m "feat: add sentinel-guarded autopilot gate hook with bash tests"
```

---

## Task 3: Settings snippet reference

**Files:**
- Create: `skills/autopilot/references/settings-snippet.json`

- [ ] **Step 1: Write the snippet**

Create `skills/autopilot/references/settings-snippet.json`:

```json
{
  "// note": "init merges ONLY this Stop block into the project's .claude/settings.json. Do not overwrite the file.",
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/autopilot-gate.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Verify JSON is valid**

Run: `jq . skills/autopilot/references/settings-snippet.json`
Expected: pretty-printed JSON, exit 0.

- [ ] **Step 3: Commit**

```bash
git add skills/autopilot/references/settings-snippet.json
git commit -m "feat: add autopilot Stop-hook settings snippet"
```

---

## Task 4: Reviewer subagent

**Files:**
- Create: `agents/autopilot-reviewer.md`

- [ ] **Step 1: Write the agent definition**

Create `agents/autopilot-reviewer.md`:

```markdown
---
name: autopilot-reviewer
description: Adversarial final reviewer for autopilot runs. Reviews a diff against PLAN.md in a fresh context and reports only correctness, requirement, and safety gaps. Use before treating an autopilot task as done.
tools: Read, Grep, Glob, Bash
model: opus
---

You are a senior engineer doing the **final review** of a change produced by an unattended
agent. You did not write this code and have no attachment to it. You only report — you do not fix.

You are given a **diff (or branch)** and a **PLAN.md**.

## What to check (in this order)

1. **Requirements** — Is every requirement in `PLAN.md` actually implemented? Quote the
   requirement, point to where it is (or isn't) satisfied. This covers business logic.
2. **Verification** — Do the edge cases in `PLAN.md` have tests that genuinely exercise them?
   Confirm a test would fail without the change (run it if unsure). Flag tests that pass
   trivially, are skipped, or assert nothing meaningful.
3. **Correctness** — Real bugs only: race conditions, unhandled errors/rejections, missing
   `await`, off-by-one, wrong types, broken contracts, null/undefined paths, incorrect state
   updates, and security issues (injection, secrets, authz).
4. **Scope** — Did anything change outside the stated scope in `PLAN.md`?
5. **Safety** — Any destructive/irreversible action, secret, env, migration, or production
   config touched?

## Gate

Re-run the project gate yourself (read `.claude/autopilot.json` for the command, else
`npm run typecheck && npm run lint && npm test`). Report its real result — never trust a claim.

## What NOT to report

Do not raise style preferences, naming nits, speculative hardening, extra abstraction layers,
or tests for cases that cannot occur. A reviewer asked for gaps will invent them — resist that.
If the change is sound, say so plainly with an empty findings list.

## Output

```
VERDICT: PASS | GAPS
GATE: GREEN | RED  (paste the final summary line)

Findings (only if GAPS):
- <file>:<line> — <what is wrong> — <why it matters> — <minimal fix>
```

Verify every claim by reading the actual files and citing specific lines. Where a claim
depends on test behavior, run the relevant test rather than guessing.
```

- [ ] **Step 2: Verify frontmatter parses and required fields exist**

Run:
```bash
awk '/^---$/{n++; next} n==1{print}' agents/autopilot-reviewer.md | grep -E '^(name|model|tools|description):'
```
Expected: four lines printed (name, description, tools, model), `model: opus` present.

- [ ] **Step 3: Commit**

```bash
git add agents/autopilot-reviewer.md
git commit -m "feat: add autopilot-reviewer subagent (Opus, adversarial, fresh context)"
```

---

## Task 5: Implementer subagent

**Files:**
- Create: `agents/autopilot-implementer.md`

- [ ] **Step 1: Write the agent definition**

Create `agents/autopilot-implementer.md`:

```markdown
---
name: autopilot-implementer
description: TDD implementer for autopilot's fast/cost-efficient mode. Implements ONE PLAN.md work package test-first, runs the gate, and escalates uncertain decisions instead of guessing. Dispatched by the autopilot skill when the user asked for Sonnet / cost-efficient / fast implementation.
tools: Read, Edit, Write, Grep, Glob, Bash
model: sonnet
---

You implement **exactly one work package** from `PLAN.md`, handed to you by the orchestrator.
You work test-first and you do not expand scope.

## Workflow

1. Read the package's goal, affected files, and verification criteria from `PLAN.md`.
2. **Write the failing test(s)** that encode the verification criteria. Run them and confirm
   they fail for the right reason.
3. Implement the **minimal** code to make them pass. Follow existing project patterns and
   conventions — do not add dependencies or restructure unrelated code.
4. Refactor only what you just wrote.
5. Run the project gate (read `.claude/autopilot.json` for the command, else
   `npm run typecheck && npm run lint && npm test`). Paste its real output. Never claim green
   without showing it.

## Escalation — never guess

When you hit a decision that is ambiguous, architectural, or could be hard to reverse
(public API shape, data model, auth, irreversible migration, a choice not pinned by `PLAN.md`):
- Make the **conservative, easily-reversible** choice and record it under your `decisions`
  output, **or**
- if you cannot proceed safely, stop and return `needs_review: true` with the precise question.

Do **not** touch anything on the never-list: force-push, `migrations/`, secrets, env files,
production config, CI credentials, or other branches.

## Output (return this structured block as your final message)

```
PACKAGE: <package id/title>
STATUS: done | needs_review | blocked
GATE: GREEN | RED  (final summary line)
FILES: <files created/modified>
DECISIONS:
- <any conservative assumption you made, with one-line rationale>
NEEDS_REVIEW:
- <open question(s) for the orchestrator — empty if none>
```

Your final message IS the return value the orchestrator parses — return the block, not prose.
```

- [ ] **Step 2: Verify frontmatter**

Run:
```bash
awk '/^---$/{n++; next} n==1{print}' agents/autopilot-implementer.md | grep -E '^model: sonnet$'
```
Expected: `model: sonnet`.

- [ ] **Step 3: Commit**

```bash
git add agents/autopilot-implementer.md
git commit -m "feat: add autopilot-implementer subagent (Sonnet, TDD, escalates on uncertainty)"
```

---

## Task 6: Init reference doc

**Files:**
- Create: `skills/autopilot/references/init.md`

- [ ] **Step 1: Write the init procedure**

Create `skills/autopilot/references/init.md`:

````markdown
# `/autopilot init` — set up the per-project hard gate

Goal: enable the deterministic Stop-hook gate in the **current** project, safely and
idempotently. Never overwrite existing config.

## Steps

### 1. Detect the package manager (first hit wins)
1. `packageManager` field in `package.json` (`pnpm@…` → pnpm, `yarn@…` → yarn, `bun@…` → bun, `npm@…` → npm).
2. Lockfile: `pnpm-lock.yaml` → pnpm; `yarn.lock` → yarn; `bun.lockb`/`bun.lock` → bun; `package-lock.json` → npm.
3. Fallback → `npm`.

Run verbs: npm/pnpm/yarn use `<pm> run <script>` (npm/pnpm) — for scripts; tests run as
`<pm> test`. (yarn/bun verb edge cases: verify against the project; npm + pnpm are primary.)

### 2. Select gate steps from `package.json` `scripts` (include only what exists)
Order: typecheck → lint → test (+ build for the full gate only).
- typecheck: `typecheck` or `type-check` script; else `tsc --noEmit` if `tsconfig.json` exists; else skip.
- lint: `lint` script; else skip.
- test: `test` script; else skip (run-mode bootstraps a missing runner — init wires only what is there).
Compose the **cheap gate** string (no build), e.g. `pnpm run typecheck && pnpm run lint && pnpm test`.

### 3. Write `.claude/autopilot.json`
```json
{ "gate": "<composed cheap gate>" }
```
This is the single source of truth read by the hook and the run-mode orchestrator. If the
file exists with a different gate, show the diff and keep the existing one unless the detected
commands are clearly better — explain what you chose.

### 4. Copy the hook
Copy `<plugin>/skills/autopilot/hooks/autopilot-gate.sh` to `.claude/hooks/autopilot-gate.sh`
and `chmod +x` it. (Use `${CLAUDE_PLUGIN_ROOT}` to locate the plugin source.)

### 5. Safe-merge the Stop hook into `.claude/settings.json`
- Read the existing `.claude/settings.json` (create `{}` if absent).
- Merge ONLY the `Stop` block from `references/settings-snippet.json`. Preserve every other key
  and any existing hooks (append, do not replace). If the autopilot Stop hook is already
  present, change nothing (idempotent).
- Use `jq` for the merge when available; otherwise edit carefully and re-validate with `jq .`.

### 6. Add the sentinel to `.gitignore`
Ensure `.claude/.autopilot-active` is gitignored (it is a transient runtime flag).

### 7. Report
Print: detected package manager, the resolved gate command, the files created/modified, and
whether the merge was a no-op (already initialized).
````

- [ ] **Step 2: Verify it renders and references the real snippet path**

Run: `grep -c "settings-snippet.json" skills/autopilot/references/init.md`
Expected: `>= 1`.

- [ ] **Step 3: Commit**

```bash
git add skills/autopilot/references/init.md
git commit -m "feat: add autopilot init reference (PM detection, safe-merge)"
```

---

## Task 7: The orchestrator skill (SKILL.md)

**Files:**
- Create: `skills/autopilot/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `skills/autopilot/SKILL.md`:

````markdown
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
````

- [ ] **Step 2: Verify frontmatter and required sections**

Run:
```bash
awk '/^---$/{n++; next} n==1{print}' skills/autopilot/SKILL.md | grep -E '^(name|description|user-invocable):'
grep -E "^## (Routing|Model strategy|Run-mode workflow|Stop conditions|Artifacts)" skills/autopilot/SKILL.md
```
Expected: name/description/user-invocable present; all five section headers found.

- [ ] **Step 3: Verify it references the real agent names**

Run: `grep -cE "evelan:autopilot-(reviewer|implementer)" skills/autopilot/SKILL.md`
Expected: `>= 3`.

- [ ] **Step 4: Commit**

```bash
git add skills/autopilot/SKILL.md
git commit -m "feat: add autopilot orchestrator skill (run + init routing)"
```

---

## Task 8: README + plugin discovery verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add an Autopilot section to the README**

Append this section (place it after the skills overview):

```markdown
## Autopilot

`autopilot` runs an autonomous, unattended development loop for **one topic per session**:
spec → plan → TDD implementation → adversarial review → quality gate → PR (CI watched until green).

### Usage

- Run a task: `/autopilot <task, ticket key, or spec file>`
  e.g. `/autopilot DNA-901 add rate limiting to the contact route`
- Cost-efficient implementation (delegates coding to a Sonnet subagent):
  add "with sonnet" / "kosteneffizient" / "schnell" to the prompt.
- Thorough review (adds clean-code + reusability lenses): add "thorough review".

The orchestrator runs at your **session model** (Opus recommended). Review always runs on Opus
(`evelan:autopilot-reviewer`); implementation delegates to `evelan:autopilot-implementer` (Sonnet)
only when you ask for it.

### Optional hard gate (per project)

`/autopilot init` sets up a deterministic Stop-hook in the current project that blocks the model
from ending a turn while the gate (typecheck/lint/test) is red. It auto-detects the package manager
(npm/pnpm/yarn/bun), writes the gate to `.claude/autopilot.json`, copies the hook into
`.claude/hooks/`, and safe-merges the hook into `.claude/settings.json` (idempotent, never
overwrites). The hook is inert outside autopilot runs (sentinel-guarded).

### Artifacts

Each session writes to `docs/autopilot/` (committed, part of the PR): an `INDEX.md` history plus a
per-session folder with `PLAN.md`, `DECISIONS.md`, `REPORT.md`, and `MANUAL_TESTING.md`.

For unattended runs, launch with `--permission-mode auto`.
```

- [ ] **Step 2: Verify the plugin loads with the new components**

Run:
```bash
claude --plugin-dir /Users/astraub/dev/tools/claude-code-plugins -p "List the skills and agents the evelan plugin provides." 2>&1 | tail -30
```
Expected: output mentions the `autopilot` skill and the `autopilot-reviewer` / `autopilot-implementer` agents. (If the CLI flag differs in this version, instead confirm files are discoverable: `ls agents skills/autopilot`.)

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document autopilot skill, init, and artifacts in README"
```

---

## Task 9: Retire the old user-level command

**Files:**
- Delete (with confirmation): `~/.claude/commands/autopilot.md`

- [ ] **Step 1: Confirm the new skill is installed/available before deleting the old command**

Verify the `evelan` plugin (with the autopilot skill) is installed for the user, OR that they run
from `--plugin-dir`. Do not delete the fallback until the replacement works.

- [ ] **Step 2: Back up and remove the old command**

```bash
mv ~/.claude/commands/autopilot.md ~/.claude/commands/autopilot.md.bak
```
(Keep the `.bak` until the user confirms the skill behaves as expected, then they can delete it.)

- [ ] **Step 3: Final review**

Use superpowers:requesting-code-review on the whole branch (agents, skill, hook, README) before
opening the PR. Then push and open the PR for `feat/autopilot-skill`.

---

## Self-Review (completed during planning)

- **Spec coverage:** form/two-actions (Task 7 routing), model strategy + escalation (Tasks 4/5/7),
  run-mode phases incl. input cascade / bootstrap / branch / TDD / hybrid review / UI verification /
  PR+CI / stop conditions (Task 7), two-tier gate (Tasks 2/3/6/7), PM-agnostic detection (Tasks 2/6),
  artifacts under `docs/autopilot/` (Task 7), team-readiness / English / Superpowers-optional (Tasks 7/8),
  branch convention (Task 7). All mapped.
- **Placeholders:** none — full file contents provided for every created file; the only `tsc --noEmit`
  / default-gate fallbacks are intentional behavior, not gaps.
- **Naming consistency:** agent names `evelan:autopilot-reviewer` / `evelan:autopilot-implementer`,
  config `.claude/autopilot.json` key `gate`, sentinel `.claude/.autopilot-active`, and the
  `<!-- NEW ENTRIES GO IMMEDIATELY BELOW THIS LINE -->` marker are used identically across Tasks 2–8.
```
