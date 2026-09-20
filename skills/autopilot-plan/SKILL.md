---
name: autopilot-plan
description: Write the plan an autopilot run executes. Interactive, in your own session, for one topic (ticket, spec, or idea). Triggers on "/autopilot-plan", "autopilot plan", "Plan für den Autopiloten", "bereite eine Autopilot-Session vor", "prepare an autopilot session".
user-invocable: true
argument-hint: "<ticket key | spec file | topic>"
---

# Autopilot plan

One topic, one plan file, written with the user in the loop. The plan is what `/autopilot`
executes unattended, so every decision an unattended agent would otherwise guess is made
here. Developers run this too.

**Input:** `$ARGUMENTS`.

## 1. Resolve the input

- Ticket key (`WEB-1095`, `#42`): fetch it via the project's tracker (`docs/agents/issue-tracker.md`
  or `gh issue view`). Title, description, acceptance criteria, comments.
- Spec file or `SPEC.md`: read it.
- Otherwise the prompt is the topic. If `CONTEXT.md` or ADRs exist, read them first and use their
  terms.

## 2. Explore, bounded

Locate with `grep -n`, read with `sed -n a,bp` in slices of at most ~80 lines, never a whole
file. Find: the files and interfaces the topic touches, the existing patterns to follow, the
test setup and gate command (`.claude/autopilot.json`), the risks (migrations, auth, CI
constraints, flaky areas). Verify every anchor you will write down by opening it.

## 3. Ask only what a plan cannot decide

Shape questions go to the user, once, together, via AskUserQuestion: what exactly, for whom,
what is out, which trade-off, which goal artifact (feature running locally, a report, a
document). Everything else you decide conservatively and record under "Decisions". Never ask
what the code answers.

## 4. Write `PLAN.md`

Path: `docs/autopilot/sessions/YYYY-MM-DD-<slug>/PLAN.md` in the repo (slug lowercase,
hyphenated; ticket key first when there is one). One file, under 200 lines, this shape:

```
# PLAN - <ticket key or topic> - <YYYY-MM-DD>
Branch: <prefix>/<KEY>-<slug>   Base: <integration branch>   Ticket: <key or none>
Sources: <spec, ADRs, docs the packages point to>

## Goal
<one paragraph: what the user gets>

## Goal artifact
<the user-verifiable deliverable, binding for the end check: e.g. "feature works in the
locally running app at <route>", "report at <path>">

## Scope / Non-goals
- in: ...
- out: ...

## Decisions
- <decision> - <reason>

## Packages (dependency order; status [ ] [~] [x] [!])
### P1 [ ] <title>
Done when: <the user gets this working>
Files: <paths>   Seams: <public interfaces the tests hit>
Verify: <test cases with inputs and expected outputs; typecheck/lint/build expectation>
Edge cases: <...>
### P2 [ ] <title> (depends: P1)
...

## Manual steps (only what this environment cannot do)
```

Rules: packages are vertical slices a fresh context finishes with the gate green; each names
real seams that exist in the project's test setup; exact commands, paths and names, no
narrative. The plan is the whole spec the run sees: nothing lives only in the ticket.

## 5. Optional review

On "review the plan" or for a topic with five or more packages: dispatch
`evelan:autopilot-plan-reviewer` (read-only, small tool set) with the plan path and the
sources; fold real findings in, dismiss with a reason under "Decisions".

## 6. Commit and hand over

Commit `PLAN.md` on the current branch (`docs(autopilot): plan for <key or slug>`). Tell the
user the path and the one command that runs it: `/autopilot <session directory>`. Say what is
still open, if anything. Do not implement anything here.
