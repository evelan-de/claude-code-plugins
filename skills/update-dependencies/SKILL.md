---
name: update-dependencies
description: Use when updating, upgrading, or checking npm dependencies. Triggers on "update dependencies", "aktualisiere dependencies", "upgrade packages", "check outdated", "Pakete aktualisieren", "Abhängigkeiten aktualisieren", or any request to update node packages.
---

# Update npm Dependencies

Update project dependencies using `ncu` (npm-check-updates). Always preview first, then apply with pinned versions.

## Workflow

```dot
digraph update_flow {
    "Start" [shape=doublecircle];
    "Ask: minor or major?" [shape=diamond];
    "Dry-run: show changes" [shape=box];
    "User confirms?" [shape=diamond];
    "Apply updates + pin versions" [shape=box];
    "Ask: reinstall node_modules?" [shape=diamond];
    "rm node_modules + npm install" [shape=box];
    "Done" [shape=doublecircle];
    "Abort" [shape=box];

    "Start" -> "Ask: minor or major?";
    "Ask: minor or major?" -> "Dry-run: show changes" [label="minor"];
    "Ask: minor or major?" -> "Dry-run: show changes" [label="major"];
    "Dry-run: show changes" -> "User confirms?";
    "User confirms?" -> "Apply updates + pin versions" [label="yes"];
    "User confirms?" -> "Abort" [label="no"];
    "Apply updates + pin versions" -> "Ask: reinstall node_modules?";
    "Ask: reinstall node_modules?" -> "rm node_modules + npm install" [label="yes"];
    "Ask: reinstall node_modules?" -> "Done" [label="no"];
    "rm node_modules + npm install" -> "Done";
}
```

## Commands

**Preview (dry-run):**
```bash
# Minor/Patch only
ncu --target minor

# All including major
ncu
```

**Apply updates with pinned versions:**
```bash
# Minor/Patch only, pinned versions
ncu --target minor -u --removeRange

# All including major, pinned versions
ncu -u --removeRange
```

**Reinstall (when requested):**
```bash
rm -rf node_modules && npm install
```

## Rules

- **Always dry-run first.** Never run with `-u` before showing the user what will change.
- **Always pin versions.** Use `--removeRange` on every update run. No `^` or `~` prefixes.
- **Ask before reinstall.** Deleting `node_modules` is optional - always ask the user.
- If the user specifies a level (minor/major), use it directly without asking again.
- If the user does not specify a level, ask which mode they want.
