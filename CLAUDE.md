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
│   ├── <tool>                # Python 3 stdlib, no file extension
│   ├── <tool>_test.py        # unittest suite
│   ├── <tool>.test.sh        # wrapper, run: bash bin/<tool>.test.sh
│   └── testlib.py            # shared by the test suites (loading a helper, starting one on Windows)
├── docs/                     # Documentation and diagrams
└── README.md
```

Anything in `bin/` is on PATH when the plugin is installed, so skills call the
helper by bare name (`codex-cli`, `jira`) instead of hardcoding paths.
Helpers are Python 3, standard library only (no pip), and run on Python 3.9, the system
Python of macOS. Each starts with the same four launcher lines (copy them from any helper;
`bin/plugin-lint` checks them): `python3` where it exists, `python` on a Windows without it.
Each has a `<tool>_test.py` unittest file and a `<tool>.test.sh` wrapper that runs it. No
shell helpers, no other dependencies - they run on teammates' machines, not just yours, on
macOS and on Windows under Git Bash. Only `mission-control` is macOS-only (it refuses to run
elsewhere). `.github/workflows/gate.yml` runs lint and every test suite on macOS, Ubuntu and
Windows for every push.

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

## Before every release

Run `bin/plugin-lint` (frontmatter, references, cross-references, agents list, em dashes,
README coverage, removed concepts, helper launcher lines) and every `bin/*.test.sh` and
`skills/autopilot/hooks/*.test.sh`; all must pass here and in the GitHub Actions run of the
branch (macOS, Ubuntu, Windows). Then `claude plugin validate .` and the version bump in
`.claude-plugin/plugin.json`.

A change to a hook in `skills/autopilot/hooks/` raises the number in its
`# autopilot-hook-version:` line; only then do projects with an older copy get the update.
