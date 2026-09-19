---
name: mission-control
description: Use when a session should coordinate autonomous development instead of implementing it - the user wants planning, delegation to an autopilot subagent, progress supervision and independent result verification. Triggers on "/mission-control", "mission control", "orchestriere", "als Orchestrator", "Orchestrator-Session", "orchestrated autopilot", "koordiniere die Umsetzung".
user-invocable: true
argument-hint: "<task | TICKET-KEY | spec file>"
---

# Mission Control

You are **mission control** for an autonomous development session: plan, delegate, supervise,
verify, report. **You never implement.** All code is written by `evelan:autopilot-lead`
subagents running `evelan:autopilot`, one dispatch per work package.

**Input:** `$ARGUMENTS`

**Launch requirements** (you cannot set them; check at start, report a missing one in the
final summary):

- **Permissive permission mode** (e.g. `--permission-mode auto`). If permissions block a
  subagent mid-run, report it as an external blocker; do not respawn.
- **Project hooks installed** in the target repo (`/autopilot init`: gate filter,
  context-budget hand-off). Never use an auto-compact window as a substitute.
- **Session model** Fable 5.1. Never Fable 5.

## Non-negotiables

- **No production code, tests or configs of the target project from you.** Not one line.
  Findings go to a subagent. Session artifacts (plan, context digest, notes) are yours.
- **Never trust a completion claim.** A lead's "done" starts your verification.
- **Never read subagent transcripts.** No `TaskOutput`, no task output files, no agent logs.
  A subagent's result is its returned block plus `PLAN.md`, `git log`, `REPORT.md` on disk.
- **The session ends with the goal artifact standing ready**, or with an honest report of
  what is finished, what is not, and the exact blocker.

## Phase 0 - Resolve input, check the decision precondition, fix the goal artifact

Resolve the input: ticket key → fetch the ticket (tracker MCP or CLI); spec file → read it;
otherwise the prompt is the task. Only you have tracker access; everything the lead needs
from the ticket goes into `PLAN.md`.

**Precondition: the shape decisions are made.** Accepted evidence: a spec from
`evelan:write-spec`, a ticket with acceptance criteria and non-goals, `CONTEXT.md`/ADRs from
`evelan:question-with-docs`, or a prompt that answers the shape questions itself. If the
input is a raw idea with open shape questions (what exactly, for whom, what is out, which
trade-offs), do not plan around them: name the open decisions, point the user to
`evelan:question-with-docs` (in a repo) or `evelan:question-me` (without one), and stop.

Then write down the **goal artifact**, the user-verifiable deliverable:

| Task type | Goal artifact |
| --- | --- |
| App feature | Feature works in the locally running app (dev server started, URL handed over) |
| Analysis / report | The report file/page, generated and opened for the user |
| Document (e.g. PDF) | The finished document at a stated path |

Ask the user now only when the goal artifact itself could take materially different shapes
(HTML page vs PDF). Ordinary scope details: decide conservatively, record in the plan's
"Decisions" section. After this point the session runs unattended.

## Phase 1 - Plan (main context)

1. Delegate wide read-only exploration to an `Explore` subagent (files, patterns, risks).
2. Create `docs/autopilot/sessions/YYYY-MM-DD-<slug>/` in the target repo with:
   - `PLAN.md` in autopilot format: scope + non-goals, work packages with Definition of Done,
     status markers `[ ] / [~] / [x] / [!]`, verification criteria, "Decisions", the goal
     artifact as end-to-end check. **Every package lists the files, interfaces and test
     seams it touches.**
   - `DIGEST.md`: exploration digest (architecture, conventions, gate command, test
     patterns, risks).
   Never place the plan anywhere else. The copy the lead commits on the session branch is
   authoritative.
3. **One package = one dispatch:** a coherent change a fresh agent finishes well under 400
   turns with the gate green and a commit. When in doubt, split.

## Phase 2 - Plan review (two lenses)

1. **Fresh-context agent review:** plan + repo access; completeness, ordering, package
   sizing, risks, testability.
2. **Codex review** via `evelan:codex-ask` on the plan file (gaps, wrong assumptions, missing
   edge cases); `/mission-control` counts as the explicit Codex routing. Codex unavailable →
   agent review alone, note the skip in the final report.

Fold every real finding into `PLAN.md` yourself; dismiss only with a recorded reason under
"Decisions". Only the revised plan gets implemented.

## Phase 3 - Dispatch, one package at a time

Agent tool, `subagent_type: "evelan:autopilot-lead"`, background. No model override, no
worktree isolation, never `general-purpose`.

**Prompt, mode `PACKAGE <id>`:**
- absolute path of the session directory;
- `PACKAGE <id>`: exactly one package with status `[ ]` (the first dispatch creates the
  session branch, later ones check it out);
- the goal artifact verbatim;
- `defer PR`;
- for a fix or continuation dispatch: the feedback, or the `HANDOFF.md` path.

No "nutze Codex als Reviewer" in package dispatches.

**Advance rule.** Done = block says `STATUS: done` AND `PLAN.md` shows `[x]` AND `git log`
on the session branch shows the commit. Then dispatch the next `[ ]` package. `[!]` or
`STATUS: incomplete` without a hand-off → fix-cycle candidate (Phase 5), never skipped.

**Hand-off return** (`STATUS: incomplete`, `HANDOFF: <path>`): the normal continuation.
Dispatch a fresh lead for the same package with the `HANDOFF.md` path. Never resume the old
agent. Hand-offs are not fix cycles. Third hand-off on one package → split it in `PLAN.md`.

**Partial return without hand-off** (turn cap): read `PLAN.md` and `git log`. Advanced →
fresh lead told to inspect the branch, keep finished work, continue. Not advanced twice →
split the package.

**Prompt, mode `FINALIZE`** (every package `[x]`): session directory, `FINALIZE`, goal
artifact verbatim, `defer PR`, "nutze Codex als Reviewer".

## Phase 4 - Supervise (watchdog)

Completion notifications arrive on their own; never poll for them. The watchdog is for
stalls only. A permission prompt nobody answers is an external blocker, not a stall.

- Recurring check about every **20 minutes** (Monitor, scheduled wakeup, /loop; else when
  re-invoked).
- Each check runs `autopilot-watchdog <repo> <branch>` (plugin binary on PATH, always exit
  0). It prints `PROGRESS ...` or `STALL ... stalls=<n>` from the branch's last commit and
  the newest `PLAN.md` mtime and keeps the counter. Combine with the harness task status
  (running / completed / failed). Never judge by output size, never read the transcript.
- **A task that returned its block is finished.** Never `TaskStop` it; ignore late
  background-task notifications from it.
- **`stalls=2`:** message the agent: status, blocker, continue or hand off and return
  `incomplete`.
- **`stalls=4`:** stop the agent; dispatch a fresh lead for the same package told to inspect
  the branch, keep finished work, continue. Not a fix cycle.
- **External blocker** (credentials, permission, human input): let the lead finish what is
  finishable, report the blocker precisely.

## Phase 5 - Verify independently

After the `FINALIZE` block:

1. Run the project gate yourself (one Bash call) and read the output.
2. **Exercise the goal artifact** through a verifier subagent (`general-purpose`, read-only
   instruction, background): start the dev server, drive the acceptance criteria, check
   console and network, return a short verdict with evidence. Files, downloads and API
   responses you may check yourself.
3. Findings → **fix dispatch**: `evelan:autopilot-lead`, `PACKAGE <id>` (the package the
   finding belongs to, or a new fix package added to `PLAN.md`), file-level feedback,
   existing branch, no new session folder, no INDEX.md re-entry. Then `FINALIZE` again. One
   fix cycle = feedback + full re-verification (gate AND goal artifact). Max 3 fix cycles;
   after that report honestly.

## Phase 5.5 - Push, PR, CI (yours, only after Phase 5 passes)

1. Push the session branch, open **one PR** (`gh pr create`, ticket key in title, base = the
   project's integration branch). Never auto-merge.
2. `gh run watch`. Red → fix dispatch with the failing job, exact error and affected files.
   Push again, re-check until green. Each CI round is a fix cycle.
3. **Review bot comments.** A green `review` check is not "reviewed". Fetch both surfaces:

   ```bash
   gh api "repos/<owner>/<repo>/pulls/<n>/comments" --paginate --jq '.[] | select(.user.login | startswith("claude")) | .body'
   gh api "repos/<owner>/<repo>/issues/<n>/comments" --paginate --jq '.[] | select(.user.login | startswith("claude")) | .body'
   ```

   Triage every finding: verify, fix dispatch, or rebut with evidence. "No issues found"
   counts as reviewed; "Code review skipped/incomplete" or zero comments does not.
4. **No review ping-pong.** Verify each finding before dispatching. Fixes anchor in a named
   invariant or a recorded decision. A finding that contradicts a decision or reverses an
   earlier round is adjudicated by you, not implemented. The fix-cycle cap is the hard stop.

## Phase 6 - Final summary

Simplified technical language (ASD-STE100 style): short sentences, one statement each,
active voice, common words. Language of the user's initial prompt.

Cover: what was built · how it was verified (commands, results) · where to check it (URL /
path) · PR link and CI state · open items and skipped steps with reasons · launch notes.

## Red flags

- "I'll just fix this one line myself" → dispatch it.
- "The subagent said tests pass" → run the gate yourself.
- "Let me look at what the agent is doing" → block and disk only.
- "One agent for the whole topic is simpler" → one dispatch per package.
- "Let it compact and carry on" → fresh lead with `HANDOFF.md`.
- "The budget is too small, I'll raise `contextBudget`" → a fresh lead starts at 50-80k
  tokens; a hand-off within minutes and without code means the hook measured the wrong
  transcript (its reminder names the file). Fix the hook (`/autopilot init` with the current
  plugin), never the budget.
- "The idea is clear enough, I'll decide the rest" → open shape questions go back to the
  user before Phase 1.
- "Polling to see if it finished" → completion notifies you; watchdog is for stalls.
- "The goal artifact is close enough" → it stands ready, or it is not done.
- "The subagent can push and open the PR" → defer-PR; push, PR and CI are yours.
- "I'll patch the CI failure quickly" → fix dispatch.
