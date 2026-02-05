---
name: update-dependencies
description: Use when updating, upgrading, or checking npm dependencies. Triggers on "update dependencies", "aktualisiere dependencies", "upgrade packages", "check outdated", "Pakete aktualisieren", "Abhängigkeiten aktualisieren", or any request to update node packages.
---

# Update npm Dependencies

Update project dependencies using `ncu` (npm-check-updates). Always preview first, then apply with pinned versions. For major updates, research breaking changes before applying.

## Workflow

```dot
digraph update_flow {
    rankdir=TB;
    node [fontname="Helvetica"];

    Start [shape=doublecircle];
    AskLevel [label="Ask: minor or major?" shape=diamond];
    DryRun [label="Dry-run: show changes" shape=box];
    HasMajor [label="Major updates\ndetected?" shape=diamond];
    SpawnAgents [label="Spawn parallel subagents\n(one per major dep)" shape=box];
    CollectResults [label="Collect & present\nbreaking changes report" shape=box];
    SelectPackages [label="User selects packages\n(opt out of specific ones)" shape=box];
    AskAction [label="Apply now, create plan,\nor abort?" shape=diamond];
    ApplyUpdates [label="Apply updates\n+ pin versions" shape=box];
    AutoMigrate [label="Auto-migrate code\nper migration guide" shape=box];
    WritePlan [label="Write migration plan\nto docs/plans/" shape=box];
    AskReinstall [label="Ask: reinstall\nnode_modules?" shape=diamond];
    Reinstall [label="rm node_modules\n+ npm install" shape=box];
    RunTests [label="Run build/tests\nif available" shape=box];
    Summary [label="Present summary" shape=box];
    Done [shape=doublecircle];
    Abort [shape=box];

    Start -> AskLevel;
    AskLevel -> DryRun [label="minor"];
    AskLevel -> DryRun [label="major"];
    DryRun -> HasMajor;
    HasMajor -> SpawnAgents [label="yes"];
    HasMajor -> AskAction [label="no (minor only)"];
    SpawnAgents -> CollectResults;
    CollectResults -> SelectPackages;
    SelectPackages -> AskAction;
    AskAction -> ApplyUpdates [label="apply now"];
    AskAction -> WritePlan [label="create plan"];
    AskAction -> Abort [label="abort"];
    WritePlan -> Done;
    ApplyUpdates -> AskReinstall;
    AskReinstall -> Reinstall [label="yes"];
    AskReinstall -> AutoMigrate [label="no"];
    Reinstall -> AutoMigrate;
    AutoMigrate -> RunTests;
    RunTests -> Summary;
    Summary -> Done;
}
```

## Phase 0: Prerequisites Check

Before running any commands, check if `ncu` is available:

```bash
which ncu
```

If `ncu` is not found, ask the user if they want to install it using AskUserQuestion with these options:

- **Install globally** — `npm install -g npm-check-updates`
- **Use npx** — skip installation, prefix all `ncu` commands with `npx` instead (e.g. `npx npm-check-updates --target minor`)
- **Abort** — cancel the update process

If the user chooses npx, replace all `ncu` calls in subsequent phases with `npx npm-check-updates`.

## Phase 1: Dry-Run

**Preview (dry-run):**
```bash
# Minor/Patch only
ncu --target minor

# All including major
ncu
```

Parse the output to identify which updates are major (first version number changed).

## Phase 2: Breaking Changes Research (Major Updates Only)

When major updates are detected, spawn **parallel Task subagents** (subagent_type: `general-purpose`) — one per dependency with a major version bump.

Each subagent receives this prompt:

```
Research the migration guide and breaking changes for upgrading {package} from {current_version} to {target_version}.

Search for:
1. Official migration guide or upgrade guide
2. Changelog entries for breaking changes
3. GitHub release notes

Return a structured summary:
- Package: {package} {current_version} → {target_version}
- Breaking changes: list of concrete breaking changes
- Migration steps: specific code changes needed (e.g. "rename X to Y", "remove config option Z", "replace API call A with B")
- References: URLs to official migration guide / changelog
- Confidence: "high" if official migration guide found, "low" if only changelog or release notes
```

**Launch all subagents in a single message** (parallel Task tool calls). Wait for all to complete, then collect results.

## Phase 3: Report & User Decision

Present a consolidated report to the user:

```
## Major Update Report

### {package} {current} → {target} (confidence: {high|low})
Breaking changes:
- {change 1}
- {change 2}
Migration steps:
- {step 1}
- {step 2}
References: {url}
```

Then ask the user with AskUserQuestion:

1. **Which packages to exclude** — let the user opt out of specific major updates
2. **What to do:**
   - **Apply now** — update packages and auto-migrate code in this session
   - **Create plan** — write a migration plan document for later execution, no code changes
   - **Abort** — cancel, no changes made

## Phase 4a: Apply Now

When the user chooses to apply immediately:

1. **Update package.json:**
   ```bash
   # Selected major packages only
   ncu -u --removeRange --filter {pkg1},{pkg2},...

   # Minor/patch (all)
   ncu --target minor -u --removeRange
   ```

2. **Reinstall** (ask user first):
   ```bash
   rm -rf node_modules && npm install
   ```

3. **Auto-migrate code** — for each package with migration steps:
   - Use Grep/Glob to find affected files (imports, API usages, config files)
   - Apply changes using Edit tool based on the migration steps from the research
   - After each package migration, run the project's build/test/lint command if available to verify no regressions

4. **Present summary:**
   - Which packages were updated
   - Which files were modified for migration
   - Build/test/lint results (pass/fail)
   - Any migration steps that were skipped (low confidence or too ambiguous) — flag these for the user to handle manually

## Phase 4b: Create Plan

When the user chooses to create a plan, write to `docs/plans/YYYY-MM-DD-dependency-migration.md`:

```markdown
# Dependency Migration Plan

Generated: {date}

## Overview

| Package | Current | Target | Breaking Changes | Confidence |
|---------|---------|--------|-----------------|------------|
| {pkg}   | {curr}  | {tgt}  | {count}         | {high/low} |

## {package} {current} → {target}

### Breaking Changes
- {change 1}
- {change 2}

### Migration Steps
1. {step description}
   - Affected files: `{glob pattern or file paths}`
2. {step description}
   - Affected files: `{glob pattern or file paths}`

### References
- {url to migration guide}
```

After writing the plan:
- Tell the user the file path
- Explain they can execute the plan in any future session by referencing the file

## Rules

- **Always dry-run first.** Never run with `-u` before showing the user what will change.
- **Always pin versions.** Use `--removeRange` on every update run. No `^` or `~` prefixes.
- **Ask before reinstall.** Deleting `node_modules` is optional — always ask the user.
- **Research before major updates.** Never apply a major update without researching breaking changes first.
- **Parallel subagents.** Always launch research agents in a single message with multiple Task tool calls for maximum speed.
- **Skip ambiguous migrations.** If a migration step has low confidence or is unclear, skip the auto-migration for that step and flag it for the user.
- **Run tests after migration.** If the project has a build or test command, run it after each package migration to catch issues early.
- **Run lint after migration.** If the project has a lint command, run it after each package migration to catch issues early.
- If the user specifies a level (minor/major), use it directly without asking again.
- If the user does not specify a level, ask which mode they want.
