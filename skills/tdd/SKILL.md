---
name: tdd
description: Test-driven development. Use when the user wants to build features or fix bugs test-first, mentions "red-green-refactor", or wants integration tests.
---

# Test-Driven Development

Tests verify behaviour through public interfaces, not implementation details. A test reads like a specification ("user can checkout with valid cart") and survives refactors.

## Seams

A **seam** is the public boundary you test at. Tests live at seams, never against internals.

**Test only at pre-agreed seams.** Before writing any test, write down the seams under test and confirm them with the user. No test at an unconfirmed seam.

When the shape of the interface is itself in question (depth, where the seam belongs, what it exposes), call the Skill tool with "evelan:codebase-design" for the vocabulary.

## Rules

- **Red before green.** Write the failing test first, watch it fail, then only enough code to pass it. No speculative features.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle. Never all tests first, then all implementation.
- **No tautological tests.** The expected value must come from an independent source (a known-good literal, a worked example, the spec), never recomputed the way the code computes it.
- **No implementation coupling.** No mocking of internal collaborators, no private methods, no verifying through a side channel (querying the database instead of the interface). Mock only at process boundaries (external APIs, time, randomness).
- **Refactoring is outside the loop.** It belongs to the review stage (`evelan:code-review`), not the red-green cycle.
