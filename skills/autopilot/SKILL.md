---
name: autopilot
description: Execute a prepared plan unattended - TDD per package, gate, one adversarial review, goal-artifact check, PR. Triggers on "/autopilot", "autopilot", "autonom umsetzen", "autonome Session", "arbeite das selbstständig ab", "setze das eigenständig um". Also handles "autopilot init" to set up the per-project hooks.
user-invocable: true
argument-hint: "[init | <session directory> | <ticket key or topic>]   (add 'defer PR' to skip push/PR, 'mit Codex' for a cross-model review)"
---

# Autopilot

You run **unattended**. Input is a plan (`docs/autopilot/sessions/<slug>/PLAN.md`, written
with `/autopilot-plan`); output is one verified, reviewed, committed branch with a PR that
finishes the topic. No questions: every open point is decided conservatively and recorded.

**Definition of done:** the goal artifact in the plan stands ready and you verified it
yourself. Gate green is not done. "Wired but dormant", "off by default", "left as a manual
step" are not done. Effort is never a reason to stop, shrink or descope; only a genuine
external blocker (a purchase, a human-only asset, input impossible here) is.

**Input:** `$ARGUMENTS`.

## Routing

- `init` → follow `references/init.md`, then stop.
- A session directory, or a ticket key whose plan exists under `docs/autopilot/sessions/` →
  run it. `HANDOFF.md` present → continuation: read it first, trust its "Verified", start at
  its "Next step", never redo.
- No plan → write one yourself from the ticket, spec or prompt in the `/autopilot-plan`
  format, all shape questions answered conservatively under "Decisions" (nobody will answer
  them), then run it.

## Context hygiene

- **Bounded reads.** `grep -n` to locate, `sed -n a,bp` to read; never a whole file, never
  `git diff` without a path, never `git show` a whole commit.
- **Tail long outputs** (`| tail -n 40`) unless reading a specific failure.
- **Never re-read** what is in your context. Read `PLAN.md` once.
- **Gate discipline.** Red-green: only the affected test file. Full cheap gate once per
  package, before its commit. Never "to see where we are".
- **One command per Bash call.** Browser checks with `read_page`/`get_page_text`, one
  screenshot per screen at most.
- **Hand off, never compact.** When the context-budget hook reports the budget: hand off
  (below). Do not push on, do not wait for compaction.

## Run

### 1. Gate and branch
Gate = `.claude/autopilot.json` `gate`; if missing, compose it from the package manager
(lockfile) and the existing scripts (`references/init.md`) and persist it. No test runner →
set one up minimally, project-consistent, before implementing. Create
`.claude/.autopilot-active` when the Stop hook exists; remove it at the end and on every
abort. Branch from the plan header (`<prefix>/<KEY>-<slug>`, base = integration branch); a
continuation checks out the existing branch. Work in the current checkout; a worktree only
when the tree is dirty with foreign changes.

### 2. Packages, in order
For each package with `[ ]`: set `[~]`, then

- **Tests at the seams the plan names** (public interfaces only; no private internals, no
  side-channel assertions). Red before green: one failing test, run that file, confirm it
  fails on the assertion; minimal code to pass; refactor only what you wrote. Vertical
  slices, one test at a time. Mock only process boundaries. Reject in your own tests:
  implementation-coupled, tautological, skipped, `.only`, cannot-fail.
- **Failures:** one hypothesis, one change, re-run. After the second failed fix on the same
  failure: write observed vs expected, bisect, then fix. Never weaken an assertion.
- **Docs** directly affected by the package (inline, the touched area's doc file).
- **Full cheap gate once**; paste its summary line. Green → commit (Conventional Commits,
  ticket key). Set `[x]` with a one-line result under the package (commits, gate line), or
  `[!]` with the gap named. Append `DECISIONS.md` for every assumption you made.

### 3. Review, once, on the whole branch
`evelan:autopilot-reviewer` with the diff against the base branch and `PLAN.md`. Fix every
correctness, requirement or safety gap test-first, re-gate, commit. At most two cycles;
unresolved real gaps go to the top of `REPORT.md` and into the PR description. "mit Codex" /
"use Codex as reviewer" in the prompt → additionally `evelan:codex-review` on the branch
(its fallback applies).

### 4. Goal artifact
Exercise the goal artifact from the plan in the real thing: start the dev server, drive the
acceptance criteria, valid and invalid input, error states, console and network; or open the
generated report or document. Fix test-first, re-verify, stop the server. A missing
precondition is a blocker to resolve, not a skip. Only steps this environment cannot perform
go to `MANUAL_TESTING.md`.

### 5. Finish
User-facing behaviour or public API changed → README and top-level docs. `build` once.
Write `REPORT.md` (what shipped, verification with commands and results, review findings,
open items), prepend one line to `docs/autopilot/INDEX.md` (below the marker, never rewrite),
delete a consumed `HANDOFF.md`, remove the sentinel, commit.

### 6. PR and CI
"defer PR" in the prompt → report branch and state, stop. Otherwise push, open **one PR**
(`gh pr create`, ticket key in the title), never merge. `gh run watch`; red → fix, re-push,
until green. A green `review` check is not a review: fetch the bot's comments on both
surfaces (`pulls/<n>/comments`, `issues/<n>/comments`), verify each, fix or rebut with
evidence; a finding that contradicts a recorded decision is escalated in the PR, not
implemented.

## Hand-off (`HANDOFF.md`)

(1) commit every finished change; (2) write `docs/autopilot/sessions/<slug>/HANDOFF.md`;
(3) set the package `[~]` in `PLAN.md` with a one-line progress note; (4) commit both;
(5) end the turn with one line: `Resume with /autopilot <session directory>`. The queue
runner or the user starts the fresh session.

```
# HANDOFF - <package> - <ISO timestamp>
## Where we are
<package> is [~]: <one sentence>. Branch: <name>, HEAD: <sha>.
## Verified (with evidence)
- <what> - <command> → <result line>   (or: .claude/autopilot-gate.log last line)
## Open
- <concrete item>
## Next step
<the exact first action>
## Decisions made
- <decision> - <why>   (also in DECISIONS.md)
## Do not redo
- <verified things the next agent must not repeat>
```

Point to `PLAN.md`, commits and the gate log instead of copying. Redact secrets.

## Stop conditions (abort: `REPORT.md` with the blocker on top, artifacts committed, sentinel removed)
- The gate cannot go green without a destructive action or human input.
- The task needs anything on the never-list: force-push, `migrations/`, secrets, env files,
  production config, CI credentials, other people's branches.

## Artifacts - `docs/autopilot/` (committed, part of the PR)

```
docs/autopilot/
  INDEX.md                          # newest-first, one line per session
  sessions/YYYY-MM-DD-<slug>/
    PLAN.md          # from /autopilot-plan: goal, goal artifact, decisions, packages + status
    DECISIONS.md     # assumptions the run made, with reasons
    HANDOFF.md       # transient; deleted when consumed
    REPORT.md        # shipped work, verification, review findings, open items
    MANUAL_TESTING.md  # only for steps impossible in this environment
```

`INDEX.md` marker (prepend below it, never sort or rewrite):
```
<!-- NEW ENTRIES GO IMMEDIATELY BELOW THIS LINE -->
- **YYYY-MM-DD HH:MM** - <title> - <one line> - [PR](<url>) [→](./sessions/<slug>/REPORT.md)
```

## Permissions and hooks
Unattended runs: `--permission-mode auto`. The hooks from `/autopilot init` are optional;
the hand-off rules apply with or without them. At the end, print the table of
`autopilot-usage <this session's transcript>` (newest `.jsonl` under
`~/.claude/projects/<cwd with "/" replaced by "-">/`) so every run leaves a measurement.
