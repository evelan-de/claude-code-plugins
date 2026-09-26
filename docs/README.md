# Documentation

## Guides

| Document | For | Covers |
| --- | --- | --- |
| [Autopilot for developers](autopilot-developer-guide.md) | every developer | planning a ticket, handing it to the queue, what a run does, PR labels, reviewing the result, blocked runs |
| [Mission control](../skills/autopilot/references/mission-control.md) | whoever runs the queue on the office Mini | queue files, commands, nightly schedule, Slack, Jira credentials, logs |
| [Plan template](../skills/autopilot-plan/references/plan-template.md) | plan writers | the `PLAN.md` format, including the `Model:` and `Effort:` lines |
| [Project setup](../skills/autopilot/references/init.md) | once per project | what `/autopilot init` installs |
| [Browser checks](../skills/autopilot/references/browser.md) | projects with a UI | how a run checks the app with `agent-browser`, login state files |

The skills and helper scripts are listed in the [README](../README.md#all-skills).

## Change notes and decisions

Dated notes on what changed and why, newest first:

- [2026-09-26 Autopilot runs review](2026-09-26-autopilot-runs-review.md)
- [2026-09-26 Autopilot 3.x compared with 1.x](2026-09-26-autopilot-compared-with-1x.md)
- [2026-09-21 Autopilot 3.0](2026-09-21-autopilot-v3.md)
- [2026-09-20 Autopilot 2.0](2026-09-20-autopilot-v2.md)
- [2026-09-19 Token efficiency review](2026-09-19-token-efficiency-review.md)

Older plans and designs: [`plans/`](plans/) and [`specs/`](specs/). Autopilot sessions of
this repo: [`autopilot/INDEX.md`](autopilot/INDEX.md).
