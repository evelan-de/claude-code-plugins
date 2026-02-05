# Evelan Claude Code Plugins

This is a Claude Code plugin repository for sharing team skills and commands.

## Project Structure

```
claude-code-plugins/
├── .claude-plugin/
│   ├── plugin.json           # Plugin metadata (name, version, author)
│   └── marketplace.json      # Marketplace catalog for plugin discovery
├── skills/                   # Model-invoked skills (auto-triggered by context)
│   └── <skill-name>/
│       └── SKILL.md
├── commands/                 # User-invoked slash commands (optional)
│   └── <command-name>.md
├── docs/                     # Documentation and diagrams
└── README.md
```

## Plugin Configuration

`.claude-plugin/plugin.json` must exist with:
```json
{
  "name": "evelan",
  "description": "Evelan team skills and commands for Claude Code",
  "version": "1.0.0",
  "author": { "name": "Evelan" },
  "skills": "./skills/"
}
```

## Adding Skills

Each skill lives in `skills/<skill-name>/SKILL.md` with YAML frontmatter:
```yaml
---
name: skill-name
description: Use when [triggering conditions]. Triggers on [phrases in English and German].
---
```

## Adding Commands

Each command lives in `commands/<command-name>.md` with YAML frontmatter:
```yaml
---
description: "Short description for /help"
allowed-tools: [Bash, Read, Glob, Grep]
---
```

## Installation

1. Add marketplace: `/plugin marketplace add evelan-de/claude-code-plugins`
2. Install plugin: `/plugin install evelan@evelan-plugins`

See `README.md` for full installation instructions including auto-prompt setup for team projects.
