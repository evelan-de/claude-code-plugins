---
name: to-spec
description: "Turn the current conversation into a spec and publish it to the project issue tracker: no interview, just synthesis of what you've already discussed. Triggers on \"/to-spec\", \"write the spec\", \"turn this into a spec\", \"mach daraus eine Spec\", \"schreib die Spec\"."
disable-model-invocation: true
---

Take the current conversation and codebase understanding and produce a spec. Do NOT interview the user; synthesize what you already know.

The issue tracker configuration should have been provided to you. If not, tell the user to run `/evelan:setup-workflow-skills`.

## Process

1. Explore the repo to understand the current state of the codebase, if you haven't already.

2. Sketch the seams at which the feature will be tested. Prefer existing seams to new ones. Use the highest seam possible. If new seams are needed, propose them at the highest point you can. The fewer seams across the codebase, the better; the ideal number is one.

   Show the seams to the user and wait. Publish only after the user confirmed the seams.

3. Write the spec using the template below, then publish it to the project issue tracker.

<spec-template>

## Problem Statement

The problem the user is facing, from the user's perspective.

## Solution

The solution, from the user's perspective.

## User Stories

Numbered. One per distinct capability the feature adds; no filler. Format:

1. As an <actor>, I want a <feature>, so that <benefit>

## Implementation Decisions

The decisions that were made:

- The modules that will be built or modified
- The interfaces of those modules that will change
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

No file paths or code snippets; they go stale fast.

## Testing Decisions

- What makes a good test here (external behaviour only, not implementation details)
- Which modules will be tested, at which seams
- Prior art for the tests (similar tests already in the codebase)

## Out of Scope

What this spec does not cover.

## Further Notes

Anything else about the feature.

</spec-template>
