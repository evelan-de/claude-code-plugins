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
| `done.txt` | Appended per item: `<ISO time> <repo> <item> <status> <pr url or ->`, then `restarts=N` when the run handed off or ended early, `no-plan` when no `PLAN.md` existed, `labels-failed` when a `gh` call after the run failed, `jira-failed` when the ticket update failed, `review-comments=N` (done items in a repo with the Claude review workflow: comments on the PR by anyone but the PR author and the gh account of the queue machine; `0` is said on stdout) and `unanswered-review-comments=N` (inline bot threads without a reply from the PR author or the queue machine's account; said on stdout, every bot comment must be answered "Fixed in <sha>" or "Not changed: <reason>"). Status: `done`, `blocked`, `handoff-limit`, `timeout`. |
| `env` | Optional, mode 600. Shell assignments, see below. `run` and `list` warn when the mode is not 600 and continue; `doctor` fails on it. |
| `logs/` | `<timestamp>-<item>.log` per item (queue lines plus the full claude output). A PR item starts as `<timestamp>-_<n>.log` and is renamed to `<timestamp>-_<n>-<resolved item>.log` once the session directory or ticket key is known, so `log #12`, `log PAUL-2801` and `log <session dir>` all find it. `queue.log` for lines outside an item (source failures, warnings), `launchd.log` for the schedule. |
| `worktrees/` | `<repo basename>-<item>/`; removed after `done`, kept otherwise so the state survives. |
| `run.lock/` | Exists while a run is active: `pid` of the run and `current` (the item it is on, read by `status`). Removed when the run ends. |
| `paused` | One date, `YYYY-MM-DD` (local time): the schedule is paused through that day. Written by `pause`, removed by `resume` or by the first scheduled run after the date. See "Pause the schedule". |
| `force-once` | Written by `start`; the next scheduled run consumes it and goes ahead although a pause is set. |
| `host` | Not read by the script. Holds the SSH alias of the office Mini (`office-mini`) on a machine that wants to reach its queue; the `/mission-control` skill then runs commands over SSH (status: both, local and remote). A machine with a `host` file may run its own local queue as well; keep its `repos.txt` empty so labelled PRs are processed by the Mini only. |

Settings in `env` (environment variables override them; defaults in brackets):
`SLACK_WEBHOOK_URL` (none), `MISSION_CONTROL_MODEL` (sonnet) and `MISSION_CONTROL_EFFORT`
(medium; a plan's `Model:` and `Effort:` headers win over these defaults, a value set in the
environment wins over the plan; a sonnet run below xhigh runs at xhigh),
`MISSION_CONTROL_ADVISOR` (fable), `MISSION_CONTROL_FALLBACK_MODEL` (opus; left out for a run
on the same model family), `MISSION_CONTROL_BUDGET_USD` (100 per attempt for sonnet, 120 for opus),
`MISSION_CONTROL_MAX_RESTARTS` (5), `MISSION_CONTROL_TIMEOUT_MIN` (240 per attempt, a
restart gets a fresh 240), `MISSION_CONTROL_WATCH_MIN` (20, the stall check interval).

## Not on this machine?

The queue commands (`run`, `list`, `add`, `status`, `stop`, `retry`, `log`, `start`,
`pause`, `resume`) refuse
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
mission-control run [--scheduled]         # process queue.txt, then the labelled PRs of repos.txt; --scheduled honours a pause
mission-control status                    # one screen: running item, queue, labelled PRs, last done, schedule, lock
mission-control stop                      # TERM the active run (its trap kills claude), wait up to 45 s
mission-control retry <repo> <#pr | item> # PR: label autopilot-blocked -> autopilot-ready; item: add it again
mission-control log [<item>]              # last 40 lines of the newest item log (or the newest one for #pr, key or session dir)
mission-control pause [until <YYYY-MM-DD> | <N>d]   # no scheduled run today / through that day / for N days
mission-control resume                    # lift the pause
mission-control start                     # run now, inside the GUI session; installs the LaunchAgent on demand; refuses while a run is active
mission-control install-schedule [22:00]  # LaunchAgent (macOS), daily at that time, or on demand only without a time; runs "run --scheduled"
mission-control uninstall-schedule
```

`status` exits 0 and prints, in this order: `running: <repo basename> <item> (attempt N,
since HH:MM, <elapsed> min, phase: <last progress line of the item log>)` or `running: none`,
and for a running item three indented lines: `package: <the [~] line of the item's PLAN.md>`
(or `none marked [~]`), `run: <ISO time> ctx=<tokens> tool=<name>` (the line the run's
context-budget hook rewrites after every tool call, `.claude/.autopilot-status` in the
worktree; `no status line yet` before the first) and `diff since base: <git diff --shortstat
against the merge-base>`;
`queue: N items` plus the next three queue lines; `labelled PRs: N (<repo> N, ...)` via `gh`
(a failing repo gets a `FAIL - ...` line, the count goes on without it; when `gh` has no
token at all, one `gh: ...` notice and `labelled PRs: unknown (gh not authenticated in this
session)` replace the counts, see "Over SSH"); `last done:` with the
last five `done.txt` lines; `schedule: installed at HH:MM, active`, `schedule: installed at
HH:MM, paused until <date>` (time read from the plist, date from `paused`), `schedule: on
demand only ("mission-control start"), no nightly run` (a LaunchAgent without a time),
`schedule: installed at HH:MM (legacy, ignores pause)` plus the warning line described under "Pause the
schedule" when the plist lacks `--scheduled`, or `schedule: not installed`; `lock: held by
pid N`, `free`, or `stale` when the recorded pid is dead. No secrets: the env file is never
printed.

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

`start` runs `launchctl kickstart gui/<uid>/de.evelan.mission-control`: the LaunchAgent
starts a `run` now, inside the GUI session, so the Keychain login is readable even when the
command arrives over SSH. No LaunchAgent installed → it installs one without a schedule
first (`install-schedule` with no time: the plist has no `StartCalendarInterval`, so it only
runs on `start`). It refuses with exit 1 while a run is active (`a run is active (pid N,
<item>), stop it first`). Output goes to `logs/launchd.log`; follow it with `log` once an
item log exists. It works during a pause: it writes `force-once` before the `launchctl
kickstart`, so that one scheduled run goes ahead and the pause stays for the following
nights. A refused start writes nothing. `kickstart` is the old name and does the same.

`labels` is the one source of truth for the three labels (`autopilot-ready` 0E8A16,
`autopilot-done` 1D76DB, `autopilot-blocked` B60205, each with a description). It prints
`exists` or `created` per label, exits 1 when one could not be created. `doctor` calls it
for every repo in `queue.txt` and `repos.txt`, and prints how many repos it found.

`add`, `retry` and `labels` expand a leading `~/` in the repo path themselves, so a path
written as `~/dev/projects/paul` works when it arrives unexpanded (over SSH, from a file).
A bare project name (`paul`, no `/`) means `~/dev/projects/paul` (`MISSION_CONTROL_PROJECTS`
overrides the directory); the same rule applies to `queue.txt` and `repos.txt` lines.

`add` with a session directory and no branch records the branch that holds the directory as
the third column: the repo's current branch when the directory exists in the checkout, else
the branch at whose tip it was last touched (`git log --all`, after a fetch), else the default
branch. Pass the branch explicitly when you know better. A ticket key or topic gets no branch
column and runs from the default branch.

## Three ways in

0. **From a Claude session on a machine with a queue.** `/autopilot <session dir>` runs
   `mission-control add <repo> <session dir>` and `mission-control start`; the run happens
   in the background, chained by the runner, never in that session.
1. **The list.** `/autopilot-plan` for the topic, then
   `mission-control add ~/dev/projects/paul docs/autopilot/sessions/2026-09-20-PAUL-2801-export`.
   A plan on a feature branch works: `add` records the branch and the run checks it out.
   A ticket key or topic without a plan is allowed: the run writes its own plan with
   conservative decisions, and `done.txt` marks the item `no-plan`.
2. **A labelled PR.** A developer runs `/autopilot-plan`, pushes the branch, opens a draft PR
   and adds the label `autopilot-ready`. The repo must be in `repos.txt`. The queue takes the
   session directory on that branch that has a `PLAN.md` as the item (name contains the ticket
   key from the branch name, or created or changed on the branch compared with the PR's
   target branch, e.g. `preview`); among several, the one whose `Branch:` header names the PR
   branch wins. A plan whose `Branch:` header names another branch (and whose `Branch mode:`
   is not `feature-branch <PR branch>`) is never run: the item is `blocked` with both branch
   names in the reason. Without a plan it uses the ticket key from the branch name (else the
   branch name) and marks `no-plan`.

## What `run` does per item

1. Resolves the repo and, for a PR, its branch and target branch (`gh pr view`).
2. Creates a worktree under `worktrees/`: on the PR branch or the recorded branch (fetched
   first; a branch checked out elsewhere, e.g. in the user's own checkout, is checked out here
   anyway with `--ignore-other-worktrees`, and the queue says where else it is: do not commit
   there until the item is done), or
   detached from the repo's default branch (`git-default-branch`) for items without a branch.
   An existing worktree for the same item is reused: it is fetched and fast-forwarded first
   (a developer may have pushed a fix); when it cannot be fast-forwarded the queue says so and
   continues on the local state. The same refresh runs before every restart. Your own
   checkout is never touched. A worktree that cannot be prepared makes the item `blocked`; a
   PR still gets its label and comment, via the repo.
3. Model and effort: the `Model:` (`sonnet` or `opus`) and `Effort:` headers of the item's
   `PLAN.md` when there is one, unless `MISSION_CONTROL_MODEL` / `MISSION_CONTROL_EFFORT` is
   set in the environment. A sonnet run below xhigh is raised to xhigh (`max` stays). Any
   other `Model:` value makes the item `blocked` before anything runs, with the header line
   in the reason. Budget per attempt: 100 USD for sonnet, 120 for opus, unless
   `MISSION_CONTROL_BUDGET_USD` is set. Ticket: the `Ticket:` header; when the
   `jira` script and `~/.claude/jira/env` exist on this machine, `jira start <KEY>` runs now
   (In Progress, assigned to the token owner); a failure is said, logged as `jira-failed`,
   and the run goes ahead. Without the credentials file the log says the ticket was not
   updated. A PR item gets a comment "Autopilot started on <host> at <time> (model, effort).
   Please do not push to this branch until the result comment arrives."
4. Starts the run in the background, output to the item log:
   `claude -p "/autopilot <item>" --model <model> --effort <effort> --advisor <advisor>
   [--fallback-model <fallback>] --permission-mode auto --max-budget-usd <budget> --output-format json`
   (fallback entries of the run model's family are left out).
   Every `WATCH_MIN` minutes `autopilot-watchdog` checks for a new commit, a plan change or a
   change of the run's status file (`.claude/.autopilot-status`, rewritten by the
   context-budget hook after every tool call); four stalls in a row (no tool call, no commit, no plan change
   for 4 × `WATCH_MIN`) kill the run (`stalled` in the log). The wall-clock timeout kills it
   too (`timeout`). A kill is SIGTERM to the claude process, SIGKILL after 10 s; a child of a
   tool call (dev server, test runner) may survive it.
5. After the exit it looks for the item's session directory: the item itself when it is one,
   else a directory whose name contains the ticket key, else a directory created or changed
   since the item's base commit (merge-base with the PR's target branch, for other items
   with the default branch). Never an unrelated
   directory: an old session with a `REPORT.md` does not make a new item `done`. No
   directory → `blocked` ("no session directory for this item").
   `HANDOFF.md` present → the same item is started again (up to `MAX_RESTARTS`, then
   `handoff-limit`), unless a `REPORT.md` is newer than it (an abort in a continuation):
   then the report decides. A clean exit (code 0) with neither file, and no budget error in
   the output, is treated the same way: restart, up to `MAX_RESTARTS`. `REPORT.md` present → its first line decides: `Status: done` → `done`;
   `Status: blocked - <reason>` → `blocked` with that reason; no `Status:` line → `blocked`
   ("report without status line"). Neither file → `blocked` (the reason names the budget
   when the claude output ends with a `max_budget` error). After every attempt the runtime
   files `.claude/.autopilot-active`, `.autopilot-status` and `.autopilot-gate-blocks` are
   removed from the worktree; the sentinel is created again before the next attempt.
6. Finds the PR the run pushed (`gh pr list --head <branch>`). `done`: draft → ready, label
   `autopilot-ready` swapped for `autopilot-done`, comment "Autopilot report" with the first
   60 lines of `REPORT.md`. Otherwise: label swapped for `autopilot-blocked`, comment with the
   status, the reason and the log path; add `autopilot-ready` again to retry after you fixed
   the cause. A failing `gh pr ready`, `pr edit` or `pr comment` is said on stdout and
   recorded as `labels-failed` in `done.txt` and the notification (the run itself still
   counts as `done` or `blocked`).
7. With a ticket and credentials: `jira comment <KEY> -` with the status, the PR link and
   the first 40 lines of `REPORT.md` as plain text (headings stripped). In a repo with
   `.github/workflows/claude-code-review.yml`, counts the PR comments not by the PR author
   (`review-comments=N`) and the inline bot threads the run left without a reply
   (`unanswered-review-comments=N`, said on stdout). Appends to `done.txt`, removes the line from `queue.txt`, notifies
   (macOS notification with a sound: Glass for `done`, Sosumi with the reason for everything
   else; Slack when `SLACK_WEBHOOK_URL` is set), removes the worktree after `done`.

Progress on stdout, one line per step: `[mission-control] <repo> <item>: <phase>`.
A lock (`run.lock`) refuses a second `run` while one is active; a lock left by a dead
process is taken over. Before polling the repos, `run`, `list` and `status` check once
whether `gh` can read its token (`gh auth status`). When it cannot, they print one notice
instead of one line per repo and skip the polling: over SSH (`SSH_CONNECTION` or `SSH_TTY`
set) `gh: token not readable in this SSH session (macOS Keychain); labelled PRs unknown
here, the scheduled run in the GUI session sees them`, and `run` and `list` still exit 0;
anywhere else `gh: not authenticated (run "gh auth login -h github.com -w"); labelled PRs
unknown`, and `run` and `list` exit 1 (a real login problem). The queue items of `run` are
processed either way. When `gh` is authenticated and `gh pr list --label` fails for one
repo (repo not found, network), `run` and `list` print
`FAIL - <repo>: gh pr list --label autopilot-ready failed (...)`, log it to `queue.log`,
continue with the other repos and the list, and exit 1 at the end.

## Login and the schedule

Claude Code keeps its login in the macOS Keychain. A shell over SSH, or a launchd job
outside your GUI session, cannot read it: `claude -p` says "Not logged in" although the Mac
is logged in. So start `run` from a Terminal in the Mac's own session, or install the
schedule: `install-schedule HH:MM` writes
`~/Library/LaunchAgents/de.evelan.mission-control.plist`, loaded with
`launchctl bootstrap gui/<uid>`, which runs inside the GUI session. The agent runs
`mission-control run --scheduled` (the flag is what makes a pause count). Re-running
`install-schedule` replaces the plist: bootout, then bootstrap. Output goes to
`logs/launchd.log`. For SSH-triggered starts, export `CLAUDE_CODE_OAUTH_TOKEN` from
`claude setup-token` (kept in a mode-600 file) before `run`. `doctor` checks the login and
prints this hint when it fails.

### Over SSH

The GitHub CLI keeps its token in the macOS Keychain as well, so a `status`, `list` or `run`
that arrives over SSH cannot read it. The script says so once, `gh: token not readable in
this SSH session (macOS Keychain); labelled PRs unknown here, the scheduled run in the GUI
session sees them`, and `status` shows `labelled PRs: unknown (gh not authenticated in this
session)` instead of the counts. That is not a login problem and not 47 broken projects:
the nightly run starts from the LaunchAgent inside the GUI session, reads the token and
sees every labelled PR. Only a manual `run` over SSH is blind to PRs; its queue items still
run. Optional, the owner's call: `gh auth login -h github.com -w --insecure-storage` stores
the token in a mode-600 file (`~/.config/gh/hosts.yml`) instead of the Keychain, which makes
SSH-driven commands see PRs too; the trade-off is a plain-text token on disk.

The LaunchAgent runs `~/.claude/plugins/marketplaces/evelan-plugins/bin/mission-control`,
the marketplace checkout, not the versioned plugin cache: after a plugin update that checkout
is what runs, no re-install needed. When the checkout is missing, `install-schedule` points
at its own path and warns that a plugin update moves it. The agent's `PATH` is
`/opt/homebrew/bin:/usr/local/bin:~/.local/bin:<that bin dir>:/usr/bin:/bin`, its working
directory `$HOME`.

## Pause the schedule

Three commands, one file (`paused`, holding a date `YYYY-MM-DD` in local time):

```
mission-control pause                     # today only: "paused until 2026-09-20"
mission-control pause until 2026-09-25    # through that day inclusive
mission-control pause 3d                  # today plus three days
mission-control resume                    # "resumed", or "not paused"
```

`pause` prints `paused until <date>` and writes that date. A date that is not a real
calendar day (`2026-02-30`, `31.12.2026`, a weekday name) is refused with exit 2 (`not a
date: '...'`), and so is a date before today (`date is in the past: <date>`); the file stays
as it was in both cases. Today itself is allowed.

What a pause does: the LaunchAgent starts `run --scheduled`. While the pause is valid (its
date is today or later) that run prints and logs `paused until <date>: scheduled run skipped
(manual runs still work)` and exits 0 without taking the lock or touching the queue. The
first scheduled run after the date removes the file, logs `pause expired (<date>), file
removed` in `queue.log` and goes on as usual. A `paused` file without a readable date
(empty, or hand-edited) is removed too; that run prints and logs `pause file unreadable
(<content or empty>), removed, run goes ahead`. `status` shows `schedule: installed at
HH:MM, paused until <date>` while the pause is valid, `..., active` otherwise.

Legacy schedule: a LaunchAgent installed before the pause feature runs plain `run`, without
`--scheduled`, so it never looks at the pause file. `pause`, `resume` and `status` detect
that (the plist's `ProgramArguments` lack `--scheduled`) and print `schedule installed
without --scheduled: run "mission-control install-schedule HH:MM" again, otherwise the
nightly job ignores the pause` with the time read from the plist; `status` shows
`schedule: installed at HH:MM (legacy, ignores pause)` instead of active or paused. The
pause file is still written; reinstalling the schedule makes it count.

What a pause does not do: a manual `mission-control run` (no flag) ignores it entirely, and
`start` overrides it once: it writes `force-once`, which the scheduled run it starts
consumes at its start (and which a scheduled run removes at its end in any case), so a
"start now" during a pause works and the pause still holds for the following nights.

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
