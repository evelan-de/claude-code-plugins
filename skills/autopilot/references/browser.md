# Browser checks in a headless run: `agent-browser`

A run started by the runner (`claude -p`) has no desktop-app browser tools. Browser checks
use the `agent-browser` CLI (Vercel, https://github.com/vercel-labs/agent-browser): headless
Chromium, driven by commands, accessibility snapshots with refs. Never Playwright, never a
browser MCP server.

Not installed → `/autopilot init` says so; in a run it is a blocker to report
(`Status: blocked - agent-browser not installed on this machine`), not a skip.

## One session per run

```
agent-browser --session autopilot open http://localhost:3000/route
agent-browser --session autopilot close          # at the end, always
```

Set `AGENT_BROWSER_SESSION=autopilot` once instead of repeating `--session`. Login projects:
`.claude/autopilot.json` has `browserState` (path outside the repo);
launch with `--state <path>` on the `open` command. Without it, a check that needs a login
is a manual step in `MANUAL_TESTING.md`, and `REPORT.md` names the missing state file.

## Commands the run uses

```
agent-browser open <url>                         # navigate
agent-browser wait --load load                   # then, when the page renders client-side:
agent-browser wait --text "<expected text>"
agent-browser snapshot -i                        # interactive elements with refs @e1, @e2 ...
agent-browser get text "<css selector>"          # or @ref; the text the user sees
agent-browser click @e3 | fill @e4 "<value>" | type @e5 "<value>"
agent-browser get url
agent-browser screenshot <path>.png              # one per screen at most; --full for the whole page
agent-browser console                            # console messages since load; --clear to reset
agent-browser errors                             # page errors
agent-browser network requests --filter api      # requests, then: network request <id>
agent-browser set viewport 390 844               # phone; back to 1440 900 after
agent-browser set media dark                     # colour scheme
```

`snapshot -i --json` and `get text ... --json` are machine-readable. A snapshot is the check
of record for text and structure; a screenshot is for layout (overflow, alignment) and for
the session folder.

## Context hygiene

- `snapshot -i` over `snapshot`; `-s "<selector>"` to scope; never a full-page snapshot of a
  long page.
- One screenshot per screen, saved under the session folder's `screenshots/`, JPEG when the
  PNG is over 2 MB.
- `console` and `errors` once per route after the interaction, not after every click.
- Close the session before the run ends, also on abort.

## Acceptance check pattern

For each route the goal artifact names: open, wait for the expected text, `snapshot -i`,
assert the elements the plan lists, drive the invalid-input case, read `console` and
`errors` (a new error is a finding to fix test-first), screenshot, then the phone viewport
and one screenshot. Record the commands and their key lines in `REPORT.md` under
"Verification".
