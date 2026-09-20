# `HANDOFF.md` format

Path: `docs/autopilot/sessions/<slug>/HANDOFF.md`. Transient: the session that consumes it
deletes it.

```
# HANDOFF - <package> - <ISO timestamp>
## Where we are
<package> is [~]: <one sentence>. Branch: <name>, HEAD: <sha>.
## Verified (with evidence)
- <what> - <command> → <result line>   (or: .claude/autopilot-gate.log last line)
## Open
- <concrete item>
## Next step
<the exact first action>
## Decisions made
- <decision> - <why>   (also in DECISIONS.md)
## Do not redo
- <verified things the next agent must not repeat>
```

Point to `PLAN.md`, commits and the gate log instead of copying. Redact secrets.
