---
name: question-me
description: Question the user relentlessly about a plan, decision, or idea until there is a shared understanding; in a repo it records the resolved terms and decisions in CONTEXT.md and ADRs as it goes. Use when the user wants to stress-test their thinking, says "question me", "frag mich aus", "stress-test this", "grill me", or wants an idea sharpened before a spec or plan.
---

# Question me

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

Format a round like so:

```
Q1 - <question title>
<question body, may be several paragraphs, may list choices>
Recommendation: <your recommended answer>

Q2 - <question title>
<question body>
Recommendation: <your recommended answer>
```

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it; don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report; ask the rest of the frontier now. The _decisions_ are the user's: put each to them and wait.

## Paper trail

When you are in a working directory (a repo), also call the Skill tool with "evelan:domain-model" and follow it alongside the interview: read `CONTEXT.md` and the ADRs first and use their terms, record a term the interview sharpens in `CONTEXT.md`, and record a hard-to-reverse decision as an ADR when the user settles it. Outside a repo (a plan, a design, a piece of writing with no codebase under it) the interview is stateless and saves nothing.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding.
