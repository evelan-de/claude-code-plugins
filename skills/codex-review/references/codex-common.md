# Codex CLI: shared procedure

Used by `codex-ask`, `codex-review` and `codex-imagegen`. Every command below is
one Bash call; note the printed values and reuse them literally in later calls.

## Preflight

1. `codex-cli --version`. The plugin's `bin/` is on PATH when installed; in a
   local checkout use `<repo>/bin/codex-cli`. Non-zero exit: relay its stderr
   and stop.
2. `git rev-parse --is-inside-work-tree`. Outside a repo: `codex review` cannot
   run (stop); `codex exec` needs `--skip-git-repo-check`.

If the session's permission setup denies `codex-cli` Bash calls, tell the user
to add a one-time allow rule for `codex-cli` in `.claude/settings.json`. Do not
route around the denial.

## Model

Default: pass no model. Codex uses its own default, the strongest coding model
in its catalog. Override only when the user names a model ("nutze Astra", "mit
Sol", "nutze Luna", "das billige Modell").

Resolve the name first, never type a slug from memory:

```bash
codex-model resolve astra
```

| Exit | Meaning | Action |
|---|---|---|
| 0 | resolved (or catalog unreadable, passed through with a warning) | use the printed slug |
| 2 | unknown name; stderr lists the real ones | stop, show the list, ask which |
| 3 | ambiguous short name | stop, ask for the full slug |

Pass the slug as `-m <slug>` to `codex exec` and as `-c model=<slug>` to
`codex review` (it has no `-m` flag). `codex-model list` shows what is
available; a model missing from the list may mean the CLI is outdated
(compare `codex-cli --version` with the latest release).

## Running

1. Create the log file: `mktemp /tmp/codex-XXXXXX` (X's at the end; on
   macOS a suffix after the X's is not expanded). Note the printed path.
2. Run the Codex command with `> <log> 2>&1` appended.
   - Interactive session: in the background (Bash `run_in_background: true`), then wait
     for the completion notification. No polling, no other work meanwhile.
   - Inside an autopilot run (`.claude/.autopilot-active` exists): in the FOREGROUND with
     Bash `timeout: 600000`. A headless run has no notifications: ending the turn to wait
     ends the process. If the command hits the 10-minute cap, run it once more; a second
     cap is "Codex unavailable" (report the skip).

## Reporting

- Strip only noise from the output: `exec /bin/zsh -lc ...` tool-call blocks
  with their `succeeded in Nms` / exit-status lines, and unrelated sandbox
  warnings (xcodebuild, DVTFilePathFSEvents). Everything else stays.
- Report the log path.
- Report which model ran, taken from the `model:` line in the log header, not
  from the model's own statements.
