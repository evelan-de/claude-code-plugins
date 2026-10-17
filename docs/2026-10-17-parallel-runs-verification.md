# 2026-10-17 - Parallel runs verified on the office Mini (plugin 3.6.0)

End-to-end check of `mission-control` running two autopilot items at once, on the office
Mini (HOME `/Users/andreas`, LaunchAgent `de.evelan.mission-control`, marketplace checkout
`~/.claude/plugins/marketplaces/evelan-plugins` at commit 6281bea, plugin 3.6.0).
Project: `autopilot-smoke-test`. Items: two one-package smoke plans, each on its own branch
with a draft PR labelled `autopilot-ready`:

| PR | Branch | Session directory |
|---|---|---|
| evelan-de/autopilot-smoke-test#6 | `feat/smoke-is-even` | `docs/autopilot/sessions/2026-10-17-smoke-is-even` |
| evelan-de/autopilot-smoke-test#5 | `feat/smoke-square` | `docs/autopilot/sessions/2026-10-17-smoke-square` |

The smoke project has no dev server, so each plan asks the run to write its `PORT` and
`AUTOPILOT_SLOT` values into `REPORT.md` under `## Environment`. The live process
environment was read with `ps -E` as a second source. Times are UTC unless a status line
says otherwise (status prints local time, UTC+2).

## Result

Everything the task asked for was observed on the office Mini:

- Two items started in the same second in slot 1 and slot 2; `status` showed two
  `running:` lines and `slots: 2 of 2 busy`.
- The item logs are `20261017-143956-s1-_6-2026-10-17-smoke-is-even.log` and
  `20261017-143956-s2-_5-2026-10-17-smoke-square.log`.
- Slot 1 ran with `PORT=3000 AUTOPILOT_SLOT=1`, slot 2 with `PORT=3001 AUTOPILOT_SLOT=2`.
- `stop <item>` on the slot 2 item ended only that worker; slot 1 kept running, the PR kept
  its `autopilot-ready` label, and the next scheduled check (15 min later) picked it up again,
  reused its worktree with the staged work and finished it.
- Both items ended with their own `done.txt` line, result comment and `autopilot-done` label.
- `logs/queue.log` has no `could not remove` and no `worker ended with exit` line.

Three defects or oddities were seen, none in the parallel path itself (findings 1 to 3).

## Findings

### 1. `doctor` fails on the office Mini with a cold prompt cache although the login works (defect, doctor only)

Fixed in plugin 3.6.1 (PR 44): the probe budget is 0.50 USD, settable as `MISSION_CONTROL_DOCTOR_PROBE_USD`, and an exhausted budget is explained as such.

`mission-control doctor` exits 1 with

```
FAIL - claude -p did not answer OK: Error: Exceeded USD budget (0.05)
       Claude Code keeps its login in the macOS Keychain. ...
```

The probe is `claude -p "reply with the single word OK" --model haiku --max-budget-usd 0.05`
(`bin/mission-control`, `cmd_doctor`). Measured on the office Mini with the same command at
`--max-budget-usd 1 --output-format json`, half an hour later: it answered `OK` at
`total_cost_usd` 0.0375 with 26,921 cache-read and 17,304 cache-creation input tokens (the
global CLAUDE.md, plugins and skills that every `claude -p` session loads). A cold prompt
cache writes all of that at the cache-creation rate, and the probe then crosses 5 cents
before it answers. A second `doctor` right after the measurement printed
`ok   - claude -p answers (logged in)` and `doctor: all checks passed`. So `doctor` fails on
the office Mini whenever the prompt cache is cold (first call of the day, or after a plugin
update changes the loaded text) and passes a minute later. The hint text blames the Keychain
login, which works: the runs in this check started and finished normally. The budget of the
probe is too small for this machine, and the hint text does not match the cause. The rest of
the doctor output, including `slots: 2 items at once, new work checked every 15 min while
items run`, is correct.

### 2. `status` on the office Mini says "lock: stale" for a run that started while status was running (cosmetic)

Fixed in plugin 3.6.1 (PR 44): `status` asks `gh` first and reads the lock and the running items after that, at one moment.

Both runs of this check were caught by a status call that was already running when the run
started:

```
===== 2026-10-17T12:39:28Z
running: none
slots: 0 of 2 busy
...
lock: stale (pid 28145 is no queue run, the next run takes it over)
```

```
13:00:59Z running: none slots: 0 of 2 busy lock: stale (pid 70652 is no queue run, the next run takes it over)
```

Pid 28145 and pid 70652 are the `run --scheduled` processes (both verified with `ps`,
`lstart` equal to `run.lock/started`). The next status call, a few seconds later, said
`lock: held by pid 28145` and `running: pid 70652, no item yet`.

Cause, from the code: `cmd_status` evaluates `pid = lock_pid()` as its first step, then
spends about 30 seconds on `gh pr list` for the 49 repos, and prints the lock line last. That
last step uses the old `pid` (empty: there was no lock when status began) but reads
`run.lock/pid` afresh for the message, so a run that took the lock during the gh phase is
reported as `lock: stale (pid <the live run> is no queue run, ...)`. `acquire_lock()` itself
is clean: it prepares `run.lock.<pid>` with `pid` and `started` inside and renames it into
place, so the lock never exists without its files. Nothing acts on the wording (the run goes
ahead), but a `/mission-control` status read in that half minute reports a stale lock that is
not stale. Deciding the lock line from a fresh `lock_pid()` at print time would remove it.

### 3. A stopped item's log on the office Mini has no closing line (observation)

Fixed in plugin 3.6.1 (PR 44): the item log ends with a line that says the item was stopped.

After `mission-control stop docs/autopilot/sessions/2026-10-17-smoke-square` the stop is
recorded in `queue.log` only:

```
2026-10-17T12:41:32Z autopilot-smoke-test #5: worker stopped, the item stays for the next run
```

The item log `20261017-143956-s2-_5-2026-10-17-smoke-square.log` ends with the last line
before the stop:

```
2026-10-17T12:40:04Z autopilot-smoke-test docs/autopilot/sessions/2026-10-17-smoke-square: run (attempt 1, model sonnet, effort xhigh)
2026-10-17T12:40:04Z node for the run: /Users/andreas/.nvm/versions/node/v22.23.2/bin
```

`mission-control log <item>` for that attempt therefore shows a log that just ends, with no
word about the stop. The next attempt wrote a new log (`20261017-150113-s1-_5-...`), so the
old one stays like this.

## Evidence by step

### Step 1 - version and doctor

`~/.claude/plugins/marketplaces/evelan-plugins/.claude-plugin/plugin.json`: `"version": "3.6.0"`.
`doctor` prints `slots: 2 items at once, new work checked every 15 min while items run` and
49 repos, every label present; one FAIL, see finding 1.

### Step 2 - queue

`status` before the check: `running: none`, `slots: 0 of 2 busy`, `queue: 0 items`,
`labelled PRs: 0`, `schedule: every 15 min, active`, `lock: free`. Andreas chose the smoke
project; the two plan branches and draft PRs were created and labelled at 12:38 UTC.
`mission-control list` then showed both PRs. The run was started with `mission-control start`
(LaunchAgent kickstart, GUI session).

### Step 3 - both items at once

`queue.log`:

```
2026-10-17T12:39:28Z force-once consumed: scheduled run goes ahead
2026-10-17T12:39:56Z autopilot-smoke-test #6: started in slot 1 (worker pid 29092)
2026-10-17T12:39:56Z autopilot-smoke-test #5: started in slot 2 (worker pid 29093)
```

`status` at 12:40 UTC:

```
running: autopilot-smoke-test docs/autopilot/sessions/2026-10-17-smoke-is-even (attempt 1, since 14:39, 0 min, slot 1, phase: node for the run: /Users/andreas/.nvm/versions/node/v22.23.2/bin)
  package: none marked [~]
  run: 2026-10-17T12:40:46Z ctx=61473 tool=Bash
  diff since base: 5 files changed, 226 insertions(+), 18 deletions(-)
running: autopilot-smoke-test docs/autopilot/sessions/2026-10-17-smoke-square (attempt 1, since 14:39, 0 min, slot 2, phase: node for the run: /Users/andreas/.nvm/versions/node/v22.23.2/bin)
  package: none marked [~]
  run: 2026-10-17T12:40:44Z ctx=61235 tool=Read
  diff since base: 5 files changed, 226 insertions(+), 18 deletions(-)
slots: 2 of 2 busy
queue: 0 items
labelled PRs: 2 (... autopilot-smoke-test 2)
lock: held by pid 28145
```

`run.lock/current-1` and `current-2` named the two worktrees
(`.claude/worktrees/autopilot-_6` and `autopilot-_5`) and worker pids 29092 and 29093.
Environment of the two `claude -p /autopilot ...` processes (`ps -E`):

```
child 29289: claude -p /autopilot docs/autopilot/sessions/2026-10-17-smoke-is-even --model so
child env: AUTOPILOT_SLOT=1 PORT=3000
child 29198: claude -p /autopilot docs/autopilot/sessions/2026-10-17-smoke-square --model son
child env: AUTOPILOT_SLOT=2 PORT=3001
```

Inside the run, `REPORT.md` of smoke-is-even (branch `feat/smoke-is-even`):

```
## Environment
PORT=3000 AUTOPILOT_SLOT=1
```

Log names: `20261017-143956-s1-_6-2026-10-17-smoke-is-even.log`,
`20261017-143956-s2-_5-2026-10-17-smoke-square.log` (both PR logs renamed once the session
directory was known).

### Step 5 - stop one item

`mission-control stop docs/autopilot/sessions/2026-10-17-smoke-square` at 12:41 UTC, about
95 seconds into the run, answered `stopped autopilot-smoke-test
docs/autopilot/sessions/2026-10-17-smoke-square`. Right after:

```
running: autopilot-smoke-test docs/autopilot/sessions/2026-10-17-smoke-is-even (attempt 1, since 14:39, 1 min, slot 1, ...)
slots: 1 of 2 busy
labelled PRs: 2 (... autopilot-smoke-test 2)
lock: held by pid 28145
```

`run.lock/` held `current-1`, `pid`, `started` only; one `claude -p /autopilot` process was
left (pid 29289, smoke-is-even). PR 5 kept `autopilot-ready` and only its start comment. Its
worktree `autopilot-_5` stayed, on `feat/smoke-square` at the hooks commit `fbfff09`, with the
run's work staged and uncommitted (`README.md`, `PLAN.md`, `src/index.js`, `test/square.test.js`).

Re-pickup by the next scheduled check (`StartInterval` 900 s), `queue.log`:

```
2026-10-17T13:01:12Z autopilot-smoke-test #5: started in slot 1 (worker pid 71342)
```

New log `20261017-150113-s1-_5-2026-10-17-smoke-square.log`:

```
2026-10-17T13:01:13Z autopilot-smoke-test #5: resolving
2026-10-17T13:01:13Z reusing worktree /Users/andreas/dev/projects/autopilot-smoke-test/.claude/worktrees/autopilot-_5
2026-10-17T13:01:14Z feat/smoke-square fast-forwarded to origin/feat/smoke-square
2026-10-17T13:01:16Z autopilot-smoke-test #5: item docs/autopilot/sessions/2026-10-17-smoke-square
...
2026-10-17T13:01:17Z autopilot hooks current
2026-10-17T13:01:18Z autopilot-smoke-test docs/autopilot/sessions/2026-10-17-smoke-square: run (attempt 1, model sonnet, effort xhigh)
```

The staged work was still in the worktree when the new attempt started; the claude process
of the re-run had `AUTOPILOT_SLOT=1 PORT=3000`.

### Step 4 - both items finished

smoke-is-even (slot 1 of the first run), item log tail:

```
2026-10-17T12:45:11Z claude exited with 0 (exited)
2026-10-17T12:45:14Z autopilot-smoke-test docs/autopilot/sessions/2026-10-17-smoke-is-even: branch feat/smoke-is-even pushed to origin
2026-10-17T12:45:16Z gh pr edit (labels) on PR #6: ok
2026-10-17T12:45:18Z gh pr comment on PR #6: ok
2026-10-17T12:45:18Z autopilot-smoke-test docs/autopilot/sessions/2026-10-17-smoke-is-even: done (PR https://github.com/evelan-de/autopilot-smoke-test/pull/6)
2026-10-17T12:45:18Z notification: Slack message sent
2026-10-17T12:45:18Z autopilot-smoke-test docs/autopilot/sessions/2026-10-17-smoke-is-even: worktree removed
```

`done.txt`:

```
2026-10-17T12:45:18Z /Users/andreas/dev/projects/autopilot-smoke-test docs/autopilot/sessions/2026-10-17-smoke-is-even done https://github.com/evelan-de/autopilot-smoke-test/pull/6
```

PR 6: label `autopilot-done`, comments: start comment and `## Autopilot report` with
`Status: done`. `launchd.log` ends with `[mission-control] run finished`; `status` after the
run: `running: none`, `slots: 0 of 2 busy`, `lock: free`.

smoke-square (re-run in slot 1 of the second run), item log tail:

```
2026-10-17T13:09:53Z claude exited with 0 (exited)
2026-10-17T13:09:56Z autopilot-smoke-test docs/autopilot/sessions/2026-10-17-smoke-square: branch feat/smoke-square pushed to origin
2026-10-17T13:09:58Z gh pr edit (labels) on PR #5: ok
2026-10-17T13:09:59Z gh pr comment on PR #5: ok
2026-10-17T13:09:59Z autopilot-smoke-test docs/autopilot/sessions/2026-10-17-smoke-square: done (PR https://github.com/evelan-de/autopilot-smoke-test/pull/5)
2026-10-17T13:09:59Z notification: Slack message sent
2026-10-17T13:09:59Z autopilot-smoke-test docs/autopilot/sessions/2026-10-17-smoke-square: worktree removed
```

`done.txt`:

```
2026-10-17T13:09:59Z /Users/andreas/dev/projects/autopilot-smoke-test docs/autopilot/sessions/2026-10-17-smoke-square done https://github.com/evelan-de/autopilot-smoke-test/pull/5
```

PR 5: label `autopilot-done`, comments: two start comments (14:40 and 15:01 local) and
`## Autopilot report` with `Status: done`. Its `REPORT.md` says `## Environment` /
`PORT=3000 AUTOPILOT_SLOT=1` and, under open items, that P1's code "was found already staged
by a prior session that died before committing" and was verified and committed as is, so the
re-run resumed rather than redoing the package.

After the last worker ended the run checked the sources once more (status showed
`running: pid 70652, no item yet` for about half a minute, the time of the `gh pr list` calls
over 49 repos) and then ended: `launchd.log` ends with `[mission-control] run finished`, the
final `status` is `running: none`, `slots: 0 of 2 busy`, `queue: 0 items`, `labelled PRs: 0`,
`lock: free`, and `git worktree list` in the smoke project shows only the main checkout.

### Checks on `queue.log`

`grep -c "could not remove" logs/queue.log` prints `0`, `grep -c "worker ended with exit"
logs/queue.log` prints `0`. All lines of the day:

```
2026-10-17T12:39:28Z force-once consumed: scheduled run goes ahead
2026-10-17T12:39:56Z autopilot-smoke-test #6: started in slot 1 (worker pid 29092)
2026-10-17T12:39:56Z autopilot-smoke-test #5: started in slot 2 (worker pid 29093)
2026-10-17T12:41:32Z autopilot-smoke-test #5: worker stopped, the item stays for the next run
2026-10-17T13:01:12Z autopilot-smoke-test #5: started in slot 1 (worker pid 71342)
```

## Not covered

- Two items finishing at the same moment (both end-of-item paths racing on `done.txt`,
  `edit.lock` and the label swap) was not exercised: one of the two items was stopped on
  purpose for step 5 and finished in a later run on its own.
- A dev server on `$PORT`: the smoke project has none. The port assignment was verified via
  the process environment and the `## Environment` line, not via a listening server.
- Two items of two different projects at once: both items were in one project.

## State left behind

- PRs evelan-de/autopilot-smoke-test#5 and #6 were closed without merging after the check,
  each with a result comment, like the earlier smoke PRs; they keep `autopilot-done`.
- The plan branches `feat/smoke-square` and `feat/smoke-is-even` are on origin.
- During the check no code in the plugin repo was changed. The three findings were fixed afterwards in plugin 3.6.1 (PR 44), together with this note.
