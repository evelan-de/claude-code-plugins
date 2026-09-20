---
name: which-skill
description: Ask which skill or flow fits your situation. A router over the skills in this repo.
disable-model-invocation: true
---

# Which skill?

You don't remember every skill, so ask.

A **flow** is a path through the skills. Most paths run along one **main flow**, and two **on-ramps** merge onto it. Everything else is standalone, or a vocabulary layer that runs underneath.

## The main flow: idea → ship

The route most work travels. You have an idea and want it built.

1. **`/evelan:question-me`** sharpens the idea by interview. In a working directory it is stateful, retaining what it learns in `CONTEXT.md` and ADRs; outside one it is the same interview without a paper trail.
2. **Branch: can you settle every question in conversation?** If a question needs a runnable answer (state, business logic, a UI you have to see), write a small throwaway program on a `prototype/<name>` branch, react to it, and fold the answer back into the idea thread; bridge with **`/evelan:handoff`** when the prototype lives in its own directory.
3. **Branch: is this a multi-session build?**
   - **Yes** → **`/evelan:to-spec`** (turn the thread into a spec), then **`/evelan:to-tasks`** to split it into tracer-bullet tickets, each declaring its **blocking edges**. On a local tracker that's one file per ticket under `.scratch/<feature>/issues/`, worked blockers-first by hand; on a real tracker the edges become native blocking links, so any ticket whose blockers are done can be grabbed: kick off **`/evelan:implement`** per ticket, **`/clear`ing context between each one**. Each ticket is self-contained, so the last one's context is disposable.
   - **No** → **`/evelan:implement`** right here, in the same context window.

   Either way, **`/evelan:implement`** builds each issue by driving **`/evelan:tdd`** internally (one red-green slice at a time), then closes out by running **`/evelan:code-review`**, a review of the diff on Standards, Spec and, when Codex is installed, a Codex second opinion, before committing. Reach for **`/evelan:tdd`** on its own when you just want to build a concrete behaviour test-first without a full spec, and **`/evelan:code-review`** on its own whenever you want to review a branch or PR against a fixed point.

### Context hygiene

Keep steps 1 to 3 in **one unbroken context window** (don't compact or clear until after `/evelan:to-tasks`) so the grilling, spec, and tickets all build on the same thinking. Each `/evelan:implement` then starts fresh, working from the ticket.

The limit on this is the **[smart zone](https://www.aihero.dev/ai-coding-dictionary/smart-zone)**: the window (~150k tokens on state-of-the-art models) within which the model still reasons sharply. If a session approaches it before `/evelan:to-tasks`, don't push on degraded; `/compact` at the nearest phase boundary and carry on (see Phase boundaries).

## On-ramps

A starting situation that generates work, then merges onto the main flow.

- **Something's broken** → **`/evelan:diagnose-bug`**. For the hard ones: the bug that resists a first glance, the intermittent flake, the regression that crept in between two known-good states. It refuses to theorise until it has a **tight feedback loop** (one command that already goes red on *this* bug), then fixes with a regression test. Its post-mortem hands off to **`/evelan:improve-architecture`** when the real finding is that there's no good seam to lock the bug down.

- **A huge, foggy effort: a greenfield project or a huge feature build, too big for one session** → **`/evelan:wayfinder`**, the most cognitively demanding flow here. When the way from here to the destination isn't visible yet, it charts a **shared map** of **decision tickets** on the issue tracker and resolves them one at a time, producing **decisions, not deliverables**, until the fog is pushed back and the way is clear. Where **`/evelan:question-me`** sharpens an idea you can hold in one session, wayfinder is for the idea you can't, and it's slower and denser, so save it for exactly that, never a well-scoped feature.

  When the map clears, **it hands off, it doesn't build**: merge onto the main flow at **`/evelan:to-spec`**, which collapses the map's linked decisions into a buildable plan, then `/evelan:to-tasks` and `/evelan:implement` as usual. Looping the map straight into `/evelan:implement` skips that collapse and throws the linked detail away, so go straight to `/evelan:implement` only when the effort turned out genuinely small.

## Codebase health

Not feature work, just upkeep.

- **`/evelan:improve-architecture`** runs whenever you have a spare moment to keep the codebase good for agents to operate in. It surfaces **deepening opportunities**; picking one _generates an idea_ you can take into the main flow at `/evelan:question-me`. It's the survey that finds the candidates; **`/evelan:codebase-design`** (below) is the bench you design the chosen one on.

## Vocabulary underneath

Two model-invoked references that run *beneath* the other skills, each the single source of truth for its vocabulary. Reach for them directly when the **words**, not the process, are the problem; or let the skills above pull them in.

- **`/evelan:domain-model`**: sharpen the project's *domain* language: challenge a fuzzy term, resolve an overloaded word ("account" doing three jobs), record a hard-to-reverse decision as an ADR. It's the active discipline `/evelan:question-me` drives to keep `CONTEXT.md` a clean glossary.
- **`/evelan:codebase-design`** is the deep-module vocabulary (module, interface, depth, seam, adapter, leverage, locality) for designing a module's *shape*: a lot of behaviour behind a small interface at a clean seam. `/evelan:tdd` and `/evelan:improve-architecture` both speak it.

## Phase boundaries

A **phase** is a chunk of work inside a session: the grilling, the implementation, the QA. At the **boundary** between two of them you have five options, and picking between them is the fuzziest decision in this whole map:

- **Continue**: stay put. Costs nothing, loses nothing.
- **`/clear`**: empty the window, when nothing here matters to what's next.
- **`/evelan:handoff`** writes a portable markdown file. Narrow: only for a **new harness**, a **new directory**, a **colleague**, or forking a side task **mid-phase**. What it buys is portability.
- **Subagent**: send a tightly-scoped task to its own window and get a report back.
- **`/compact`** compresses this context and seeds a fresh session with it. The **default**, at the bottom of the tree rather than the first reach.

Read [PHASE-BOUNDARIES.md](PHASE-BOUNDARIES.md) for the ordered tree: the five questions, the reasoning behind each branch, and why the primary-source cost makes **Continue** the one to rule out first. Make the decision **at** a boundary; mid-phase, continue or split the rest into subagents.

## Standalone

Off the main flow entirely.

- **`/evelan:question-me`** on its own, off the main flow: the interview itself (rounds, the frontier, facts are the agent's job and decisions are yours) for sharpening a plan, a design or a piece of writing. `/evelan:wayfinder` and `/evelan:improve-architecture` run it internally.
- **`/evelan:wait-what`** is the corrective for a message that didn't land. Use it mid-conversation, inside any other skill, and the agent re-pitches what it just said with the context you were missing, in plain English, using the `CONTEXT.md` vocabulary. It works after the fact; `/evelan:question-me` is the upfront cure, because a shared language agreed early is what stops the jargon arriving at all.

## Unattended builds: plan, then Autopilot

The flows above are interactive: you decide, the agent asks. `/evelan:autopilot` is the
unattended counterpart: it executes a plan end to end without you in the loop. The seam is the
plan: **write it with `/evelan:autopilot-plan`** (after `/evelan:question-me` when shape
questions are open), then run `/evelan:autopilot <session directory>` in a fresh session. The
run never asks; whatever the plan leaves open, it decides conservatively and records.

## Precondition

**`/evelan:setup-workflow-skills`**: run before your first engineering flow to configure the issue tracker and doc layout the other skills assume. Custom issue trackers also work.
