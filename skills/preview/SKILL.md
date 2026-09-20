---
name: preview
description: Switch to the preview branch and pull latest changes, with optional branch cleanup. Triggers on "Wechsel zu Preview", "switch to preview", "checkout preview", "geh auf preview", "öffne preview", "zurück zu preview", "back to preview", "pull preview", "/preview".
---

# Switch to Preview Branch

1. `git status --porcelain`. Dirty: show the files and ask: stash
   (`git stash push -m "auto-stash before switching to preview"`), continue,
   or abort. Clean: no question.
2. `git fetch --prune`.
3. Not on `preview` yet: `git branch -vv --list <current>`. Output containing
   `: gone]` means the branch was deleted on the remote; remember its name.
4. `git checkout preview` (skip when already on it).
5. `git pull`.
6. Remembered a gone branch: ask "Branch `<name>` was deleted on the remote.
   Delete local copy?" Yes: `git branch -d <name>` (never `-D`; a failed
   delete of unmerged work is reported, not forced). Never offer to delete a
   branch that still exists on the remote.
7. One line: `Switched to preview, pulled latest.` plus
   `Deleted local branch <name>.` when applicable.
