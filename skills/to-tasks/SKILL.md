---
name: to-tasks
description: Break a plan, spec, or the current conversation into a set of tracer-bullet tasks (tickets on the configured tracker), each declaring its blocking edges (edges as text in one file per ticket locally, or native blocking links on a real tracker). Triggers on "/to-tasks", "split this into tickets", "break the spec into tasks", "zerleg das in Tickets", "mach Tasks daraus".
disable-model-invocation: true
---

# To tasks

Break a plan, spec, or conversation into **tickets**: tracer-bullet vertical slices, each declaring the tickets that **block** it.

The issue tracker configuration should have been provided to you. If not, tell the user to run `/evelan:setup-workflow-skills`.

## Process

### 1. Gather context

Work from what is already in the conversation. If the user passes a reference (a spec path, an issue number or URL), fetch it and read its full body and comments.

### 2. Explore the codebase (if not done yet)

Explore the codebase to understand its current state. Use the project's glossary terms (`CONTEXT.md`) in titles and descriptions and respect ADRs in the area you touch, where they exist. Look for prefactoring that makes the implementation easier: "make the change easy, then make the easy change."

### 3. Draft vertical slices

- Each slice cuts a narrow but COMPLETE path through every layer (schema, API, UI, tests); never a horizontal slice of one layer
- A completed slice is demoable or verifiable on its own
- Each slice fits in a single fresh context window
- Prefactoring comes first

Give each ticket its **blocking edges**: the tickets that must complete before it can start.

**Wide refactors** (one mechanical change that fans across the whole codebase, such as renaming a column or retyping a shared symbol) are sequenced as expand-contract instead:
1. Expand: add the new form beside the old one.
2. Migrate in batches (per package or directory), each batch its own ticket blocked by the expand.
3. Contract: delete the old form, blocked by every migrate batch.

### 4. Quiz the user

Present the breakdown as a numbered list: per ticket the **title**, **blocked by**, and **what it delivers** end to end. Ask whether the granularity is right, whether every blocking edge genuinely gates, and whether any ticket should be merged or split. Iterate until the user approves.

### 5. Publish

Publish the approved tickets in dependency order (blockers first) so blocking edges can reference real identifiers. Follow `docs/agents/issue-tracker.md` for the mechanics:

- **Real tracker (Jira, GitHub, ...)**: one issue per ticket; use the platform's native blocking or sub-issue relationship where it has one, otherwise the "Blocked by" section below.
- **Local files**: one file per ticket under `docs/issues/<feature-slug>/<NN>-<slug>.md`, numbered from `01`, first line `# <NN>: <title>`, then the same body as below. Never a single combined file.

Work the **frontier**: any ticket whose blockers are all done; a linear chain means top to bottom.

Do NOT close or modify any parent issue.

<issue-template>

## Parent

Reference to the parent issue (omit if the source was not an existing issue).

## What to build

The end-to-end behaviour this ticket makes work, from the user's perspective.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Blocked by

- A reference to each blocking ticket, or "None (can start immediately)".

</issue-template>

No file paths or code snippets in tickets; they go stale fast.
