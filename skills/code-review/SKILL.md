---
name: code-review
description: "Evelan's code review. ALWAYS use this skill (never the built-in code-review) whenever the user asks for a code review in any wording: \"code review\", \"review this\", \"review the PR\", \"review the branch\", \"review my changes\", \"review since X\", German \"Code Review\", \"reviewe das\", \"mach ein Review\", \"schau dir den Diff an\". Reviews the changes since a fixed point along three axes: Standards, Spec, and Codex (cross-model, when the Codex CLI is installed)."
---

Review the diff between `HEAD` and a fixed point the user supplies, on three axes:

- **Standards**: does the code conform to this repo's documented coding standards?
- **Spec**: does the code implement the originating issue / spec?
- **Codex**: an independent cross-model review of the same diff, run whenever the Codex CLI is installed.

The two Claude axes run as **parallel sub-agents**; Codex runs in the background next to them; then this skill aggregates. Findings are never merged or reranked across axes.

If `docs/agents/issue-tracker.md` is missing, tell the user to run `/evelan:setup-workflow-skills`.

## Process

### 1. Pin the fixed point

Whatever the user said is the fixed point (a commit SHA, branch name, tag, `main`, `HEAD~5`). If they didn't specify one, ask.

Capture the diff command once: `git diff <fixed-point>...HEAD` (three-dot, against the merge-base). Note the commits via `git log <fixed-point>..HEAD --oneline`.

Confirm the fixed point resolves (`git rev-parse <fixed-point>`) and the diff is non-empty before spawning anything.

### 2. Identify the spec source

In this order:

1. Issue references in the commit messages (`#123`, `Closes #45`, `ABC-123`), fetched via `docs/agents/issue-tracker.md`.
2. A path the user passed as an argument.
3. A spec file under `docs/`, `specs/`, or `docs/issues/` matching the branch name or feature.
4. Ask the user. If there is none, the Spec sub-agent is skipped and the report says "no spec available".

### 3. Identify the standards sources

Anything in the repo that documents how code should be written (`CODING_STANDARDS.md`, `CONTRIBUTING.md`, `CLAUDE.md` rules).

On top of that, the Standards axis always carries the **smell baseline** below (Fowler, _Refactoring_, ch.3). A documented repo standard overrides the baseline. Each smell is a labelled judgement call ("possible Feature Envy"), never a hard violation. Skip anything tooling already enforces.

- **Mysterious Name**: a name that doesn't reveal what it does or holds. -> rename; if no honest name comes, the design is murky.
- **Duplicated Code**: the same logic shape in more than one hunk or file. -> extract the shared shape.
- **Feature Envy**: a method that reaches into another object's data more than its own. -> move it onto that data.
- **Data Clumps**: the same few fields or params keep travelling together. -> bundle them into one type.
- **Primitive Obsession**: a primitive standing in for a domain concept. -> give the concept its own small type.
- **Repeated Switches**: the same `switch`/`if`-cascade on the same type recurs. -> polymorphism, or one shared map.
- **Shotgun Surgery**: one logical change forces scattered edits across many files. -> gather what changes together.
- **Divergent Change**: one module is edited for several unrelated reasons. -> split so each changes for one reason.
- **Speculative Generality**: abstraction or hooks for needs the spec doesn't have. -> delete it.
- **Message Chains**: long `a.b().c().d()` navigation. -> hide the walk behind one method.
- **Middle Man**: a class or function that mostly delegates onward. -> cut it, call the target direct.
- **Refused Bequest**: a subclass that ignores most of what it inherits. -> composition instead.

### 4. Spawn the axes in parallel

**Standards sub-agent prompt**: the diff command and commit list; the standards-source files from step 3 **plus the smell baseline pasted in full**; the brief: "Report, per file/hunk, (a) every place the diff violates a documented standard, citing file and rule; (b) any baseline smell, named, with the hunk quoted. Documented-standard breaches can be hard violations; baseline smells are always judgement calls; a documented repo standard overrides the baseline. Skip anything tooling enforces. Under 400 words."

**Spec sub-agent prompt**: the diff command and commit list; the path or fetched contents of the spec; the brief: "Report: (a) requirements the spec asked for that are missing or partial; (b) behaviour in the diff that wasn't asked for; (c) requirements that look implemented but wrong. Quote the spec line for each finding. Under 400 words."

**Codex, third axis, automatic.** In the same step, run `codex-cli --version`. If it succeeds,
start `evelan:codex-review` on the same range (`--base <fixed-point>`, always, so all
three axes review the same diff; uncommitted edits are not part of this review) in the
background alongside the two sub-agents; it needs no extra prompt. If the binary is missing, skip it with one line in the report ("Codex: not installed,
skipped") and nothing else; a developer without Codex gets the two Claude axes. Codex
rate-limited or failing: same one line with the reason, no Claude fallback (the two axes
already are the Claude review). The user never has to ask for Codex; "ohne Codex" / "no
Codex" in the request switches it off.

### 5. Aggregate

Present the reports under `## Standards`, `## Spec` and `## Codex` headings, verbatim or lightly cleaned (Codex: findings untouched, tool-call noise stripped, log path named). Do not merge or rerank across axes.

End with one line: total findings per axis and the worst issue within each axis. No single winner across axes.
