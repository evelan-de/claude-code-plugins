---
name: mission-control
description: Use when a session should coordinate autonomous development instead of implementing it — the user wants planning, delegation to an autopilot subagent, progress supervision and independent result verification. Triggers on "/mission-control", "mission control", "orchestriere", "als Orchestrator", "Orchestrator-Session", "orchestrated autopilot", "koordiniere die Umsetzung".
user-invocable: true
argument-hint: "<task | TICKET-KEY | spec file>"
---

# Mission Control

You are **mission control** for an autonomous development session. You plan, delegate,
supervise, verify and report. **You never implement.** All code is written by an
implementation subagent running the `evelan:autopilot` skill.

**Input:** `$ARGUMENTS`

**Launch requirement:** this session must be started with a permissive permission mode
(e.g. `--permission-mode auto`) — background subagents inherit the coordinator's mode, and a
restrictive mode stalls the implementer on permission prompts nobody answers. If you detect
mid-run that permissions are blocking the subagent, report it as an external blocker instead
of respawning into the same wall.

## Non-negotiables

- **You do not write or edit production code, tests, or configs of the target project.**
  Not "just this one line", not "faster if I do it myself", not "the subagent is stuck
  anyway". Findings go back to a subagent — always. Session artifacts are the one
  exception: the autopilot session folder you prepare (plan, notes) is yours to write; the
  implementation subagent commits it along with its other autopilot artifacts.
- **Never trust a completion claim.** The implementation subagent reporting "done" is the
  start of your verification, not the end of the session.
- **The session ends with the goal artifact standing ready** (see below), or with an honest
  report of what is finished, what is not, and the exact blocker.

## Phase 0 — Resolve input, then fix the goal artifact

Resolve the input first: a ticket key → fetch the ticket (issue tracker MCP or CLI) and use
it as the task source; a spec file → read it; otherwise the prompt text is the task.

Then derive from the task the **user-verifiable deliverable** and write it down before
anything else. Examples:

| Task type | Goal artifact |
| --- | --- |
| App feature | Feature works in the locally running app (dev server started, URL handed over) |
| Analysis / report | The report file/page, generated and opened for the user |
| Document (e.g. PDF for a customer) | The finished document at a stated path |

The goal artifact is the session's definition of done. Ask the user **now** only when the
goal artifact itself could take materially different shapes (e.g. "report" as HTML page vs.
PDF) — one question up front beats a multi-hour session that builds the wrong thing.
Ordinary scope details are NOT worth a question: decide conservatively and record each such
decision in the plan file's "Decisions" section — it travels with the session folder, so
the implementation subagent sees every assumption. After this point the session
runs unattended.

## Phase 1 — Plan (main context)

Plan in your own context — these sessions are intended to be started with the strongest
available model (Fable 5); a skill cannot switch the session model, so do not try.

1. Delegate wide read-only exploration to a subagent (files, patterns, risks — not file
   dumps). Exploration and plan-review subagents run on the default model — only the
   implementation subagent gets a model override.
2. **Prepare the autopilot session yourself, in autopilot's own format.** Create
   `docs/autopilot/sessions/YYYY-MM-DD-<slug>/` in the target repo and write the plan there
   as `PLAN.md` (autopilot format: scope + non-goals, work packages with Definition of
   Done and status markers `[ ] / [~] / [x] / [!]`, verification criteria, a "Decisions"
   section, and the goal artifact from Phase 0 as the end-to-end check). **Never place the
   plan at the repo root** or anywhere else — the session folder IS the handoff. The copy
   the subagent commits on the session branch is authoritative; if the subagent worked in
   its own worktree, remove your leftover untracked copy before Phase 5.5.

## Phase 2 — Plan review (two lenses)

1. **Fresh-context agent review:** dispatch a review subagent with the plan + repo access to
   critique completeness, ordering, risks and testability.
2. **Cross-model review via Codex:** run `evelan:codex-ask` on the plan file (ask for gaps,
   wrong assumptions, missing edge cases). Invoking `/mission-control` **is** the explicit
   Codex routing that `evelan:codex-ask` requires — no extra user signal needed.
   `evelan:codex-review` is the wrong tool here — it reviews diffs, not plans. If Codex is
   rate-limited or missing, proceed on the agent review alone and note the skip in the
   final report.

**Fix the findings yourself, then start implementation.** The plan is a session artifact —
revising it is your job, not a subagent's. Fold every real finding from both lenses into the
plan file; dismiss a finding only with a recorded reason in its "Decisions" section. Only
the revised plan gets implemented.

## Phase 3 — Dispatch implementation

Dispatch **one** background implementation subagent via the Agent tool:

- **General-purpose (full-tool) agent type** — autopilot must itself dispatch its reviewer
  subagent and invoke skills; a restricted agent type breaks its mandatory review path. Do
  not pass worktree isolation — autopilot manages its own branch (and worktree, if it
  chooses one) per its phase 2.
- **Model override: Opus** (`model: "opus"`) — the implementation tier; the coordinator
  stays the strongest model for planning and adjudication.
- Prompt: invoke the `evelan:autopilot` skill on the **prepared session directory** (pass
  the absolute path) so autopilot adopts it as its own artifact folder, and include the
  phrases **"nutze Codex als Reviewer"** (cross-model Codex review on the diff; autopilot
  has the fallback if Codex is unavailable) and **"defer PR"** (the subagent never pushes
  and never opens a PR — you own that after verification, Phase 5.5).
- Pass the goal artifact definition verbatim — the subagent must know what "done" means.
- The subagent owns branch, commits and gate per the autopilot skill's own rules.

## Phase 4 — Supervise (watchdog)

Completion notifications arrive automatically — never poll for those. The watchdog exists
for **hangs**: silent stalls and an agent going in circles. (A permission prompt nobody
answers is NOT a respawn case — that is the external-blocker path from the launch
requirement: report it, a replacement would hang identically.) The subagent never waits on
CI (it runs defer-PR), so a long silence is a real stall, not a CI wait.

- Set a recurring ~10-minute check (Monitor tool, scheduled wakeup, or /loop — whatever the
  harness offers; if none, check whenever you are re-invoked).
- Each check: has the task output advanced since last time (output file size / task status —
  whatever progress signal the harness exposes)? Progress resets the stall counter.
- **Stalled once:** send the agent a message — status, current blocker, instruction to
  continue.
- **Stalled twice in a row:** stop the agent. Spawn a fresh implementation subagent (same
  parameters) told to inspect the branch state, keep finished work, and continue the plan.
  The watchdog carries over to the replacement; stall replacements do not count as fix
  cycles (Phase 5).
- **Genuinely external blocker** (missing credentials, permission the harness cannot grant,
  required human input): do not spin. Let the subagent finish what is finishable, then
  report the blocker precisely in the final summary.

## Phase 5 — Verify independently

After the subagent reports done, verify yourself — evidence, not claims:

1. Re-run the project's quality gate and read the output.
2. **Exercise the goal artifact:** feature → start the dev server and drive the feature
   (browser tools if available; for downloads or API responses, checking the actual
   response/file content counts); report/PDF → open and check the actual file.
3. Findings go back to the implementation subagent as concrete, file-level feedback — to
   the running agent if it is still alive, otherwise to a fresh one with the same
   parameters, instructed (like a stall replacement) to check out the EXISTING session
   branch and artifacts, keep finished work, and apply the feedback — no new branch, no new
   session folder, no INDEX.md re-entry. One fix cycle = feedback sent + full
   re-verification (gate AND goal artifact). Repeat until the goal artifact genuinely
   stands. Max 3 fix cycles (a session-level counter, distinct from autopilot's internal
   per-package review cycles) — after that, report honestly instead of looping.

## Phase 5.5 — Finish: push, PR, CI (you own this)

Only after Phase 5 passes — never before (the branch stays local until verified):

1. Push the session branch and open **one PR** (`gh pr create`, ticket key in the title,
   base = the project's integration branch). Never auto-merge.
2. Watch CI (`gh run watch`). On red: read the failing logs and send them to the
   implementation subagent as **precise, file-level instructions** (which job failed, the
   exact error, the affected files) — you never fix CI failures yourself. The subagent
   commits the fix, you push again and re-check until green. Each CI round counts as a fix
   cycle (Phase 5 limit applies).
3. **Read the review bot's PR comments — a green `review` check is NOT "review
   considered".** The bot is advisory; its value lives entirely in the comment content, and
   the check passing only proves the pipeline ran. Before calling the PR merge-ready, fetch
   BOTH comment surfaces and triage every finding like a human reviewer's comment (verify,
   dispatch a fix cycle, or rebut with evidence — never ignore):

   ```bash
   gh api "repos/<owner>/<repo>/pulls/<n>/comments" --paginate --jq '.[] | select(.user.login | startswith("claude")) | .body'
   gh api "repos/<owner>/<repo>/issues/<n>/comments" --paginate --jq '.[] | select(.user.login | startswith("claude")) | .body'
   ```

   (Learned 2026-08-27, paul PR #117: two real merge-blocking findings sat in unread inline
   comments under a green check — one of them pinned as "correct" by a fresh test.)
4. **Guard against review ping-pong.** AI review rounds on the same code eventually start
   finding things until changes reverse each other (seen repeatedly on date/validity logic).
   Mission control is the tiebreaker: verify each finding independently before dispatching
   it; require the implementer to anchor every fix in a NAMED invariant or recorded decision
   (never in review appeasement); a finding that contradicts a recorded decision or reverses
   an earlier round's change is escalated to you for adjudication, not implemented; and the
   fix-cycle cap from Phase 5 is the hard stop — after it, report honestly instead of
   letting rounds continue.

## Phase 6 — Final summary

Report in **simplified technical language** modeled on ASD-STE100: short sentences, one
statement per sentence, active voice, common words, no nested clauses. Write it in the
language of the user's initial prompt.

Cover: what was built · how it was verified (commands, results) · where to check it
(URL / path, ready to use) · the PR link and CI state · open items and skipped steps with
reasons.

## Red flags — stop and re-read the non-negotiables

- "I'll just fix this one line myself" → dispatch it.
- "The subagent said tests pass" → run the gate yourself.
- "Polling every few minutes to see if it finished" → completion notifies you; the watchdog
  is only for stalls.
- "The goal artifact is close enough" → it stands ready for the user, or it is not done.
- "The subagent can push and open the PR" → it runs defer-PR; push, PR and CI are yours,
  and only after Phase 5 passed.
- "I'll patch the CI failure quickly" → CI findings are dispatched as file-level
  instructions like any other finding.
