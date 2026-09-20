# `mission-control` - run prepared sessions one after another

A shell script in the plugin's `bin/` (on PATH once the plugin is installed); the
`/mission-control` skill is its control surface from a Claude session. It starts
`claude -p "/autopilot <item>"` for each queued item in its own worktree, watches the run,
restarts it when it handed off, reads the outcome from `REPORT.md`, labels the PR and
notifies you. The run itself pushes, opens or updates the PR and works the review bot; the
queue never opens PRs. One machine-wide queue, one run at a time.

## Files - all under `~/.claude/mission-control` (`MISSION_CONTROL_HOME`)

| File | Content |
|---|---|
| `queue.txt` | One item per line: `<repo path> <item> [<branch>]`. `#` starts a comment. Item = session directory (`docs/autopilot/sessions/...`), ticket key (`PAUL-2801`) or a `"quoted topic"`. The branch column exists for session directory items only; `add` fills it in. Processed top to bottom; a processed line is removed, an unparsable line (repo without item) is removed and named on stdout. |
| `repos.txt` | One repo path per line. Every open PR there with the label `autopilot-ready` is processed after the list. Andreas adds a repo once; `doctor` prints the list. |
| `done.txt` | Appended per item: `<ISO time> <repo> <item> <status> <pr url or ->`, then `restarts=N` when the run handed off, `no-plan` when no `PLAN.md` existed, `labels-failed` when a `gh` call after the run failed. Status: `done`, `blocked`, `handoff-limit`, `timeout`. |
| `env` | Optional, mode 600. Shell assignments, see below. `run` and `list` warn when the mode is not 600 and continue; `doctor` fails on it. |
| `logs/` | `<timestamp>-<item>.log` per item (queue lines plus the full claude output). A PR item starts as `<timestamp>-_<n>.log` and is renamed to `<timestamp>-_<n>-<resolved item>.log` once the session directory or ticket key is known, so `log #12`, `log PAUL-2801` and `log <session dir>` all find it. `queue.log` for lines outside an item (source failures, warnings), `launchd.log` for the schedule. |
| `worktrees/` | `<repo basename>-<item>/`; removed after `done`, kept otherwise so the state survives. |
| `run.lock/` | Exists while a run is active: `pid` of the run and `current` (the item it is on, read by `status`). Removed when the run ends. |
| `host` | Not read by the script. Exists only on a machine that does NOT run the queue and holds the SSH alias of the one that does (`office-mini`); the `/mission-control` skill then runs every command over SSH, without it locally. |

Settings in `env` (environment variables override them; defaults in brackets):
`SLACK_WEBHOOK_URL` (none), `MISSION_CONTROL_MODEL` (sonnet), `MISSION_CONTROL_EFFORT`
(medium; a plan's `Effort:` header wins over this default, an `MISSION_CONTROL_EFFORT` set in
the environment wins over the plan), `MISSION_CONTROL_ADVISOR` (fable),
`MISSION_CONTROL_FALLBACK_MODEL` (opus), `MISSION_CONTROL_BUDGET_USD` (60 per run),
`MISSION_CONTROL_MAX_RESTARTS` (3), `MISSION_CONTROL_TIMEOUT_MIN` (240 per item, restarts
included), `MISSION_CONTROL_WATCH_MIN` (20, the stall check interval).

## Not on this machine?

The queue commands (`run`, `list`, `add`, `status`, `stop`, `retry`, `log`, `kickstart`) refuse
with exit 3 when `~/.claude/mission-control` does not exist: the machine has no queue. The
message points to the office Mini and to the developer's way in (`/autopilot-plan`, draft PR
labelled `autopilot-ready`, results on the PR and in Slack `#mission-control`). `doctor`,
`labels` and `install-schedule` still work; `doctor` creates the directory. The
`/mission-control` skill checks the same before running anything, so a developer who has the
plugin but no queue gets the pointer instead of an empty local status.

## Commands

```
mission-control doctor                    # login, gh, git, repos, labels, env mode; exit 1 on any failure
mission-control labels [<repo>]           # create autopilot-ready/-done/-blocked when missing (default: cwd)
mission-control add <repo> <item> [<branch>]   # append a line; a topic with spaces is quoted
mission-control list                      # what run would process, no side effects
mission-control run                       # process queue.txt, then the labelled PRs of repos.txt
mission-control status                    # one screen: running item, queue, labelled PRs, last done, schedule, lock
mission-control stop                      # TERM the active run (its trap kills claude), wait up to 45 s
mission-control retry <repo> <#pr | item> # PR: label autopilot-blocked -> autopilot-ready; item: add it again
mission-control log [<item>]              # last 40 lines of the newest item log (or the newest one for #pr, key or session dir)
mission-control install-schedule 22:00    # LaunchAgent, daily at that time (macOS)
mission-control uninstall-schedule
mission-control kickstart                 # run the installed LaunchAgent now, inside the GUI session; refuses while a run is active
```

`status` exits 0 and prints, in this order: `running: <repo basename> <item> (attempt N,
since HH:MM, <elapsed> min, phase: <last progress line of the item log>)` or `running: none`;
`queue: N items` plus the next three queue lines; `labelled PRs: N (<repo> N, ...)` via `gh`
(a failing repo gets a `FAIL - ...` line, the count goes on without it); `last done:` with the
last five `done.txt` lines; `schedule: installed at HH:MM` (read from the plist) or `not
installed`; `lock: held by pid N`, `free`, or `stale` when the recorded pid is dead. No
secrets: the env file is never printed.

`stop` sends TERM to the run's pid when the lock holds a live one; the run's trap kills the
claude process (SIGTERM, SIGKILL after 10 s) and releases the lock. Every sleep in the run
loop is interruptible, so the stop takes effect at once, not after the next watch step.
Prints `stopped <repo> <item>`, or `still running (pid N)` with exit 1 after 45 s, or
`nothing running`. The stopped item stays in `queue.txt` (a list item) or keeps its label
(a PR item), so the next run takes it again; `log <item>` still finds the log of the
stopped run.

`retry <repo> <#pr>` (`#N` or an all-digit argument) swaps `autopilot-blocked` for
`autopilot-ready` on that PR and says so; when `gh pr edit` fails, the message carries the
first line of its stderr. `retry <repo> <item>` appends the item to `queue.txt` like `add`:
a session directory with the branch the kept worktree is on, so the retry continues where
the blocked run stopped; any other item (ticket key, topic) exactly as given, without a
branch.

`log [<item>]` names the file it shows (`log: <path>`), then `tail -n 40` of it. The
argument is matched against the file name without its leading timestamp, after the same
normalisation the file names use (`#12` becomes `_12`, a session directory its basename), so
`log 12` never matches a date. Item logs only; `queue.log` and `launchd.log` are read
directly.

`kickstart` runs `launchctl kickstart gui/<uid>/de.evelan.mission-control`: the installed
LaunchAgent starts a `run` now, inside the GUI session, so the Keychain login is readable
even when the command arrives over SSH. It refuses with exit 1 while a run is active
(`a run is active (pid N, <item>), stop it first`) and when no schedule is installed
(`no schedule installed; run "mission-control install-schedule HH:MM" once, or start
"mission-control run" in a Terminal on this Mac`). Output goes to `logs/launchd.log`; follow
it with `log` once an item log exists.

`labels` is the one source of truth for the three labels (`autopilot-ready` 0E8A16,
`autopilot-done` 1D76DB, `autopilot-blocked` B60205, each with a description). It prints
`exists` or `created` per label, exits 1 when one could not be created. `doctor` calls it
for every repo in `queue.txt` and `repos.txt`, and prints how many repos it found.

`add`, `retry` and `labels` expand a leading `~/` in the repo path themselves, so a path
written as `~/dev/projects/paul` works when it arrives unexpanded (over SSH, from a file).

`add` with a session directory and no branch records the branch that holds the directory as
the third column: the repo's current branch when the directory exists in the checkout, else
the branch at whose tip it was last touched (`git log --all`, after a fetch), else the default
branch. Pass the branch explicitly when you know better. A ticket key or topic gets no branch
column and runs from the default branch.

## Two ways in

1. **The list.** `/autopilot-plan` for the topic, then
   `mission-control add ~/dev/projects/paul docs/autopilot/sessions/2026-09-20-PAUL-2801-export`.
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
   `MISSION_CONTROL_EFFORT` is set in the environment.
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

Progress on stdout, one line per step: `[mission-control] <repo> <item>: <phase>`.
A lock (`run.lock`) refuses a second `run` while one is active; a lock left by a dead
process is taken over. When `gh pr list --label` fails for a repo, `run` and `list` print
`FAIL - <repo>: gh pr list --label autopilot-ready failed (...)`, log it to `queue.log`,
continue with the other repos and the list, and exit 1 at the end.

## Login and the schedule

Claude Code keeps its login in the macOS Keychain. A shell over SSH, or a launchd job
outside your GUI session, cannot read it: `claude -p` says "Not logged in" although the Mac
is logged in. So start `run` from a Terminal in the Mac's own session, or install the
schedule: `install-schedule HH:MM` writes
`~/Library/LaunchAgents/de.evelan.mission-control.plist`, loaded with
`launchctl bootstrap gui/<uid>`, which runs inside the GUI session. Output goes to
`logs/launchd.log`. For SSH-triggered starts, export `CLAUDE_CODE_OAUTH_TOKEN` from
`claude setup-token` (kept in a mode-600 file) before `run`. `doctor` checks the login and
prints this hint when it fails.

The LaunchAgent runs `~/.claude/plugins/marketplaces/evelan-plugins/bin/mission-control`,
the marketplace checkout, not the versioned plugin cache: after a plugin update that checkout
is what runs, no re-install needed. When the checkout is missing, `install-schedule` points
at its own path and warns that a plugin update moves it. The agent's `PATH` is
`/opt/homebrew/bin:/usr/local/bin:~/.local/bin:<that bin dir>:/usr/bin:/bin`, its working
directory `$HOME`.

## Slack notifications

Once, by a workspace admin: in Slack create an app (api.slack.com/apps), enable "Incoming
Webhooks" and add a webhook for the target channel. Copy the webhook URL into
`~/.claude/mission-control/env` on the queue machine as `SLACK_WEBHOOK_URL=https://hooks.slack.com/...`
and `chmod 600` the file. Never paste the URL into a chat, a ticket or a commit; the script
never prints it either (curl's stderr is dropped, only the exit code is logged). Without it,
notifications are macOS-only plus the PR comment.

## Test hooks

`CLAUDE_BIN`, `GH_BIN` (fake binaries), `MISSION_CONTROL_WATCH_MIN=0` (no stall check),
`MISSION_CONTROL_NO_NOTIFY=1` (no osascript, no Slack). Tests: `bash bin/mission-control.test.sh`.
