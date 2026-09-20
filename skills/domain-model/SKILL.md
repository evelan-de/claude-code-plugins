---
name: domain-model
description: Build and sharpen a project's domain model. Use when discussing codebase terminology, writing or editing a CONTEXT.md, or recording or editing an ADR. Triggers on "domain model", "glossary", "ADR", "Begriff festlegen", "Entscheidung als ADR festhalten".
---

# Domain Modeling

Build and sharpen the project's domain model as you design: challenge terms, invent edge-case scenarios, and write the glossary and decisions down the moment they crystallise. Reading `CONTEXT.md` for vocabulary is not this skill; this skill is for changing the model.

## Files

- `CONTEXT.md` at the repo root (or one per context, listed in a root `CONTEXT-MAP.md`): the glossary. Format and layout rules in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).
- `docs/adr/NNNN-slug.md`: decision records. Format, numbering and the criteria for offering one in [ADR-FORMAT.md](./ADR-FORMAT.md).

Create files lazily: `CONTEXT.md` when the first term is resolved, `docs/adr/` when the first ADR is needed.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y. Which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account': do you mean the Customer or the User?"

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios that probe edge cases and force precise boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. Surface contradictions: "Your code cancels entire Orders, but you just said partial cancellation is possible. Which is right?"

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there; don't batch. `CONTEXT.md` is a glossary and nothing else: no implementation details, no spec, no scratch pad.

### Offer ADRs sparingly

Offer an ADR only when the decision meets all three criteria in [ADR-FORMAT.md](./ADR-FORMAT.md) (hard to reverse, surprising without context, a real trade-off).
