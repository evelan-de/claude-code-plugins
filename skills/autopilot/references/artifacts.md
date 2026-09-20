# Artifacts - `docs/autopilot/` (committed, part of the PR)

```
docs/autopilot/
  INDEX.md                          # newest-first, one line per session
  sessions/YYYY-MM-DD-<slug>/
    PLAN.md          # from /autopilot-plan: goal, goal artifact, decisions, packages + status
    DECISIONS.md     # assumptions the run made, with reasons
    HANDOFF.md       # transient; deleted when consumed
    REPORT.md        # first line `Status: done` or `Status: blocked - <reason>`; then shipped work,
                     # verification, review findings, open items (the queue runner reads the first line)
    MANUAL_TESTING.md  # only for steps impossible in this environment
```

`INDEX.md` marker (prepend below it, never sort or rewrite):
```
<!-- NEW ENTRIES GO IMMEDIATELY BELOW THIS LINE -->
- **YYYY-MM-DD HH:MM** - <title> - <one line> - [PR](<url>) [→](./sessions/<slug>/REPORT.md)
```

Runtime files that are never committed: `.claude/.autopilot-active` (sentinel),
`.claude/autopilot-gate.log`, `.claude/.autopilot-gate-blocks`.
