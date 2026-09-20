---
name: autopilot
description: Execute a prepared plan unattended - TDD per package, gate, one adversarial review, goal-artifact check, PR. Triggers on "/autopilot", "autopilot", "autonom umsetzen", "autonome Session", "arbeite das selbstständig ab", "setze das eigenständig um".
argument-hint: "[init | <session dir> | <ticket>] [defer PR] [no Codex]"
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
- **Bound long outputs** with the tool's own flags (`git log -n 20`, `grep -m 20`, `--reporter=dot`), never a pipe; gate commands are already filtered by the hook.
- **Never re-read** what is in your context. Read `PLAN.md` once.
- **Gate discipline.** Red-green: only the affected test file. Full cheap gate once per
  package, before its commit. Never "to see where we are".
- **One command per Bash call.** Browser checks with `read_page`/`get_page_text`, one
  screenshot per screen at most.
- **Hand off, never compact.** When the context-budget hook reports the budget: hand off
  (below). Do not push on, do not wait for compaction.

## Write less

- Before each change, stop at the first rung that holds: (1) it need not exist (speculative
  need → skip, record under `DECISIONS.md`); (2) a helper, type or pattern in this codebase →
  reuse it; (3) the standard library does it; (4) a native platform feature covers it
  (`<input type="date">` over a picker, CSS over JS, a DB constraint over app code); (5) an
  installed dependency solves it (never add one for a few lines); (6) it can be one line;
  (7) only then the minimum that works.
- No abstraction with one implementation, no factory for one product, no config for a value
  that never changes, no scaffolding "for later".
- Fewest files, shortest working diff that fixes the root cause where all callers route
  through, not the symptom. A bug fix greps every caller first. Read the flow end to end
  before changing it.
- Explanations: code and the one-line result under the package, no essays.
- Never simplify away: input validation at trust boundaries, error handling that prevents
  data loss, security, accessibility basics, the plan's verification criteria, anything the
  plan asks for explicitly.

## Run

Launch: model, effort and advisor are launch parameters chosen by the plan's hand-over line
(see `/autopilot-plan`); consult the advisor before committing to an approach, on a
recurring error and before declaring done. At the end print the table of
`autopilot-usage <this session's transcript>` (newest `.jsonl` under
`~/.claude/projects/<cwd with "/" replaced by "-">/`).

### 1. Gate and branch
Gate = `.claude/autopilot.json` `gate`; if missing, compose it from the package manager
(lockfile) and the existing scripts (`references/init.md`) and persist it. No test runner →
set one up minimally, project-consistent, before implementing. Create
`.claude/.autopilot-active` whenever `.claude/autopilot.json` exists; remove it (and
`.claude/.autopilot-gate-blocks`) at the end and on every abort; never commit either. Branch per the plan header: **session mode** checks out
`<prefix>/<KEY>-<slug>`, which `/autopilot-plan` created with the plan on it (create it from
the base only when you wrote the plan yourself, and commit the plan there first);
**feature-branch mode** checks out the named feature branch (create it from the base if
missing) and commits straight onto it; several sessions add up to one branch with one review
at the end. `PLAN.md` must be on the checked-out branch before the first package. A
continuation checks out the existing branch. Work in the current checkout; a worktree only
when the tree is dirty with foreign changes.

### 2. Packages, in order
For each package with `[ ]`: set `[~]`, then

- **Tests at the seams the plan names** (public interfaces only). Red before green: one
  failing test, run that file, confirm it fails on the assertion; minimal code to pass;
  refactor only what you wrote. Vertical slices, one test at a time. Mock only process
  boundaries. Reject: implementation-coupled, tautological, skipped, `.only`, cannot-fail.
- **Failures:** one hypothesis, one change, re-run. After the second failed fix on the same
  failure: write observed vs expected, bisect, then fix. Never weaken an assertion.
- **Docs** directly affected by the package (inline, the touched area's doc file).
- **Full cheap gate once**; paste its summary line. Green → commit (Conventional Commits,
  ticket key). Set `[x]` with a one-line result under the package (commits, gate line), or
  `[!]` with the gap named. Append `DECISIONS.md` for every assumption you made.

### 3. Review, once, on the whole branch
`evelan:autopilot-reviewer` with the diff against the base branch and `PLAN.md`. Fix every
correctness, requirement or safety gap test-first, re-gate, commit. At most two cycles;
unresolved real gaps go to the top of `REPORT.md` and into the PR description.

**Codex cross-model review, on by default.** After the Claude review is settled, run
`evelan:codex-review` on the branch (`--base <base branch>`) unless the prompt says
"ohne Codex" / "no Codex" or `codex-cli --version` fails (then one line in `REPORT.md`:
Codex review skipped, why). Treat Codex's findings exactly like the reviewer's (fix every
correctness, requirement or safety gap test-first, re-gate, commit; one cycle), rebut the
rest with evidence in `REPORT.md` under "Codex review". Codex rate-limited or unavailable →
skip with the reason in `REPORT.md`; do not run the skill's Claude fallback.

### 4. Goal artifact
Exercise the goal artifact in the real thing: start the dev server, drive the acceptance
criteria, valid and invalid input, error states, console and network; or open the generated
report or document. Fix test-first, re-verify, stop the server. A missing precondition is a
blocker to resolve, not a skip. Only steps this environment cannot perform go to
`MANUAL_TESTING.md`.

### 5. Finish
**Docs are part of done.** Walk the diff once and update every document the change made
stale: README and top-level docs for user-facing behaviour or public API; `docs/` pages that
describe the touched area; `CLAUDE.md` and `.claude/rules/` when a convention, command or
gate changed; inline doc comments on changed public interfaces. A stale doc is a gap, the
reviewer flags it. `build` once.
Write `REPORT.md` (what shipped, verification with commands and results, review findings,
open items), prepend one line to `docs/autopilot/INDEX.md` (below the marker, never rewrite),
delete a consumed `HANDOFF.md`, remove the sentinel, commit. Artifact layout and INDEX
marker: `references/artifacts.md`.

### 6. PR and CI
"defer PR" in the prompt → report branch and state, stop. Before any push: when
`.claude/autopilot.json` has `gateFull` (the project's full gate, e.g. with integration
tests), run it once; red → fix, re-run; a precondition it needs (a test database, a service)
is a blocker to resolve, not a skip. Feature-branch mode → push the feature branch
(`git push origin <feature>`; pull with rebase first if it moved), no PR; the feature branch
gets its PR when the last session of the feature is done. Otherwise push, open **one PR**
(`gh pr create`, ticket key in the title), never merge. `gh run watch`; a red CI check → fix,
re-push, until green. The review check is not CI: red there means the review pipeline is
broken, never a finding; note it in `REPORT.md` and move on.

**Review bot.** Projects with a Claude review workflow (`.github/workflows/claude-code-review.yml`)
review each PR once, asynchronously; the project's `CLAUDE.md` or its review doc names the
contract, read it. Default contract: findings arrive as inline comments on the diff
(`gh api repos/{owner}/{repo}/pulls/<n>/comments`); a PR without findings gets one
top-level comment "No issues found" and a PR the bot could not review gets a
"Code review skipped/incomplete" notice (`gh api repos/{owner}/{repo}/issues/<n>/comments`);
a PR over the size gate (100 reviewable files or 5000 lines) gets a top-level notice from
`github-actions[bot]` instead of a review. A green `review` check proves nothing, only a
comment does. A later push is not re-reviewed unless the label `claude-re-review` is added;
the workflow removes the label when its run ends. Loop: (1) wait for the review: poll both
surfaces every minute, up to 40 minutes, all authors; a round ends with the first inline
comment batch, "No issues found", a skipped/incomplete notice or the size notice (the size
notice ends the whole loop: the label would force a review that cannot finish); (2) verify
each finding in the code, fix real ones test-first, re-gate, commit, push; (3) rebut the
rest with evidence in a PR comment; a finding that contradicts a recorded decision is
escalated in the PR, not implemented; (4) after a fix push add the label
(`gh pr edit <n> --add-label claude-re-review`) and wait for round two: its result is a
Claude comment whose `created_at` is after the fix push, or the label gone with no new
comment (pipeline broken, note it). At most two rounds; whatever remains goes into
`REPORT.md` and the PR description. No workflow file → no review to wait
for; say so in `REPORT.md`.

## Hand-off

(1) commit every finished change; (2) write `docs/autopilot/sessions/<slug>/HANDOFF.md`;
(3) set the package `[~]` in `PLAN.md` with a one-line progress note; (4) commit both;
(5) end the turn with one line: `Resume with /autopilot <session directory>`. The queue
runner or the user starts the fresh session. HANDOFF.md format: `references/handoff.md`.

## Stop conditions (abort: `REPORT.md` with the blocker on top, artifacts committed, sentinel removed)
- The gate cannot go green without a destructive action or human input.
- The task needs anything on the never-list: force-push, `migrations/`, secrets, env files,
  production config, CI credentials, other people's branches.
