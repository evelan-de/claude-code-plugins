---
name: mission-control
description: Queue control: status, add, retry, stop, log, start. Triggers on "/mission-control", "mission control", "was läuft gerade", "Warteschlange", "queue status", "nimm X dazu", "stopp die Warteschlange".
argument-hint: "[status | add <repo> <item> | retry <#pr|item> | stop | log [item] | start | doctor | schedule HH:MM]"
---

# Mission control

Thin wrapper around the `mission-control` script (plugin `bin/`, docs in
`skills/autopilot/references/mission-control.md`). Minimal token footprint is the point:
one command, relay its lines, done.

## Where the queue runs

Read `~/.claude/mission-control/host` (one hostname, e.g. `office-mini`). When the file
exists and its hostname differs from `hostname -s`, run every command as
`ssh <host> 'zsh -lc "mission-control <args>"'` (one Bash call). Otherwise run
`mission-control <args>` locally.

## Intent to command

| User says | Command |
| --- | --- |
| status, "was läuft gerade", "queue status", no argument | `status` |
| "nimm X dazu", add | `add <repo> <item>`; a bare project name resolves to `~/dev/projects/<name>` on the target machine |
| retry, "nochmal" | `retry <repo> <#pr \| item>` |
| stop, "stopp die Warteschlange" | `stop` |
| log, "zeig das Log" | `log [<item substring>]` |
| "starte jetzt", start | remote: `kickstart`; local: `run` with Bash `run_in_background`, then report the log path (`~/.claude/mission-control/logs/`) |
| doctor | `doctor` |
| schedule HH:MM | `install-schedule HH:MM` |

## Output rule

Relay the script's lines as they are, compact, in the user's language. Never open the env
file, never print a webhook URL. A log is at most the 40 lines the script gives. Do not poll
or loop: answer once per request. One command per Bash call.
