---
name: mission-control
description: "Queue: status, add, retry, stop, log, start, pause. Triggers on \"/mission-control\", \"mission control\", \"was läuft gerade\", \"Warteschlange\", \"queue status\", \"nimm X dazu\", \"stopp die Warteschlange\"."
argument-hint: "[status | add <repo> <item> | retry <repo> <#pr|item> | stop | log [item] | start | pause [until <date> | <N>d] | resume | doctor | schedule [HH:MM]]"
---

# Mission control

Thin wrapper around the `mission-control` script (plugin `bin/`, docs in
`skills/autopilot/references/mission-control.md`). Minimal token footprint is the point:
one command, relay its lines, done.

## Where the queue runs

Step 0, before any command: when the directory `~/.claude/mission-control` does not exist,
this machine has no queue and no way to reach one. Say so in two lines and stop: Mission
Control runs on Andreas' office Mini; hand work over with `/autopilot-plan` and the draft PR
labelled `autopilot-ready`, results arrive on the PR and in Slack `#mission-control`. Run
nothing. (The script refuses the queue commands with exit 3 in that state as well.)

`~/.claude/mission-control/host` holds the SSH alias of the office Mini (`office-mini`). A
machine with a `host` file may also run its own local queue (Andreas' MacBook does).

- No `host` file: run every command locally.
- `host` file, `status`: run it locally AND remotely, print the local block under `local:`
  and the remote block under `<alias>:`.
- `host` file, any other command: remote, unless the request says "hier", "lokal", "auf
  diesem Mac", "here", "on this Mac", "local" → local.
- Local: `mission-control <args>`
- Remote: `ssh <alias> 'zsh -lc "~/.claude/plugins/marketplaces/evelan-plugins/bin/mission-control <args>"'`
  (the plugin `bin/` is not on the remote login PATH). An item with spaces goes as
  `\"...\"` inside the remote command. Items containing quotes are not supported: say so.
- Repos: a bare project name means `~/dev/projects/<name>`. Write that literally with `~`,
  never expanded (homes differ between Macs); the remote shell or the script expands it.

## Intent to command

| User says | Command |
| --- | --- |
| status, "was läuft gerade", "queue status", no argument | `status` |
| "nimm X dazu", add | `add <repo> <item>` |
| retry, "nochmal" | `retry <repo> <#pr \| item>` (a PR gets its label back; any other item is re-added as given) |
| stop, "stopp die Warteschlange" | `stop` (the item stays in the queue or keeps its label; `log <item>` still finds its log) |
| log, "zeig das Log" | `log [<item>]` (`#12`, a ticket key or a session dir) |
| "starte jetzt", start | `start` (local or remote per step 0). It installs the LaunchAgent on demand when none exists, runs in the GUI session, refuses while a run is active (relay that message), works during a pause (that one run goes ahead, the pause stays). Then say: progress via `status`, macOS notification with sound and Slack when an item finishes |
| "heute nicht automatisch", "keine automatische Ausführung heute", pause | `pause` (today only; the nightly run skips, manual starts still work) |
| "Pause bis <Datum>", "pause until <date>" | `pause until <YYYY-MM-DD>` (through that day inclusive). A weekday name ("bis Freitag") needs no tool: from today's date (known in the session) take the next occurrence of that weekday, inclusive (today is a Friday: today), pass that date and reply with it, e.g. `pausiert bis einschließlich Freitag, 2026-09-25`. A date before today is refused with exit 2 (`date is in the past`), relay that. "<N> Tage" is `pause <N>d` |
| "wieder automatisch", "Pause aufheben", resume | `resume` |
| doctor | `doctor` |
| schedule HH:MM | `install-schedule HH:MM` (nightly); `install-schedule` without a time = on demand only |

`pause`, `resume` and `status` print a warning line when the installed schedule predates the
pause feature (`schedule installed without --scheduled: run "mission-control install-schedule
HH:MM" again, ...`). Relay it: the pause is written, but the nightly job ignores it until the
schedule is reinstalled with that command.

A line starting with `gh: token not readable in this SSH session (macOS Keychain)` means the
command ran over SSH and the GitHub CLI could not read its Keychain token there. Relay it as
it is: the labelled PRs are unknown in this session, the scheduled run in the GUI session sees
them. It is not a problem with the projects and not "gh is not authenticated for all
projects"; do not suggest logging in. `gh: not authenticated (run "gh auth login ...")`
without the SSH wording is a real login problem on that machine: relay the command.

## Output rule

Relay the script's lines as they are, compact, in the user's language. Never open the env
file, never print a webhook URL. A log is at most the 40 lines the script gives. Do not poll
or loop: answer once per request. One command per Bash call.
