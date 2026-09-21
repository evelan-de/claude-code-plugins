---
name: autopilot
description: Execute a prepared plan unattended - TDD per package, gate, one adversarial review, goal-artifact check, PR. Started by the runner (mission-control); in an interactive session it enqueues and starts the runner. Triggers on "/autopilot", "autopilot", "autonom umsetzen", "autonome Session", "arbeite das selbstständig ab", "setze das eigenständig um".
argument-hint: "[init | <session dir> | <ticket>] [defer PR] [no Codex]"
---

# Autopilot

You run **unattended**, started by the runner (`mission-control run`, headless `claude -p`).
Input is a plan (`docs/autopilot/sessions/<slug>/PLAN.md`, written with `/autopilot-plan`
at code level: anchors, signatures, pseudo-code, assertions); output is one verified,
reviewed, committed branch with a PR that finishes the topic. No questions: every open point
is decided conservatively and recorded.

**Definition of done:** the goal artifact in the plan stands ready and you verified it
yourself. Gate green is not done. "Wired but dormant", "off by default", "left as a manual
step" are not done. Effort is never a reason to stop, shrink or descope; only a genuine
external blocker (a purchase, a human-only asset, input impossible here) is.

**Input:** `$ARGUMENTS`.

## Routing

- `init` → follow `references/init.md`, then stop.
- **Interactive session** (no `.claude/.autopilot-active`, and you were not started by the
  runner, which creates it before it starts you): do not implement here.
  `~/.claude/mission-control` exists on this machine → options in the prompt ("defer PR",
  "no Codex") go into the plan header line `Options:` (replace the line, commit
  `docs(autopilot): options for <slug>`); a clean checkout on the plan branch is switched
  to the base branch (`git switch <base>`, so the run owns the branch); then
  `mission-control add <repo path> <session dir>` (one Bash call), then `mission-control
  start` (one Bash call); print the `added:`
  line, the `start` line and "progress: `/mission-control status`, log:
  `/mission-control log <session dir>`, macOS notification and Slack when it finishes";
  stop. No directory → say that runs are started by the runner only, and point to the
  hand-over in `/autopilot-plan` step 7 (draft PR labelled `autopilot-ready`). Stop. A
  sentinel that exists although a user is typing to you (an interactive session in a
  checkout, not a runner worktree under `~/.claude/mission-control/worktrees/`) is stale:
  delete it and take this interactive route. The rest of this skill is for the run.
- A session directory, or a ticket key whose plan exists under `docs/autopilot/sessions/` →
  run it. Options come from the prompt and from the plan header `Options:` ("defer PR",
  "no Codex"). `HANDOFF.md` present → continuation: read it first, trust its "Verified", start at
  its "Next step", never redo. A package `[~]` with uncommitted changes and no `HANDOFF.md`
  (the previous session died) → `git checkout -- .` and `git clean -fd` inside the touched
  paths, restart that package from its first step, one line in `DECISIONS.md`.
- No plan → write one yourself from the ticket, spec or prompt in the `/autopilot-plan`
  format, all shape questions answered conservatively under "Decisions" (nobody will answer
  them), then run it. Say in `REPORT.md` that the plan was written by the run.

## Context hygiene

- **Bounded reads.** `grep -n` to locate, `sed -n a,bp` to read; never a whole file, never
  `git diff` without a path, never `git show` a whole commit. The plan already carries the
  anchors: read the anchored region, not the file.
- **Bound long outputs** with the tool's own flags (`git log -n 20`, `grep -m 20`,
  `--reporter=dot`), never a pipe; gate commands are already filtered by the hook.
- **Never re-read** what is in your context. Read `PLAN.md` once, whole (it is the spec).
- **Gate discipline.** Red-green: only the affected test file. Full cheap gate once per
  package, before its commit. Never "to see where we are".
- **One command per Bash call.** Browser checks with `agent-browser` (`references/browser.md`),
  one screenshot per screen at most.
- **Hand off, never compact.** When the context-budget hook reports the budget: hand off
  (below). Do not push on, do not wait for compaction. The runner starts the next session.

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

Model, effort and advisor are launch parameters the runner passes (`--model sonnet
--effort <plan header> --advisor fable`); consult the advisor before committing to an
approach, on a recurring error and before declaring done. At the end print the table of
`autopilot-usage <this session's transcript>` (newest `.jsonl` under
`~/.claude/projects/<cwd with "/" replaced by "-">/`).

### 1. Gate, branch, ticket
Gate = `.claude/autopilot.json` `gate`; if missing, compose it from the package manager
(lockfile) and the existing scripts (`references/init.md`) and persist it. No test runner →
set one up minimally, project-consistent, before implementing. Create
`.claude/.autopilot-active` whenever `.claude/autopilot.json` exists; remove it (and
`.claude/.autopilot-gate-blocks`) at the end and on every abort; never commit either.
Branch per the plan header: **session mode** checks out `<prefix>/<KEY>-<slug>` (prefix per
the project's branch convention in `CLAUDE.md`, else `feat`), which `/autopilot-plan`
created with the plan on it (create it from the base only when you wrote the plan yourself,
and commit the plan there first); **feature-branch mode** checks out the named feature
branch (create it from the base if missing) and commits straight onto it; several sessions
add up to one branch with one review at the end. `PLAN.md` must be on the checked-out branch
before the first package. A continuation checks out the existing branch. Work in the current
checkout (the runner's worktree).

**Ticket.** A ticket key in the plan header and `~/.claude/jira/env` present → `jira start
<KEY>` once before the first commit (In Progress, assigned to the token owner); a
continuation skips it. Env file missing → one line in `REPORT.md` ("ticket not updated: no
~/.claude/jira/env on this machine"), no other tracker call. Never transition a ticket to a
done or merged status.

### 2. Packages, in order
For each package with `[ ]`: set `[~]`, then

- **Follow the Implementation steps** of the package in order. Before each step open the
  anchored region (`sed -n` around `path:line`) and confirm the quoted anchor; moved by a few
  lines → use the real line; missing, or the signature does not fit the code as it is now →
  do the smallest change that keeps the step's intent, and record it in `DECISIONS.md` as
  `P<n> step <k>: <what differed> - <what you did instead>`. Never skip a step silently, never
  redesign a package because one step was off.
- **Tests at the seams the plan names** (public interfaces only), the test lines of the
  package as written: name, input, expected. Red before green: one failing test, run that
  file, confirm it fails on the assertion; minimal code to pass; refactor only what you wrote.
  Vertical slices, one test at a time. Mock only process boundaries. Reject:
  implementation-coupled, tautological, skipped, `.only`, cannot-fail.
- **Failures:** one hypothesis, one change, re-run. After the second failed fix on the same
  failure: write observed vs expected, bisect, then fix. Never weaken an assertion.
- **Docs** directly affected by the package (inline, the touched area's doc file).
- **Full cheap gate once**; paste its summary line. Green → commit (Conventional Commits,
  ticket key). Set `[x]` with a one-line result under the package (commits, gate line), or
  `[!]` with the gap named. Append `DECISIONS.md` for every assumption you made.

### 3. Review, once, on the whole branch
`evelan:autopilot-reviewer` with the diff against the base branch and `PLAN.md`. Fix every
correctness, requirement or safety gap test-first, re-gate, commit. At most two cycles, each
a fresh reviewer dispatch on the updated diff;
unresolved real gaps go to the top of `REPORT.md` and into the PR description.

**Codex cross-model review, on by default.** After the Claude review is settled, run
`evelan:codex-review` on the branch (`--base <base branch>`) unless the prompt or the
plan header `Options:` says "ohne Codex" / "no Codex" or `codex-cli --version` fails (then one line in `REPORT.md`:
Codex review skipped, why). Treat Codex's findings exactly like the reviewer's (fix every
correctness, requirement or safety gap test-first, re-gate, commit; one cycle), rebut the
rest with evidence in `REPORT.md` under "Codex review". Codex rate-limited or unavailable →
skip with the reason in `REPORT.md`; do not run the skill's Claude fallback.

### 4. Goal artifact
Exercise the goal artifact in the real thing: start the dev server (`.claude/launch.json` or
the project's script, in the background, output to a file), drive the acceptance criteria
with `agent-browser` per `references/browser.md` (routes, expected text, invalid input, error
states, `console`, `errors`, `network requests`, phone viewport, one screenshot per screen
into the session folder), or open the generated report or document. Fix test-first,
re-verify, close the browser session, stop the server. A missing precondition (a database,
a seeded user, a service) is a blocker to resolve, not a skip. A check that needs a login
without a `browserState` file goes to `MANUAL_TESTING.md` with the exact steps; only steps
this environment cannot perform go there.

### 5. Finish
**Docs are part of done.** Walk the diff once and update every document the change made
stale: README and top-level docs for user-facing behaviour or public API; `docs/` pages that
describe the touched area; `CLAUDE.md` and `.claude/rules/` when a convention, command or
gate changed; inline doc comments on changed public interfaces. A stale doc is a gap, the
reviewer flags it. `build` once.
Write `REPORT.md`: first line `Status: done` (or, on an abort, `Status: blocked - <reason>`;
the runner reads this line and treats anything else as blocked), then what shipped,
verification with commands and results (browser checks included), review findings, open
items. Prepend one line to `docs/autopilot/INDEX.md` (below the marker, never rewrite),
delete a consumed `HANDOFF.md`, remove the sentinel, commit. Artifact layout and INDEX
marker: `references/artifacts.md`.

### 6. PR, CI, ticket comment
"defer PR" in the prompt or the plan header `Options:` → report branch and state, stop. Before any push: when
`.claude/autopilot.json` has `gateFull` (the project's full gate, e.g. with integration
tests), run it once; red → fix, re-run; a precondition it needs (a test database, a service)
is a blocker to resolve, not a skip. Feature-branch mode → push the feature branch
(`git push origin <feature>`; pull with rebase first if it moved), no PR; the feature branch
gets its PR when the last session of the feature is done. Otherwise push, then **one PR**:
`gh pr list --head <branch>` first; a PR exists (the plan skill opened a draft for the queue)
→ update its body with the report summary and mark it ready (`gh pr ready <n>`; review
workflows skip drafts, so this is what triggers the review); none → `gh pr create` (ticket
key in the title). Never merge. `gh pr checks <n> --watch`; a red CI check → fix,
re-push, until green. The review check is not CI: red there means the review pipeline is
broken, never a finding; note it in `REPORT.md` and move on.

**Ticket comment.** With `~/.claude/jira/env`: `jira comment <KEY> -` with the first lines of
`REPORT.md` (status, what shipped, PR link, open items) as plain text, no Markdown headings.
Feature-branch mode: the branch name and the session directory instead of a PR link.

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
(5) close the `agent-browser` session and stop a dev server you started; (6) remove
`.claude/.autopilot-active` and `.claude/.autopilot-gate-blocks` so the Stop hook lets the
turn end (the fresh session recreates the sentinel); (7) end the turn with one line:
`Resume with /autopilot <session directory>`. The runner starts the fresh session by itself,
up to five times per item (`references/mission-control.md`). HANDOFF.md format:
`references/handoff.md`.

## Stop conditions (abort: `REPORT.md` with `Status: blocked - <reason>` as its first line, `HANDOFF.md` deleted, artifacts committed, sentinel removed, browser session closed)
- The gate cannot go green without a destructive action or human input.
- The task needs anything on the never-list: force-push, `migrations/`, secrets, env files,
  production config, CI credentials, other people's branches.
- `agent-browser` is not installed and the goal artifact needs a browser.
