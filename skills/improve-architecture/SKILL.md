---
name: improve-architecture
description: Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick.
disable-model-invocation: true
---

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities**: refactors that turn shallow modules into deep ones, for testability and AI-navigability.

Call the Skill tool with "evelan:codebase-design" for the vocabulary (**module**, **interface**, **depth**, **seam**, **adapter**, **leverage**, **locality**) and its principles. Use these terms exactly in every suggestion; never "component," "service," "API," or "boundary." `CONTEXT.md` names the domain; ADRs in `docs/adr/` record decisions not to re-litigate.

## Process

### 1. Explore

Scope before you scan. Deepening pays off where code changes, so weight recently changed areas:

- If the user named a direction (a module, a subsystem, a pain point), take it.
- Otherwise walk the commit history (`git log --oneline`) for hot spots, the files and areas that keep coming up, and start there. No clear hot spot: widen the net.

Spawn a sub-agent to walk the codebase and note friction:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow**, with an interface nearly as complex as the implementation?
- Where have pure functions been extracted for testability while the real bugs hide in how they're called (no **locality**)?
- Where do tightly coupled modules leak across their seams?
- Which parts are untested, or hard to test through their current interface?

Apply the **deletion test** to anything you suspect is shallow: would deleting it concentrate complexity, or just move it?

### 2. Present candidates as an HTML report

Write a self-contained HTML file to `<tmpdir>/architecture-review-<timestamp>.html` (`$TMPDIR`, falling back to `/tmp`, or `%TEMP%` on Windows). Open it (`open` on macOS, `xdg-open` on Linux, `start` on Windows) and tell the user the absolute path.

The report uses **Tailwind via CDN** for layout and **Mermaid via CDN** for graph-shaped diagrams (call graphs, dependencies, sequences); hand-built divs/SVG for editorial visuals (mass diagrams, cross-sections). Each candidate gets a **before/after visualisation**.

Per candidate, one card:

- **Files**: which files/modules are involved
- **Problem**: what friction the current architecture causes
- **Solution**: what would change
- **Benefits**: in terms of locality and leverage, and how tests improve
- **Before / After diagram**: side by side
- **Recommendation strength**: `Strong`, `Worth exploring`, `Speculative`, as a badge

End with a **Top recommendation** section: which candidate to tackle first and why.

Use `CONTEXT.md` vocabulary for the domain and the codebase-design vocabulary for the architecture: "the Order intake module," not "the FooBarHandler" or "the Order service."

**ADR conflicts**: surface a candidate that contradicts an ADR only when the friction warrants reopening it, and mark it in the card (_"contradicts ADR-0007, but worth reopening because..."_).

See [HTML-REPORT.md](HTML-REPORT.md) for the scaffold, diagram patterns and styling.

Do NOT propose interfaces yet. After the file is written, ask: "Which of these would you like to explore?"

### 3. Grilling loop

Once the user picks a candidate, call the Skill tool with "evelan:question-me" to walk the decision tree: constraints, dependencies, the shape of the deepened module, what sits behind the seam, what tests survive.

Call the Skill tool with "evelan:domain-model" to keep the domain model current as decisions crystallise:

- **Naming a deepened module after a concept not in `CONTEXT.md`?** Add the term.
- **Sharpening a fuzzy term?** Update `CONTEXT.md` right there.
- **User rejects the candidate with a load-bearing reason?** Offer an ADR: _"Want me to record this as an ADR so future architecture reviews don't re-suggest it?"_ Skip ephemeral reasons ("not worth it right now") and self-evident ones.
- **Want to explore alternative interfaces?** Use the design-it-twice pattern from "evelan:codebase-design".
