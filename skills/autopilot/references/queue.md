# `autopilot-queue` - run prepared sessions one after another

A shell script in the plugin's `bin/` (on PATH once the plugin is installed). It starts
`claude -p "/autopilot <item>"` for each queued item in its own worktree, watches the run,
restarts it when it handed off, reads the outcome from `REPORT.md`, labels the PR and
notifies you. The run itself pushes, opens or updates the PR and works the review bot; the
queue never opens PRs. One machine-wide queue, one run at a time.

## Files - all under `~/.claude/autopilot-queue` (`AUTOPILOT_QUEUE_HOME`)

| File | Content |
|---|---|
| `queue.txt` | One item per line: `<repo path> <item> [<branch>]`. `#` starts a comment. Item = session directory (`docs/autopilot/sessions/...`), ticket key (`PAUL-2801`) or a `"quoted topic"`. The branch column exists for session directory items only; `add` fills it in. Processed top to bottom; a processed line is removed, an unparsable line (repo without item) is removed and named on stdout. |
| `repos.txt` | One repo path per line. Every open PR there with the label `autopilot-ready` is processed after the list. Andreas adds a repo once; `doctor` prints the list. |
| `done.txt` | Appended per item: `<ISO time> <repo> <item> <status> <pr url or ->`, then `restarts=N` when the run handed off, `no-plan` when no `PLAN.md` existed, `labels-failed` when a `gh` call after the run failed. Status: `done`, `blocked`, `handoff-limit`, `timeout`. |
| `env` | Optional, mode 600. Shell assignments, see below. `run` and `list` warn when the mode is not 600 and continue; `doctor` fails on it. |
| `logs/` | `<timestamp>-<item>.log` per item (queue lines plus the full claude output), `queue.log` for lines outside an item (source failures, warnings), `launchd.log` for the schedule. |
| `worktrees/` | `<repo basename>-<item>/`; removed after `done`, kept otherwise so the state survives. |

Settings in `env` (environment variables override them; defaults in brackets):
`SLACK_WEBHOOK_URL` (none), `AUTOPILOT_QUEUE_MODEL` (sonnet), `AUTOPILOT_QUEUE_EFFORT`
(medium; a plan's `Effort:` header wins over this default, an `AUTOPILOT_QUEUE_EFFORT` set in
the environment wins over the plan), `AUTOPILOT_QUEUE_ADVISOR` (fable),
`AUTOPILOT_QUEUE_FALLBACK_MODEL` (opus), `AUTOPILOT_QUEUE_BUDGET_USD` (60 per run),
`AUTOPILOT_QUEUE_MAX_RESTARTS` (3), `AUTOPILOT_QUEUE_TIMEOUT_MIN` (240 per item, restarts
included), `AUTOPILOT_QUEUE_WATCH_MIN` (20, the stall check interval).

## Commands

```
autopilot-queue doctor                    # login, gh, git, repos, labels, env mode; exit 1 on any failure
autopilot-queue labels [<repo>]           # create autopilot-ready/-done/-blocked when missing (default: cwd)
autopilot-queue add <repo> <item> [<branch>]   # append a line; a topic with spaces is quoted
autopilot-queue list                      # what run would process, no side effects
autopilot-queue run                       # process queue.txt, then the labelled PRs of repos.txt
autopilot-queue install-schedule 22:00    # LaunchAgent, daily at that time (macOS)
autopilot-queue uninstall-schedule
```

`labels` is the one source of truth for the three labels (`autopilot-ready` 0E8A16,
`autopilot-done` 1D76DB, `autopilot-blocked` B60205, each with a description). It prints
`exists` or `created` per label, exits 1 when one could not be created. `doctor` calls it
for every repo in `queue.txt` and `repos.txt`, and prints how many repos it found.

`add` with a session directory and no branch records the branch that holds the directory as
the third column: the repo's current branch when the directory exists in the checkout, else
the branch at whose tip it was last touched (`git log --all`, after a fetch), else the default
branch. Pass the branch explicitly when you know better. A ticket key or topic gets no branch
column and runs from the default branch.

## Two ways in

1. **The list.** `/autopilot-plan` for the topic, then
   `autopilot-queue add ~/dev/projects/paul docs/autopilot/sessions/2026-09-20-PAUL-2801-export`.
   A plan on a feature branch works: `add` records the branch and the run checks it out.
   A ticket key or topic without a plan is allowed: the run writes its own plan with
   conservative decisions, and `done.txt` marks the item `no-plan`.
2. **A labelled PR.** A developer runs `/autopilot-plan`, pushes the branch, opens a draft PR
   and adds the label `autopilot-ready`. The repo must be in `repos.txt`. The queue takes the
   session directory on that branch that has a `PLAN.md` as the item (name contains the ticket
   key from the branch name, or created on the branch); without one it uses the ticket key
   from the branch name (else the branch name) and marks `no-plan`.

## What `run` does per item

1. Resolves the repo and, for a PR, its branch (`gh pr view`).
2. Creates a worktree under `worktrees/`: on the PR branch or the recorded branch (fetched
   first; a branch checked out in another worktree gets a detached worktree at its tip), or
   detached from the repo's default branch (`git-default-branch`) for items without a branch.
   An existing worktree for the same item is reused: it is fetched and fast-forwarded first
   (a developer may have pushed a fix); when it cannot be fast-forwarded the queue says so and
   continues on the local state. The same refresh runs before every restart. Your own
   checkout is never touched. A worktree that cannot be prepared makes the item `blocked`; a
   PR still gets its label and comment, via the repo.
3. Effort: the `Effort:` header of the item's `PLAN.md` when there is one, unless
   `AUTOPILOT_QUEUE_EFFORT` is set in the environment.
4. Starts the run in the background, output to the item log:
   `claude -p "/autopilot <item>" --model <model> --effort <effort> --advisor <advisor>
   --fallback-model <fallback> --permission-mode auto --max-budget-usd <budget> --output-format json`.
   Every `WATCH_MIN` minutes `autopilot-watchdog` checks for a new commit or plan change;
   four stalls in a row kill the run (`stalled` in the log). The wall-clock timeout kills it
   too (`timeout`). A kill is SIGTERM to the claude process, SIGKILL after 10 s; a child of a
   tool call (dev server, test runner) may survive it.
5. After the exit it looks for the item's session directory: the item itself when it is one,
   else a directory whose name contains the ticket key, else a directory created or changed
   since the item's base commit (merge-base with the default branch). Never an unrelated
   directory: an old session with a `REPORT.md` does not make a new item `done`. No
   directory → `blocked` ("no session directory for this item").
   `HANDOFF.md` present → the same item is started again (up to `MAX_RESTARTS`, then
   `handoff-limit`). `REPORT.md` present → its first line decides: `Status: done` → `done`;
   `Status: blocked - <reason>` → `blocked` with that reason; no `Status:` line → `blocked`
   ("report without status line"). Neither file → `blocked`.
6. Finds the PR the run pushed (`gh pr list --head <branch>`). `done`: draft → ready, label
   `autopilot-ready` swapped for `autopilot-done`, comment "Autopilot report" with the first
   60 lines of `REPORT.md`. Otherwise: label swapped for `autopilot-blocked`, comment with the
   status, the reason and the log path; add `autopilot-ready` again to retry after you fixed
   the cause. A failing `gh pr ready`, `pr edit` or `pr comment` is said on stdout and
   recorded as `labels-failed` in `done.txt` and the notification (the run itself still
   counts as `done` or `blocked`).
7. Appends to `done.txt`, removes the line from `queue.txt`, notifies (macOS notification;
   Slack when `SLACK_WEBHOOK_URL` is set), removes the worktree after `done`.

Progress on stdout, one line per step: `[autopilot-queue] <repo> <item>: <phase>`.
A lock (`run.lock`) refuses a second `run` while one is active; a lock left by a dead
process is taken over. When `gh pr list --label` fails for a repo, `run` and `list` print
`FAIL - <repo>: gh pr list --label autopilot-ready failed (...)`, log it to `queue.log`,
continue with the other repos and the list, and exit 1 at the end.

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

The LaunchAgent runs `~/.claude/plugins/marketplaces/evelan-plugins/bin/autopilot-queue`,
the marketplace checkout, not the versioned plugin cache: after a plugin update that checkout
is what runs, no re-install needed. When the checkout is missing, `install-schedule` points
at its own path and warns that a plugin update moves it. The agent's `PATH` is
`/opt/homebrew/bin:/usr/local/bin:~/.local/bin:<that bin dir>:/usr/bin:/bin`, its working
directory `$HOME`.

## Test hooks

`CLAUDE_BIN`, `GH_BIN` (fake binaries), `AUTOPILOT_QUEUE_WATCH_MIN=0` (no stall check),
`AUTOPILOT_QUEUE_NO_NOTIFY=1` (no osascript, no Slack). Tests: `bash bin/autopilot-queue.test.sh`.
