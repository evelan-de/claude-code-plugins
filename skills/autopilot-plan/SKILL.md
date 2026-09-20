---
name: autopilot-plan
description: Write the plan an autopilot run executes. Interactive, in your own session, for one topic (ticket, spec, or idea). Triggers on "/autopilot-plan", "autopilot plan", "Plan für den Autopiloten", "bereite eine Autopilot-Session vor", "prepare an autopilot session".
user-invocable: true
argument-hint: "<ticket key | spec file | topic>   (add 'feature branch <name>' when several sessions share one branch)"
---

# Autopilot plan

One topic, one plan file, written with the user in the loop. The plan is what `/autopilot`
executes unattended, so every decision an unattended agent would otherwise guess is made
here, once. Developers run this too. It borrows the working rules of the interactive
workflow skills: seams agreed before slicing (`write-spec`), tracer-bullet slices with
blocking edges and a quiz on granularity (`spec-to-tickets`), and a named destination
(`wayfinder`).

**Input:** `$ARGUMENTS`.

## 1. Resolve the input

- Ticket key (`WEB-1095`, `#42`): fetch it via the project's tracker (`docs/agents/issue-tracker.md`
  or `gh issue view`). Title, description, acceptance criteria, comments.
- Spec file, `SPEC.md`, or a spec issue from `/evelan:write-spec`: read it; its user stories,
  implementation and testing decisions are the plan's raw material.
- A `wayfinder:map` with open decision tickets: stop and say so; decisions come before plans.
- Otherwise the prompt is the topic. If `CONTEXT.md` or ADRs exist, read them first and use
  their terms.

## 2. Explore, bounded

Locate with `grep -n`, read with `sed -n a,bp` in slices of at most ~80 lines, never a whole
file. Find: the files and interfaces the topic touches, the existing patterns to follow, the
test setup and gate command (`.claude/autopilot.json`), the risks (migrations, auth, CI
constraints, flaky areas), and **prefactoring** that would make the change easy ("make the
change easy, then make the easy change"). Verify every anchor you will write down by opening it.

## 3. Seams first, then ask once

Sketch the **seams** the tests will hit: existing seams preferred, the highest possible, as few
as possible (the ideal is one). Then ask the user once, together, via AskUserQuestion:

- do these seams match their expectations;
- the shape questions a plan cannot decide: what exactly, for whom, what is out, which
  trade-off, which **goal artifact** (feature running locally, a report, a document);
- the **branch mode**: one branch and PR per session (default), or a shared **feature
  branch** that several sessions push to and that gets one review at the end.

Everything else you decide conservatively and record under "Decisions". Never ask what the
code answers.

## 4. Slice, then quiz

Break the work into **tracer bullets**: each package a narrow but complete path through every
layer it needs (schema, API, UI, tests), demoable or verifiable on its own, sized for one
fresh context with the gate green. Prefactoring first. Give each package its **blocking
edges**. A **wide refactor** (one mechanical change with a blast radius across the codebase)
is not a tracer bullet: sequence it expand → migrate in batches → contract, each batch a
package blocked by the expand.

Show the packages as a numbered list (title, blocked by, what it delivers) and ask the user
once: granularity right, edges right, merge or split anything? Iterate until approved.

## 5. Write `PLAN.md`

Path: `docs/autopilot/sessions/YYYY-MM-DD-<slug>/PLAN.md` in the repo (slug lowercase,
hyphenated; ticket key first when there is one). One file, under 200 lines, this shape:

```
# PLAN - <ticket key or topic> - <YYYY-MM-DD>
Branch: <prefix>/<KEY>-<slug>   Base: <integration branch>   Ticket: <key or none>
Branch mode: session | feature-branch <name>     PR: per session | none (feature branch reviewed as a whole)
Sources: <spec, ADRs, docs the packages point to>

## Destination
<one paragraph: what the user gets when this plan is done>

## Goal artifact
<the user-verifiable deliverable, binding for the end check: e.g. "feature works in the
locally running app at <route>", "report at <path>">

## Scope / Non-goals
- in: ...
- out: ...

## Decisions
- <decision> - <reason>

## Seams
- <public interface the tests hit> - <prior art: existing test that does the same>

## Packages (dependency order; status [ ] [~] [x] [!])
### P1 [ ] <title>
Delivers: <the end-to-end behaviour the user gets, not a layer list>
Blocked by: none
Files: <paths as of today>   Seams: <from the list above>
Verify: <test cases with inputs and expected outputs; typecheck/lint/build expectation>
Edge cases: <...>
### P2 [ ] <title>
Blocked by: P1
...

## Manual steps (only what this environment cannot do)
```

Rules: exact commands, paths and names (they are read within days, not months), no narrative,
no ticket history. The plan is the whole spec the run sees: nothing lives only in the ticket.

## 6. Optional review

On "review the plan" or for a topic with five or more packages: dispatch
`evelan:autopilot-plan-reviewer` (read-only, small tool set) with the plan path and the
sources; fold real findings in, dismiss with a reason under "Decisions".

## 7. Commit and hand over

Commit `PLAN.md` on the current branch (`docs(autopilot): plan for <key or slug>`). Tell the
user the path and the one command that runs it: `/autopilot <session directory>`, and how to
pick the run's model at launch (`claude --model sonnet --advisor fable`, see the autopilot
skill). Say what is still open, if anything. Do not implement anything here.
