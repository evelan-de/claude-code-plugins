# `autopilot-queue` - run prepared sessions one after another

A shell script in the plugin's `bin/` (on PATH once the plugin is installed). It starts
`claude -p "/autopilot <item>"` for each queued item in its own worktree, watches the run,
restarts it when it handed off, labels the PR with the outcome and notifies you. The run
itself pushes, opens or updates the PR and works the review bot; the queue never opens PRs.
One machine-wide queue, one run at a time.

## Files - all under `~/.claude/autopilot-queue` (`AUTOPILOT_QUEUE_HOME`)

| File | Content |
|---|---|
| `queue.txt` | One item per line: `<repo path> <item>`. `#` starts a comment. Item = session directory (`docs/autopilot/sessions/...`), ticket key (`PAUL-2801`) or a `"quoted topic"`. Processed top to bottom; a processed line is removed. |
| `repos.txt` | One repo path per line. Every open PR there with the label `autopilot-ready` is processed after the list. |
| `done.txt` | Appended per item: `<ISO time> <repo> <item> <status> <pr url or ->`, then `restarts=N` when the run handed off and `no-plan` when no `PLAN.md` existed. Status: `done`, `blocked`, `handoff-limit`, `timeout`. |
| `env` | Optional, mode 600. Shell assignments, see below. |
| `logs/` | `<timestamp>-<item>.log` per item (queue lines plus the full claude output), `launchd.log` for the schedule. |
| `worktrees/` | `<repo basename>-<item>/`; removed after `done`, kept otherwise so the state survives. |

Settings in `env` (environment variables override them; defaults in brackets):
`SLACK_WEBHOOK_URL` (none), `AUTOPILOT_QUEUE_MODEL` (sonnet), `AUTOPILOT_QUEUE_EFFORT`
(medium), `AUTOPILOT_QUEUE_ADVISOR` (fable), `AUTOPILOT_QUEUE_BUDGET_USD` (60 per run),
`AUTOPILOT_QUEUE_MAX_RESTARTS` (3), `AUTOPILOT_QUEUE_TIMEOUT_MIN` (240 per item, restarts
included), `AUTOPILOT_QUEUE_WATCH_MIN` (20, the stall check interval).

## Commands

```
autopilot-queue doctor                    # login, gh, git, repos, labels, env mode; exit 1 on any failure
autopilot-queue add <repo> <item...>      # append a line (quotes an item with spaces)
autopilot-queue list                      # what run would process, no side effects
autopilot-queue run                       # process queue.txt, then the labelled PRs of repos.txt
autopilot-queue install-schedule 22:00    # LaunchAgent, daily at that time (macOS)
autopilot-queue uninstall-schedule
```

`doctor` creates the labels `autopilot-ready`, `autopilot-done` and `autopilot-blocked` in
every repo it finds in `queue.txt` and `repos.txt` when they are missing, and says so.

## Two ways in

1. **The list.** `/autopilot-plan` for the topic, then
   `autopilot-queue add ~/dev/projects/paul docs/autopilot/sessions/2026-09-20-PAUL-2801-export`.
   A ticket key or topic without a plan is allowed: the run writes its own plan with
   conservative decisions, and `done.txt` marks the item `no-plan`.
2. **A labelled PR.** A developer runs `/autopilot-plan`, pushes the branch, opens a draft PR
   and adds the label `autopilot-ready`. The repo must be in `repos.txt`. The queue takes the
   newest session directory on that branch that has a `PLAN.md` as the item; without one it
   uses the ticket key from the branch name (else the branch name) and marks `no-plan`.

## What `run` does per item

1. Resolves the repo and, for a PR, its branch (`gh pr view`, fetch).
2. Creates a worktree under `worktrees/`: from the PR branch, or detached from the repo's
   default branch (`git-default-branch`) for list items. An existing worktree for the same
   item is reused (continuation). Your own checkout is never touched.
3. Starts the run in the background, output to the item log:
   `claude -p "/autopilot <item>" --model <model> --effort <effort> --advisor <advisor>
   --fallback-model opus --permission-mode auto --max-budget-usd <budget> --output-format json`.
   Every `WATCH_MIN` minutes `autopilot-watchdog` checks for a new commit or plan change;
   four stalls in a row kill the run (`stalled` in the log). The wall-clock timeout kills it
   too (`timeout`).
4. After the exit it looks at the item's session directory: `HANDOFF.md` present → the same
   item is started again (up to `MAX_RESTARTS`, then `handoff-limit`); `REPORT.md` present →
   `done`; neither → `blocked`.
5. Finds the PR the run pushed (`gh pr list --head <branch>`). `done`: draft → ready, label
   `autopilot-ready` swapped for `autopilot-done`, comment "Autopilot report" with the first
   60 lines of `REPORT.md`. Otherwise: label swapped for `autopilot-blocked`, comment with the
   reason and the log path; add `autopilot-ready` again to retry after you fixed the cause.
6. Appends to `done.txt`, removes the line from `queue.txt`, notifies (macOS notification;
   Slack when `SLACK_WEBHOOK_URL` is set), removes the worktree after `done`.

Progress on stdout, one line per step: `[autopilot-queue] <repo> <item>: <phase>`.
A lock (`run.lock`) refuses a second `run` while one is active; a lock left by a dead
process is taken over.

## Login and the schedule

Claude Code keeps its login in the macOS Keychain. A shell over SSH, or a launchd job
outside your GUI session, cannot read it: `claude -p` says "Not logged in" although the Mac
is logged in. So start `run` from a Terminal in the Mac's own session, or install the
schedule: `install-schedule HH:MM` writes
`~/Library/LaunchAgents/de.evelan.autopilot-queue.plist`, loaded with
`launchctl bootstrap gui/<uid>`, which runs inside the GUI session. Output goes to
`logs/launchd.log`. For SSH-triggered starts, export `CLAUDE_CODE_OAUTH_TOKEN` from
`claude setup-token` (kept in a mode-600 file) before `run`. `doctor` checks the login and
prints this hint when it fails.

## Test hooks

`CLAUDE_BIN`, `GH_BIN` (fake binaries), `AUTOPILOT_QUEUE_WATCH_MIN=0` (no stall check),
`AUTOPILOT_QUEUE_NO_NOTIFY=1` (no osascript, no Slack). Tests: `bash bin/autopilot-queue.test.sh`.
