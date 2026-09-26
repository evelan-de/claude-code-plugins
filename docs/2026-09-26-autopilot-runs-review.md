# Autopilot runs review and run model choice - 2026-09-26

Review of every queue run since plugin 3.0.0 (2026-09-21), from the item logs on the office
Mini (`~/.claude/mission-control/logs/`) and the PRs on GitHub, plus the model change that
came out of it (plugin 3.1.0).

## Runs

Costs are list prices from the `total_cost_usd` of each attempt's result line; wall time is
from the queue start to the done line.

| Item | PR | Attempts | Cost | Wall time | Outcome |
| --- | --- | --- | --- | --- | --- |
| WEB-1108 Magicline chat widget | fit-inn-trier-web #4 | 1 | $8.26 | 39 min | done, CI green; reviewer found and fixed one real gap, Codex clean; merged 23.09. |
| PAUL-2802 DATEV manual changes | paul #315 | 2 | $43.92 (29.70 + 14.22) | 2 h 30 min | done; the review bot found one real bug (filter options ignored), fixed and answered; merged 23.09. |
| default-org-redirect | jexity-chatbot #277 | 1 | $1.67 | 4 min | **wrong plan**: resolved to the finished `2026-09-23-two-factor-auth` session, built nothing, reported done. |
| org-leads | jexity-chatbot #276 | 1 | $1.37 | 3 min | **wrong plan**, same as #277. Both were implemented by hand the next morning and merged 24.09. |
| visitor-widget-language | jexity-chatbot #262 | 3 | $64.62 (50.34 + 12.73 + 1.55) | 2 h | done; attempt 1 ran 484 turns without a context-budget hook; attempt 3 merged `preview` into the branch to clear a merge blocker; merged 25.09. |

Before 3.0.0 on the Mini: WEB-1101 ($12.06, blocked: E2E needed a login, the reason for the
`agent-browser` state file) and website-a-wave (4 attempts, $50.22, `handoff-limit` at the
old limit of 3 restarts; local-recording #386 is still open).

Advisor (Fable) share of the cost: WEB-1108 9%, PAUL-2802 17%, visitor-widget-language 29%,
website-a-wave 25%.

## What works

- The queue chain: start, hand-off, restart, report, label, PR comment, Slack. Hand-offs
  restarted without anyone (PAUL-2802 once, visitor-widget-language twice).
- Jira bookkeeping by the runner: In Progress at the start, a result comment read back at
  the end, for every ticket item.
- Reviews find real defects: the adversarial reviewer (WEB-1108) and the review bot
  (PAUL-2802) each caught a bug that shipped fixed.
- Every PR of a correctly resolved item was merged within about a day.

## Findings

1. **Wrong session directory for PR items without a ticket key (critical).** `base_sha`
   takes the merge-base with the repo's default branch (`main`), but both PRs target
   `preview`. Everything merged into `preview` since then, including the finished
   two-factor-auth session, counts as "changed on this branch". `changed_session_dirs` sorts
   by name and the loop keeps the last one, so `2026-09-23-two-factor-auth` beat
   `2026-09-23-default-org-redirect` and `2026-09-23-org-leads`. The run found a
   `Status: done` report, did nothing, and the runner marked the PR ready, labelled it
   `autopilot-done` and posted the old report. Fix proposal: resolve the base from the PR's
   `baseRefName`, prefer the session directory whose `PLAN.md` `Branch:` equals the PR head
   branch, and refuse `done` from a `REPORT.md` that the item did not write. Not fixed yet.
2. **jexity-chatbot has no context-budget hook.** The runner warned ("no context-budget hook
   in this project"); attempt 1 of visitor-widget-language ran 484 turns and $50.34 of the
   $60 budget before it handed off on its own. Action: `/autopilot init` in jexity-chatbot
   to install the current hooks.
3. **Leftover worktree on the Mini.** `worktrees/paul-2026-09-23-paul-2802-...` could not be
   removed ("Directory not empty"). Action: look at what is left, then delete it.
4. **fit-inn-trier-web is not trusted on the Mini.** Claude ignored the 14 permissions of
   `.claude/settings.local.json`; the `.env.example` line was denied and became a manual
   step. Action: open `claude` once in that repo on the Mini and accept the trust dialog.
5. **website-a-wave is stuck since 21.09.** local-recording #386 is open without a label.
   Action: relabel `autopilot-ready` (the limit is 5 restarts now) or split the plan.
6. **The Mini's `opus` alias ran as Opus 5.** The reviewer showed `claude-opus-5[1m]` in the
   runs (Claude Code 2.1.278 on the Mini, 2.1.281 on the MacBook, where `opus` is Opus 5.5).
   Opus 5 lists at $5/$25 per million tokens, Opus 5.5 at $4/$20, Sonnet 5 at $2/$10.

## Model change (plugin 3.1.0)

Requested by Andreas: runs can use Opus, Sonnet runs always at extra-high effort, and the
plan decides the model.

- `PLAN.md` header `Model: sonnet | opus` next to `Effort:`. `/autopilot-plan` shows the
  run model with the package list (Sonnet by default) and writes both lines;
  `/autopilot <session dir> opus` rewrites the line of an existing plan before queueing.
- The runner passes `--model` from the header. Precedence as for effort: environment, then
  plan, then env file, then default (`sonnet`). Any other header value blocks the item
  before anything runs, with the line in the PR comment.
- A Sonnet run below `xhigh` runs at `xhigh`; `max` stays. Opus uses the header's effort
  (`medium` is Opus 5.5's own default and matches Opus 5 at `high` per the Claude Code docs).
- The advisor stays Fable; the pairing table accepts it for Sonnet 5 and Opus 5 and later.
- The fallback (`opus`) is left out when it is the run's own model family: an Opus run
  stays on Opus instead of silently falling back to a model the plan did not choose.
- Budget per attempt: 60 USD for Sonnet, 120 for Opus (2x Opus 5.5, 2.5x Opus 5 list
  price), unless `MISSION_CONTROL_BUDGET_USD` is set.

Effect on existing plans: a plan without `Model:` runs on Sonnet at `xhigh` from the next
queue run, also when it says `Effort: medium`.

Rollout: the Mini runs the plugin version installed there (3.0.2 today). The change takes
effect once the plugin is updated on the Mini, in the GUI session (SSH cannot unlock the
Keychain). The Mini's `~/.claude/settings.json` has no `fallbackModel`, so an Opus run
without `--fallback-model` really has no fallback. Not yet verified: a real launch with the
new flags (the CLI probe on the MacBook failed on an expired login) and a real queue run.

## Open decisions

1. Opus budget default of 120 USD per attempt, and whether Sonnet's 60 should rise now that
   Sonnet runs at `xhigh` (visitor-widget-language used $50.34 at `medium`).
2. `max` stays allowed for Sonnet; only `low`, `medium` and `high` are raised.
3. Fix finding 1 next (with a reproduction in the runner tests first).
