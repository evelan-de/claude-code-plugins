# Evelan Claude Code Plugins

The Evelan team's skills, agents and helper scripts for Claude Code: plan a ticket with
Claude and let the office Mini implement it overnight, review code, work with Codex, and a
set of everyday helpers.

**Contents:** [Install](#install) · [Documentation](#documentation) ·
[Autopilot](#autopilot-tickets-implemented-overnight) · [All skills](#all-skills) ·
[Helper scripts](#helper-scripts) · [Working on this plugin](#working-on-this-plugin)

## Install

In Claude Code:

```
/plugin marketplace add evelan-de/claude-code-plugins
/plugin install evelan@evelan-plugins
```

Updates arrive automatically. To refresh by hand: `/plugin marketplace update evelan-plugins`.

To have Claude offer the plugin to everyone who opens a project, add this to the project's
`.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "evelan-plugins": {
      "source": { "source": "github", "repo": "evelan-de/claude-code-plugins" }
    }
  },
  "enabledPlugins": { "evelan@evelan-plugins": true }
}
```

## Documentation

| Document | For | Covers |
| --- | --- | --- |
| [Autopilot for developers](docs/autopilot-developer-guide.md) | every developer | planning a ticket, handing it to the queue, what a run does, PR labels, reviewing the result, blocked runs |
| [Mission control](skills/autopilot/references/mission-control.md) | whoever runs the queue on the office Mini | queue files, commands, nightly schedule, Slack, Jira credentials, logs |
| [Plan template](skills/autopilot-plan/references/plan-template.md) | plan writers | the `PLAN.md` format, including the `Model:` and `Effort:` lines |
| [Project setup](skills/autopilot/references/init.md) | once per project | what `/autopilot init` installs |
| [Browser checks](skills/autopilot/references/browser.md) | projects with a UI | how a run checks the app with `agent-browser`, login state files |

All documents, including the dated notes on changes and decisions: [`docs/`](docs/README.md).
Each skill's full instructions are in `skills/<name>/SKILL.md`.

## Autopilot: tickets implemented overnight

You write the plan together with Claude in your own session; the office Mini implements it
unattended and hands you a reviewed pull request.

1. **Once per project:** `/autopilot init` sets up the test command, the hooks and the PR
   labels. Commit the result.
2. **Plan:** `/autopilot-plan WEB-1234` (a ticket key, a spec file or a topic). Claude reads
   the code and asks you twice: the shape of the work, then the package list with the run
   model and effort. It writes `PLAN.md` on a new branch.
3. **Hand over:** Claude pushes the branch and opens a draft PR with the label
   `autopilot-ready`.
4. **Run:** the office Mini picks it up at 22:00 and says so in a PR comment. It implements
   the plan test-first, reviews the whole branch, checks the result in a browser and marks
   the PR ready for review. You get a PR comment, a Slack message and a comment on the Jira
   ticket.
5. **Review and merge** like any other PR. The run never merges.

**Model and effort** are two lines in the plan. `Model: sonnet` is the default and always
runs at effort `xhigh` or `max`; `Model: opus` runs at any effort, `medium` by default. Say
them while planning ("opus, high") or change them later with
`/autopilot <session dir> opus high` (either word alone works too).

| Skill or agent | What it does |
| --- | --- |
| `/evelan:autopilot-plan` | writes the plan with you (best on Fable or Opus) |
| `/evelan:autopilot` | executes a plan unattended when the queue starts it; in your own session it only queues the plan; `/autopilot init` sets up a project |
| `/evelan:mission-control` | queue status, add, retry, stop, log, start, pause; on this machine or on the office Mini over SSH |
| `evelan:autopilot-reviewer`, `evelan:autopilot-plan-reviewer` | fresh-context reviewers the two skills call |

## All skills

Every skill also starts from plain phrases in German and English, listed in its `SKILL.md`.

### Plan and build (interactive)

| Skill | What it does |
| --- | --- |
| `/evelan:setup-workflow-skills` | once per repo: where tickets live (Jira, GitHub Issues or local files) and where domain docs go |
| `/evelan:question-me` | asks you until an idea or plan is sharp; records terms and decisions |
| `/evelan:to-spec` | turns the conversation into a spec on the tracker |
| `/evelan:to-tasks` | splits a spec into tickets with their dependencies |
| `/evelan:implement` | implements a spec or ticket test-first and ends with a code review |
| `evelan:tdd` | the test-first rules the other skills follow |
| `evelan:diagnose-bug` | finds the cause of a hard bug and ends with a regression test |
| `evelan:domain-model`, `evelan:codebase-design` | domain terms and decision records; module and interface design |
| `/evelan:improve-architecture` | finds places where the code structure can get simpler |
| `/evelan:handoff` | writes a hand-off note for a fresh session |

Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, see
`skills/THIRD-PARTY-NOTICES.md`).

### Review and verify

| Skill | What it does |
| --- | --- |
| `evelan:code-review` | reviews a diff against the project's standards and the ticket, plus a Codex review when the Codex CLI is installed |
| `/evelan:codex-review` | a second opinion from Codex on your diff, passed on unchanged |
| `/evelan:e2e-demo` | proves a finished task in the real running system and produces a narrated video and a report |

### Codex

| Skill | What it does |
| --- | --- |
| `/evelan:codex-ask` | hands a self-contained task or question to the Codex CLI and reports its answer and changes |
| `/evelan:codex-imagegen` | generates images through the Codex CLI (gpt-image-2) |

### Everyday helpers

| Skill | What it does |
| --- | --- |
| `/evelan:update-dependencies` | updates npm packages, researches breaking changes of major updates, pins exact versions |
| `/evelan:preview` | switches to the `preview` branch, pulls, and offers to delete the branch you left |
| `/evelan:port-from-repo` | copies a component or feature from another repo, exactly or restyled |
| `/evelan:slim-claude-md` | shrinks a project's `CLAUDE.md` to a short core plus rules that load per path |

## Helper scripts

The scripts in `bin/` are on the PATH once the plugin is installed.

| Script | What it does |
| --- | --- |
| `mission-control` | the queue runner: starts, watches and restarts autopilot runs one after another |
| `jira` | ticket start, comment and view for the runner; `jira setup` once per queue machine |
| `autopilot-usage` | where the tokens of one session went, per agent |
| `autopilot-watchdog` | the progress check the runner uses to spot a stalled run |
| `codex-cli`, `codex-model` | finds the local Codex CLI; turns a model name into a valid Codex model id |
| `codex-snapshot`, `codex-image-copy` | shows what a Codex run changed; copies an image Codex generated |
| `git-default-branch` | prints a repository's default branch |
| `plugin-lint` | consistency checks for this plugin |

## Working on this plugin

Structure and rules: [`CLAUDE.md`](CLAUDE.md). To try a local checkout:
`claude --plugin-dir /path/to/claude-code-plugins`. Before a release: `sh bin/plugin-lint`,
every `bin/*.test.sh` and `skills/autopilot/hooks/*.test.sh`, `claude plugin validate .`,
and the version bump in `.claude-plugin/plugin.json`.
