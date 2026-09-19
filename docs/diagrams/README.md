# Diagrams

Interactive HTML diagrams (archify) of the orchestrated autopilot flow. Open the `.html` in a
browser; the `.json` next to it is the source. Guided views (top bar) walk through each one.

| File | Type | Shows |
| --- | --- | --- |
| `orchestrated-run.html` | workflow | Overview: mission control, autopilot-lead per package, session folder and git as the only handoff channel |
| `mission-control-plan.html` | workflow | Phases 0-4: decision precondition, goal artifact, PLAN.md + DIGEST.md, two plan reviews, dispatch loop, advance rule, hand-off return, watchdog |
| `mission-control-finish.html` | workflow | Phases 5-6: FINALIZE dispatch, independent gate and verifier, fix cycles, push, PR, CI, review-bot triage, summary |
| `package-lifecycle.html` | lifecycle | Status of one work package in PLAN.md: `[ ]`, `[~]`, gate + review, `[x]`, hand-off detour, `[!]` gap, reported incomplete |
| `package-dispatch-1.html` | sequence | One PACKAGE dispatch, part 1: dispatch, read the session folder, red-green cycles through the gate filter, budget hook |
| `package-dispatch-2.html` | sequence | Part 2: reviewer with gate.log tree-hash check, commit, output block, coordinator verifies PLAN.md and git log |
| `hook-chain-1.html` | sequence | Gate-output filter (PreToolUse): rewrite, run with pipefail, log line, filtered result |
| `hook-chain-2.html` | sequence | Context budget (PostToolUse): read transcript usage, inject the hand-off instruction |

Regenerate: edit the `.json`, then `node <archify>/bin/archify.mjs deliver <type> <json> <html> --quality showcase`.
