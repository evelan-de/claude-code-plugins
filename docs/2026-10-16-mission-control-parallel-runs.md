# Mission control: several runs at once, a check every 15 minutes (2026-10-16)

## Why

- **One run at a time left the Mini idle.** The queue on the office Mini ran one item after
  another: a second labelled PR waited for hours although the machine had room for it.
  Andreas asked for more autopilot sessions in parallel.
- **A check every 30 minutes was too slow.** A PR labelled right after a check waited up to
  half an hour before anything happened, and during a run the launchd check could not fire
  at all (launchd starts no second instance of a running job), so new work waited for the
  whole run.

## What changed

- `run` is a scheduler. It holds the one lock per machine and starts a worker process per
  item (`run-one`, internal), up to `MISSION_CONTROL_SLOTS` at once (default 2). A slot that
  becomes free is filled at once; while items run, the queue and the labelled PRs are checked
  again every `MISSION_CONTROL_CHECK_MIN` minutes (15). The run ends when nothing runs and
  nothing waits.
- `MISSION_CONTROL_SLOTS_PER_REPO` (default no limit) keeps the items of one project one
  after another where the gate or the dev stack needs a fixed resource.
- Each worker gets `PORT=<3000 + slot - 1>` and `AUTOPILOT_SLOT`; the autopilot skill and the
  browser reference open the dev server on `$PORT`, so two runs of one project do not verify
  each other's app.
- The git steps that touch a repository's shared `.git` (worktree add, fetch, push, worktree
  remove) take a per-repository lock (`locks/`). Edits of `queue.txt` and `held.txt` take
  `edit.lock`. Both exist so two workers never lose each other's change.
- `status` lists every running item with its slot and a `slots: N of M busy` line. `stop
  <item>` ends one item; `stop` ends the run.
- The documented schedule is `install-schedule 15m`.

## Decisions

- **Default two slots, no limit per repository.** Nearly every item is in one project
  (jexity-chatbot), so a per-repository limit of 1 would give nothing. The port per slot
  removes the one known collision (the browser check on `localhost:3000`). A project with a
  Docker Compose file that maps fixed host ports still collides; set
  `MISSION_CONTROL_SLOTS_PER_REPO=1` for such a machine, or make the compose file read
  `$PORT`-based ports.
- **Worker processes, not threads, not detached processes.** A process per item keeps the
  runner's per-item state (log, claude process, stop flag) separate without touching the
  item code; the parent waits for its workers, so the lock, `stop`, `start` and the launchd
  check keep their meaning and the Keychain login of the GUI session is inherited as before.

## Rollout on the office Mini

The LaunchAgent runs the marketplace checkout, so the next scheduled check after the merge
and the plugin update there already runs two items at once; nothing to reinstall for that.
The reinstall only changes how often launchd checks while the queue is idle: `mission-control
stop` (every running item ends and stays queued or labelled), `mission-control
install-schedule 15m`, `mission-control start`; the stopped items start again from their
kept worktrees. Until then the installed agent checks every 30 minutes.
