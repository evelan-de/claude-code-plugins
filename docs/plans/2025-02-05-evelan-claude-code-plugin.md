# Plan: Create Evelan Claude Code Plugin

## Goal

Create a custom Claude Code plugin as a GitHub repo (`evelan/claude-code-plugins`) containing team-shared skills. Each team member installs it with `/install-plugin`. Updates are distributed automatically.

First skill in the plugin: `update-dependencies` (update npm dependencies using `ncu`).

**GitHub repo description:** `Shared Claude Code skills and commands for the Evelan team`

---

## Prerequisites

- GitHub repo `evelan/claude-code-plugins` created (public or private — private requires SSH access for all team members)
- Repo cloned locally into a working directory (e.g. `~/dev/evelan/claude-code-plugins`)

---

## Step 1: Create repo structure

In the cloned repo, create the following structure:

```
claude-code-plugins/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── update-dependencies/
│       └── SKILL.md
└── README.md
```

## Step 2: Create plugin.json

File: `.claude-plugin/plugin.json`

```json
{
  "name": "evelan-tools",
  "description": "Evelan team skills and commands for Claude Code",
  "version": "1.0.0",
  "author": {
    "name": "Evelan"
  },
  "skills": "./skills/"
}
```

## Step 3: Create update-dependencies skill

File: `skills/update-dependencies/SKILL.md`

```markdown
---
name: update-dependencies
description: Use when updating, upgrading, or checking npm dependencies. Triggers on "update dependencies", "aktualisiere dependencies", "upgrade packages", "check outdated", "Pakete aktualisieren", "Abhängigkeiten aktualisieren", or any request to update node packages.
---

# Update npm Dependencies

Update project dependencies using `ncu` (npm-check-updates). Always preview first, then apply with pinned versions.

## Workflow

1. If user did not specify level, ask: minor/patch only or major?
2. Run dry-run to show available updates
3. Ask user to confirm
4. Apply updates with pinned versions (--removeRange)
5. Ask if node_modules should be reinstalled

## Commands

**Preview (dry-run):**

Minor/Patch only:
ncu --target minor

All including major:
ncu

**Apply updates with pinned versions:**

Minor/Patch only, pinned versions:
ncu --target minor -u --removeRange

All including major, pinned versions:
ncu -u --removeRange

**Reinstall (when requested):**
rm -rf node_modules && npm install

## Rules

- **Always dry-run first.** Never run with `-u` before showing the user what will change.
- **Always pin versions.** Use `--removeRange` on every update run. No `^` or `~` prefixes.
- **Ask before reinstall.** Deleting `node_modules` is optional - always ask the user.
- If the user specifies a level (minor/major), use it directly without asking again.
- If the user does not specify a level, ask which mode they want.
```

## Step 4: Create README.md

File: `README.md`

```markdown
# Evelan Claude Code Plugins

Shared Claude Code skills and commands for the Evelan team.

## Installation

Run in Claude Code:

/install-plugin github:evelan/claude-code-plugins

## Skills

### update-dependencies
Updates npm dependencies using ncu (npm-check-updates).
Supports minor/patch and major update modes. Always pins exact versions.

Trigger phrases: "update dependencies", "aktualisiere dependencies", "upgrade packages", "Pakete aktualisieren"
```

## Step 5: Commit and push

```bash
git add .
git commit -m "Initial plugin with update-dependencies skill"
git push origin main
```

## Step 6: Remove local skill

Delete the local skill since it will now come from the plugin:

```bash
rm -rf ~/.claude/skills/update-dependencies
```

## Step 7: Install plugin

Run in Claude Code:

```
/install-plugin github:evelan/claude-code-plugins
```

## Step 8: Test

In any project, say one of:

- "Update dependencies"
- "Aktualisiere Dependencies"
- "Check outdated packages"

The skill should be loaded and the ncu workflow should start.

---

## Adding more skills

Add a new folder under `skills/`:

```
skills/
├── update-dependencies/
│   └── SKILL.md
└── new-skill/
    └── SKILL.md
```

Commit, push — all team members receive the update automatically.

## Adding slash commands (optional)

For explicit `/commands`, create a `commands/` folder:

```
commands/
└── command-name.md
```

Frontmatter format for commands:

```yaml
---
description: "Short description shown in /help"
allowed-tools: [Bash, Read, Glob, Grep]
---
```
