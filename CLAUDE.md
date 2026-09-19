# Evelan Claude Code Plugins

This is a Claude Code plugin repository for sharing team skills and commands.

## Project Structure

```
claude-code-plugins/
├── .claude-plugin/
│   ├── plugin.json           # Plugin metadata (name, version, author)
│   └── marketplace.json      # Marketplace catalog for plugin discovery
├── skills/                   # Skills (user- or model-invoked)
│   ├── <skill-name>/
│   │   └── SKILL.md
│   └── THIRD-PARTY-NOTICES.md  # attribution for vendored skills
├── agents/                   # Subagent definitions (frontmatter: model, tools, maxTurns)
│   └── <agent-name>.md
├── commands/                 # User-invoked slash commands (optional)
│   └── <command-name>.md
├── bin/                      # Helper executables on PATH for skills
│   ├── <tool>                # POSIX sh, no external deps
│   └── <tool>.test.sh        # bash test suite, run: bash bin/<tool>.test.sh
├── docs/                     # Documentation and diagrams
└── README.md
```

Anything in `bin/` is on PATH when the plugin is installed, so skills call the
helper by bare name (`codex-cli`, `codex-model`) instead of hardcoding paths.
Keep helpers POSIX `sh` and dependency-free, and ship a `.test.sh` next to
each one - they run on teammates' machines, not just yours.

## Plugin Configuration

`.claude-plugin/plugin.json` must exist with `name`, `description`, `version` (bump on every
release), `author`, `skills: "./skills/"` and an `agents` array listing every file under
`agents/` (an unlisted agent is not installed).

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
