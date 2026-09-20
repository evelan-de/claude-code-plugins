---
name: autopilot-plan
description: Write the plan an autopilot run executes. Interactive, in your own session, for one topic (ticket, spec, or idea). Triggers on "/autopilot-plan", "autopilot plan", "Plan für den Autopiloten", "bereite eine Autopilot-Session vor", "prepare an autopilot session".
argument-hint: "<ticket key | spec file | topic>   (add 'feature branch <name>' when several sessions share one branch)"
---

# Autopilot plan

One topic, one plan file, written with the user in the loop. The plan is what `/autopilot`
executes unattended, so every decision an unattended agent would otherwise guess is made
here, once. Developers run this too.

**Input:** `$ARGUMENTS`.

## 1. Resolve the input

- Ticket key (`WEB-1095`, `#42`): fetch it via the project's tracker (`docs/agents/issue-tracker.md`
  or `gh issue view`). Title, description, acceptance criteria, comments.
- Spec file, `SPEC.md`, or a spec issue from `/evelan:to-spec`: read it; its user stories,
  implementation and testing decisions are the plan's raw material.
- A topic with open decision tickets: stop and say so; decisions come before plans.
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

Template: `references/plan-template.md`.

Rules: exact commands, paths and names (they are read within days, not months), no narrative,
no ticket history. The plan is the whole spec the run sees: nothing lives only in the ticket.

## 6. Optional review

On "review the plan" or for a topic with five or more packages: dispatch
`evelan:autopilot-plan-reviewer` (read-only, small tool set) with the plan path and the
sources; fold real findings in, dismiss with a reason under "Decisions".

## 7. Commit and hand over

Commit `PLAN.md` on the branch the plan header names, so the run finds it: session mode →
create `<prefix>/<KEY>-<slug>` from the base (prefix per the project's branch convention in `CLAUDE.md`, else `feat`) and commit there; feature-branch mode → check out
the feature branch (create it from the base if missing) and commit there. Commit message
`docs(autopilot): plan for <key or slug>`. Write the chosen effort into the plan header
(`Effort: medium`) so the queue and the launch line agree. Tell the user the path, the one
command that runs it (`/autopilot <session directory>`) and the launch line:

```
claude --model sonnet --effort medium --advisor fable --fallback-model opus --permission-mode auto
```

Effort per the plan header (default medium). `--advisor` is accepted although `claude --help`
does not list it. Turn and dollar caps (`--max-turns 400 --max-budget-usd 60`) exist only in
headless mode (`claude -p`, used by the queue runner), not in an interactive launch.
Say what is still open, if anything. Do not implement anything here.
