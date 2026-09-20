---
name: diagnose-bug
description: Diagnosis loop for hard bugs and performance regressions. Use when the user says "diagnose"/"debug this", or reports something broken/throwing/failing/slow. Triggers on "diagnose", "debug this", "Fehler eingrenzen", "warum bricht das", "das ist langsam geworden".
---

# Diagnosing Bugs

A discipline for hard bugs. Skip phases only when explicitly justified.

## Redact

This skill has you show commands, outputs and captured artifacts. **Redact every secret first**: write `<REDACTED>` in its place. Build loops against env vars so the credential stays in the environment rather than in what you show. Captured artifacts carry auth headers: quote only the lines that carry the signal.

If the redacted output is not enough to diagnose the bug, say so and ask the user.

## Phase 1: Build a feedback loop

Get a **tight** pass/fail signal for the bug: one command that goes red on _this_ bug. Bisection, hypothesis-testing and instrumentation all consume it. Spend disproportionate effort here.

### Ways to construct one, in roughly this order

1. **Failing test** at whatever seam reaches the bug: unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser script** (Playwright / Puppeteer) that drives the UI and asserts on DOM/console/network.
5. **Replay a captured trace.** Save a real network request / payload / event log to disk; replay it through the code path in isolation.
6. **Throwaway harness.** Spin up a minimal subset of the system (one service, mocked deps) that exercises the bug code path with a single function call.
7. **Property / fuzz loop.** If the bug is "sometimes wrong output", run 1000 random inputs and look for the failure mode.
8. **Bisection harness.** If the bug appeared between two known states (commit, dataset, version), automate "boot at state X, check, repeat" so you can `git bisect run` it.
9. **Differential loop.** Run the same input through old-version vs new-version (or two configs) and diff outputs.
10. **HITL bash script.** Last resort. If a human must click, drive _them_ with `scripts/hitl-loop.template.sh` so the loop is still structured. Captured output feeds back to you.

### Tighten the loop

Once you have _a_ loop, tighten it:

- Faster: cache setup, skip unrelated init, narrow the test scope.
- Sharper: assert on the specific symptom, not "didn't crash".
- Deterministic: pin time, seed RNG, isolate filesystem, freeze network.

### Non-deterministic bugs

Aim for a **higher reproduction rate**, not a clean repro. Loop the trigger 100 times, parallelise, add stress, narrow timing windows, inject sleeps. Keep raising the rate until the bug is debuggable.

### When you cannot build a loop

Stop and say so. List what you tried. Ask the user for: (a) access to whatever environment reproduces it, (b) a redacted captured artifact (HAR file, log dump, core dump, screen recording with timestamps), or (c) permission to add temporary production instrumentation. Do **not** hypothesise without a loop.

### Completion criterion: a tight loop that goes red

Phase 1 is done when you can name **one command** (a script path, a test invocation, a curl) that you have **already run at least once** (show the invocation and its output, redacted), and that is:

- [ ] **Red-capable**: it drives the actual bug code path and asserts the **user's exact symptom**, so it goes red on this bug and green once fixed.
- [ ] **Deterministic**: same verdict every run (flaky bugs: a pinned, high reproduction rate).
- [ ] **Fast**: seconds, not minutes.
- [ ] **Agent-runnable**: you can run it unattended; a human in the loop only via `scripts/hitl-loop.template.sh`.

No red-capable command, no Phase 2. Do not read code to build a theory before this command exists.

## Phase 2: Reproduce + minimise

Run the loop. Watch it go red.

Confirm:

- [ ] The loop produces the failure mode the **user** described, not a different nearby failure.
- [ ] The failure is reproducible across multiple runs (or at a high enough rate for non-deterministic bugs).
- [ ] You have captured the exact symptom (error message, wrong output, slow timing) so later phases can verify the fix addresses it.

### Minimise

Shrink the repro to the **smallest scenario that still goes red**. Cut inputs, callers, config, data and steps **one at a time**, re-running the loop after each cut. Done when removing any remaining element makes the loop go green. The minimal repro becomes the regression test in Phase 5.

Do not proceed until you have reproduced **and** minimised.

## Phase 3: Hypothesise

Generate **3-5 ranked hypotheses** before testing any of them. Each must be **falsifiable**:

> "If <X> is the cause, then <changing Y> will make the bug disappear / <changing Z> will make it worse."

If you cannot state the prediction, discard or sharpen the hypothesis.

**Show the ranked list to the user before testing.** Don't block on it; proceed with your ranking if the user is away.

## Phase 4: Instrument

Each probe maps to one prediction from Phase 3. **Change one variable at a time.**

Tool preference:

1. **Debugger / REPL inspection** if the env supports it.
2. **Targeted logs** at the boundaries that distinguish hypotheses.
3. Never "log everything and grep".

**Tag every debug log** with a unique prefix, e.g. `[DEBUG-a4f2]`, so cleanup is a single grep.

**Perf branch.** For performance regressions: establish a baseline measurement (timing harness, `performance.now()`, profiler, query plan), then bisect. Measure first, fix second.

## Phase 5: Fix + regression test

Write the regression test **before the fix**, but only at a **correct seam**: one where the test exercises the real bug pattern as it occurs at the call site. A seam that is too shallow (single-caller test when the bug needs multiple callers) gives false confidence.

**If no correct seam exists, that itself is the finding.** Note it and flag it for cleanup.

If a correct seam exists:

1. Turn the minimised repro into a failing test at that seam.
2. Watch it fail.
3. Apply the fix.
4. Watch it pass.
5. Re-run the Phase 1 loop against the original (un-minimised) scenario.

## Phase 6: Cleanup

Required before declaring done:

- [ ] Original repro no longer reproduces (re-run the Phase 1 loop)
- [ ] Regression test passes (or absence of seam is documented)
- [ ] All `[DEBUG-...]` instrumentation removed (`grep` the prefix)
- [ ] Throwaway harnesses deleted (or moved to a clearly marked debug location)
- [ ] The confirmed hypothesis is stated in the commit / PR message
