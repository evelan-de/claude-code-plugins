---
name: update-dependencies
description: Use when updating, upgrading, or checking npm dependencies. Triggers on "update dependencies", "aktualisiere dependencies", "upgrade packages", "check outdated", "Pakete aktualisieren", "Abhängigkeiten aktualisieren", or any request to update node packages.
---

# Update npm Dependencies

Preview with npm-check-updates, research majors, apply with pinned versions,
gate, roll back what breaks. Always `npx npm-check-updates`; never install
`ncu` and never ask about installing it.

## 1. Dry-run

```bash
npx npm-check-updates
```

Show the full list to the user, split into minor/patch and major (first
version number changed). No `-u` before the user has seen this list. No
minor-or-major question: the user picks packages in step 3. "Minor only" in
the request drops the majors from the rest of the run.

## 2. Research majors

One `general-purpose` subagent per major bump, all launched in one message.
Each returns: package and versions, concrete breaking changes, migration
steps (rename X to Y, remove option Z), reference URLs, confidence (high with
an official migration guide, low with only release notes).

Ecosystem check per major, before reporting: `npm ls <package> --depth=3`
for dependents and plugins in this project; confirm they support the new
major (ESLint configs and plugins, `@typescript-eslint/*`, testing
libraries, build-tool loaders). A dependent that does not: mark the package
"blocked, ecosystem not ready", name the blocker, recommend the latest
minor of the current major instead.

## 3. Report and decision

Per major: current and target version, confidence, breaking changes,
migration steps, references, blocked status. Then ask (AskUserQuestion):
which packages to exclude, and apply now / create plan / abort.

Create plan: write `docs/plans/YYYY-MM-DD-dependency-migration.md` with an
overview table (package, current, target, breaking-change count,
confidence), one section per package (breaking changes, migration steps with
affected files, references). Tell the user the path and stop.

## 4. Apply

1. `npx npm-check-updates -u --removeRange --filter <pkg1>,<pkg2>`
2. Read `package.json`. Any remaining `^` or `~` range (packages ncu did not
   touch): `npm ls <package> --depth=0` for the installed version, pin to
   exactly that. Never guess a version. The final `package.json` has no `^`
   or `~`.
3. Ask before `rm -rf node_modules`; then `npm install`.
4. Migrate code per the research: find usages with Grep/Glob, edit them. Low
   confidence or unclear step: skip it and flag it for the user.
5. Gate: typecheck, lint, test, build (the project's commands).
6. Red: read the error, identify the major that caused it, pin that package
   to the latest minor/patch of its previous major
   (`npm view <package> versions --json` to find it), `npm install`, gate
   again. Report each rollback with its reason.

## 5. Summary

Updated packages with before/after versions, rollbacks and why, files
changed for migration, gate results, skipped migration steps for the user
to handle.

## Constraints

- Dry-run first; the user sees the list before any `-u`.
- `--removeRange` on every update run; no `^`/`~` left in `package.json`.
- Majors are researched (parallel subagents) and ecosystem-checked before
  they are applied.
- Gate after applying; rollback on red; never leave the project broken.
- Ask before deleting `node_modules`.
