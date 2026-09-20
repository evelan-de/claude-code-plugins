---
name: mission-control
description: "Queue control: status, add, retry, stop, log, start. Triggers on \"/mission-control\", \"mission control\", \"was läuft gerade\", \"Warteschlange\", \"queue status\", \"nimm X dazu\", \"stopp die Warteschlange\"."
argument-hint: "[status | add <repo> <item> | retry <repo> <#pr|item> | stop | log [item] | start | doctor | schedule HH:MM]"
---

# Mission control

Thin wrapper around the `mission-control` script (plugin `bin/`, docs in
`skills/autopilot/references/mission-control.md`). Minimal token footprint is the point:
one command, relay its lines, done.

## Where the queue runs

`~/.claude/mission-control/host` exists only on a machine that does NOT run the queue. It
holds the SSH alias of the machine that does (e.g. `office-mini`). When the file exists, run
every command over SSH; otherwise run it locally. No hostname comparison.

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
| "starte jetzt", start | remote: `kickstart`; it refuses while a run is active or when no schedule is installed, relay that message. Local: `run` with Bash `run_in_background`, then say that progress arrives as macOS/Slack notifications and via `status`, not from the background call |
| doctor | `doctor` |
| schedule HH:MM | `install-schedule HH:MM` |

## Output rule

Relay the script's lines as they are, compact, in the user's language. Never open the env
file, never print a webhook URL. A log is at most the 40 lines the script gives. Do not poll
or loop: answer once per request. One command per Bash call.
