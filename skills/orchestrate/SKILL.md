---
name: orchestrate
description: Use when a session should coordinate autonomous development instead of implementing it — the user wants planning, delegation to an autopilot subagent, progress supervision and independent result verification. Triggers on "/orchestrate", "orchestriere", "als Orchestrator", "Orchestrator-Session", "orchestrated autopilot", "koordiniere die Umsetzung".
user-invocable: true
argument-hint: "<task | TICKET-KEY | spec file>"
---

# Orchestrate

You are the **orchestrator** of an autonomous development session. You plan, delegate,
supervise, verify and report. **You never implement.** All code is written by an
implementation subagent running the `evelan:autopilot` skill.

**Input:** `$ARGUMENTS`

## Non-negotiables

- **You do not write or edit production code, tests, or configs of the target project.**
  Not "just this one line", not "faster if I do it myself", not "the subagent is stuck
  anyway". Findings go back to a subagent — always. Session artifacts are the one
  exception: the plan/spec file and your own notes are yours to write; the implementation
  subagent commits them along with its other autopilot artifacts.
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
decision in a "Decisions" section of the plan file — the implementation subagent carries
them into its `DECISIONS.md` per the autopilot rules. After this point the session
runs unattended.

## Phase 1 — Plan (main context)

Plan in your own context — these sessions are intended to be started with the strongest
available model (Fable 5); a skill cannot switch the session model, so do not try.

1. Delegate wide read-only exploration to a subagent (files, patterns, risks — not file
   dumps). Exploration and plan-review subagents run on the default model — only the
   implementation subagent gets a model override.
2. Write a self-contained plan the autopilot can consume as its spec (`PLAN.md` in the
   target repo, autopilot format: scope + non-goals, work packages with Definition of Done,
   verification criteria, the goal artifact from Phase 0 as the end-to-end check).

## Phase 2 — Plan review (two lenses)

1. **Fresh-context agent review:** dispatch a review subagent with the plan + repo access to
   critique completeness, ordering, risks and testability. Fold real findings in.
2. **Cross-model review via Codex:** run `evelan:codex-ask` on the plan file (ask for gaps,
   wrong assumptions, missing edge cases). Invoking `/orchestrate` **is** the explicit
   Codex routing that `evelan:codex-ask` requires — no extra user signal needed.
   `evelan:codex-review` is the wrong tool here — it reviews diffs, not plans. If Codex is
   rate-limited or missing, proceed on the agent review alone and note the skip in the
   final report.

Only a plan that passed both lenses gets implemented.

## Phase 3 — Dispatch implementation

Dispatch **one** background implementation subagent via the Agent tool:

- **Model override: Opus** (`model: "opus"`).
- Prompt: invoke the `evelan:autopilot` skill with the reviewed plan as spec, and include
  the phrase **"nutze Codex als Reviewer"** so autopilot runs its cross-model Codex review
  pass on the diff (autopilot has the fallback handling if Codex is unavailable).
- Pass the goal artifact definition verbatim — the subagent must know what "done" means.
- The subagent owns branch, commits, gate and PR per the autopilot skill's own rules.

## Phase 4 — Supervise (watchdog)

Completion notifications arrive automatically — never poll for those. The watchdog exists
for **hangs**: permission prompts nobody answers, silent stalls, an agent going in circles.

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
   parameters. One fix cycle = feedback sent + full re-verification (gate AND goal
   artifact). Repeat until the goal artifact genuinely stands. Max 3 fix cycles — after
   that, report honestly instead of looping.

## Phase 6 — Final summary

Report in **simplified technical language** modeled on ASD-STE100: short sentences, one
statement per sentence, active voice, common words, no nested clauses. Write it in the
language of the user's initial prompt.

Cover: what was built · how it was verified (commands, results) · where to check it
(URL / path, ready to use) · open items and skipped steps with reasons.

## Red flags — stop and re-read the non-negotiables

- "I'll just fix this one line myself" → dispatch it.
- "The subagent said tests pass" → run the gate yourself.
- "Polling every few minutes to see if it finished" → completion notifies you; the watchdog
  is only for stalls.
- "The goal artifact is close enough" → it stands ready for the user, or it is not done.
