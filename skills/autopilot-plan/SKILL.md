---
name: autopilot-plan
description: Write the plan an autopilot run executes. Interactive, in your own session, for one topic (ticket, spec, or idea). Triggers on "/autopilot-plan", "autopilot plan", "Plan für den Autopiloten", "bereite eine Autopilot-Session vor", "prepare an autopilot session".
argument-hint: "<ticket key | spec file | topic>   (a topic without a ticket gets its ticket created; add 'feature branch <name>' when several sessions share one branch; add 'opus' to run it on Opus instead of Sonnet)"
---

# Autopilot plan

One topic, one plan file, written with the user in the loop. The plan is what `/autopilot`
executes unattended. It carries every decision, every insertion point, every signature,
every assertion. The run implements steps; it does not invent them.

**Input:** `$ARGUMENTS`.

## 0. Model

Default planner: Fable; Opus is fine. On Sonnet or Haiku say so in one line ("planning on
<model>; Fable or Opus is the intended planner") and continue.

## 1. Resolve the input

- Ticket key (`WEB-1095`, `#42`): fetch it via the project's tracker (`docs/agents/issue-tracker.md`
  or `gh issue view`). Title, description, acceptance criteria, comments.
- Spec file, `SPEC.md`, or a spec issue from `/evelan:to-spec`: read it; its user stories,
  implementation and testing decisions are the plan's raw material.
- A topic with open decision tickets: stop and say so; decisions come before plans.
- Otherwise the prompt is the topic. If `CONTEXT.md` or ADRs exist, read them first and use
  their terms. **No ticket yet:** create it after step 3, once the shape is settled, via the
  project's tracker (`docs/agents/issue-tracker.md`: Jira through the Atlassian MCP,
  `gh issue create`, or a file under `docs/issues/`): title from the destination, description
  from the destination, scope and goal artifact, in the tracker's description format. Use the
  new key everywhere a key is used (plan header, slug, branch name, commits, PR title).

## 2. Explore, whole files

Locate with `grep -n`, then read every file a package will touch **whole**, plus the tests
next to it and the types it imports. No read cap. Find: the files and interfaces the topic touches, the existing patterns to follow
(and the one file that is the best example of each), the test setup and gate command
(`.claude/autopilot.json`), the risks (migrations, auth, CI constraints, flaky areas), and
**prefactoring** that would make the change easy ("make the change easy, then make the easy
change"). Verify every anchor, signature and type you will write down by opening it; a
`path:line` in the plan is a promise.

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
layer it needs (schema, API, UI, tests), demoable or verifiable on its own. Prefactoring
first. Give each package its **blocking edges**. A **wide refactor** (one mechanical change
with a blast radius across the codebase) is not a tracer bullet: sequence it expand → migrate
in batches → contract, each batch a package blocked by the expand.

Size: a package touches at most ~6 files and ~300 diff lines and has at most ~8
implementation steps. Larger → split.

Show the packages as a numbered list (title, blocked by, what it delivers) and the **run
model** (Sonnet at effort xhigh by default; Opus when the user asks for it or named it in the
prompt), and ask the user once: granularity right, edges right, merge or split anything, run
model right? Iterate until approved.

## 5. Write `PLAN.md`

Template and the rules for Implementation steps: `references/plan-template.md`.

Per package, in this order: Delivers, Blocked by, Files, Seams, **Implementation** (numbered
steps, each with `path:line`, the quoted anchor line, the signature, the flow as pseudo-code,
the helper it reuses), **Tests** (file, runner command, one line per test with input →
expected), Verify (exact commands and expected lines; the browser check with route, viewport
and what must be visible), Edge cases. Exact commands, paths and names; no narrative, no
ticket history. The plan is the whole spec the run sees: nothing lives only in the ticket.

Goal artifact: name the browser checks the run performs with `agent-browser` (headless,
`skills/autopilot/references/browser.md`) and say whether they need a login state file
(`browserState` in `.claude/autopilot.json`; if the project has none and the check needs a
login, list it under "Manual steps" with the recipe from
`skills/autopilot/references/init.md`, step 6b).

## 6. Review

Three or more packages, or "review the plan": dispatch `evelan:autopilot-plan-reviewer`
(read-only, small tool set) with the plan path and the sources. Fold real findings in,
dismiss the rest with a reason under "Decisions", write `Reviewed: yes (<n> findings folded
in)` into the header. Fewer packages: `Reviewed: no (two packages)` unless asked.

## 7. Commit and hand over

Commit `PLAN.md` on the branch the plan header names, so the run finds it: session mode →
create `<prefix>/<KEY>-<slug>` from the base (prefix per the project's branch convention in
`CLAUDE.md`, else `feat`) and commit there; feature-branch mode → check out the feature
branch (create it from the base if missing) and commit there. Commit message
`docs(autopilot): plan for <key or slug>`. Write the approved run model and its effort into
the plan header so the runner reads them: `Model: sonnet` with `Effort: xhigh` (or `max`), or
`Model: opus` with `Effort: medium` (or higher when the user asks).

Then tell the user the path and the two ways to run it (every run is started and chained
by the runner, `mission-control`):

1. **On this machine** (`~/.claude/mission-control` exists here): `/autopilot <session
   directory>` enqueues the item and starts the runner in the
   background; progress via `/mission-control status`, macOS notifications and Slack.
2. **Hand to the queue on the office Mini**: push the branch, open a draft PR against the base (`gh pr create --draft --label
   autopilot-ready`, title `<KEY>: <destination in a few words>`, body: the Destination and
   Goal artifact paragraphs plus the path of `PLAN.md`; create the label when missing:
   `mission-control labels`). The queue picks it up on its next run, the result comes back on
   this PR (label `autopilot-done` or `autopilot-blocked`, report as a comment) and in Slack.
   Developer note: the repo must be listed in the queue's `repos.txt` on the Mini; Andreas
   adds a repo once (`mission-control doctor` prints the list), so a repo not yet on it goes
   to him with the PR link. Feature-branch mode has no PR: hand-over means pushing the
   feature branch and adding the item to the queue (`mission-control add <repo> <session
   dir>`, which records the branch; over SSH from the `/mission-control` skill).

Ask once which of the two, do it, say what is still open, if anything. Do not implement
anything here.
