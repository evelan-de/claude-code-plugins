---
name: codex-review
description: >-
  Delegate a code review to the locally installed Codex CLI and relay its
  findings verbatim (cross-model review). This is a manually-invoked skill:
  use it ONLY when the user explicitly brings Codex into it - "Codex-Review",
  "lass Codex reviewen", "lass Codex drüberschauen", "zweite Meinung von
  Codex", "Cross-Model-Review", "let Codex review this", or the /codex-review
  command. A generic "review this" / "review my changes" does NOT trigger this
  skill - the normal Claude review flow handles those. Never auto-trigger
  without an explicit Codex signal.
---

# Codex Review - cross-model code review via the Codex CLI

Run OpenAI's Codex as a second, independent reviewer over a local diff and
hand its findings to the user untouched. You are the operator here, not the
reviewer: you pick the right diff, run the tool, strip the noise, and relay.
You do not judge, filter, or fix.

The native `codex review` subcommand is used deliberately - OpenAI maintains
its review prompt and diff-selection logic. Do not rebuild either with
`codex exec`.

## Preflight (in order, abort on first failure)

1. **Resolve the binary:** run `codex-cli --version`. The plugin's `bin/` is
   on PATH when installed; in a local checkout use `<repo>/bin/codex-cli`.
   If it exits non-zero, relay its stderr message to the user and stop -
   nothing below can work.
2. **Confirm a git repo:** `git rev-parse --is-inside-work-tree`. If not,
   tell the user `codex review` needs a repository and stop.
3. **Select the scope and confirm the diff is non-empty** (next section).
   Reviewing an empty diff wastes a model call - abort with an explanation
   instead.

If the session's permission setup denies `codex-cli` Bash calls outright, the
fix is a one-time allow rule for `codex-cli` in `.claude/settings.json` - tell
the user that rather than routing around the denial.

## Scope selection

An explicit user argument always wins (forward it verbatim). Otherwise:

| Situation | Flag |
|---|---|
| Working tree dirty (`git status --porcelain` non-empty) | `--uncommitted` |
| Clean tree on a feature branch | `--base <default branch>` |
| User points at a specific commit | `--commit <SHA>` |

Derive the default branch - never assume it:

```bash
base="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
if [ -z "$base" ]; then git show-ref --verify --quiet refs/remotes/origin/main && base=main; fi
if [ -z "$base" ]; then git show-ref --verify --quiet refs/remotes/origin/master && base=master; fi
```

Non-empty checks per scope:

- `--uncommitted`: `git status --porcelain` has output.
- `--base <b>`: `git diff "<b>"...HEAD --stat` has output.
- `--commit <sha>`: `git show --stat <sha>` shows changed files.

## Execution

Focus instructions from the user ("only the API route", "watch for security
issues") go in as the positional `PROMPT` argument. A model override, only
when the user asks for one, goes through `-c model="<id>"` - there is no
`--model` flag on this subcommand.

A review can run for several minutes and foreground Bash is capped at 10
minutes, so run it **in the background**, log to a file, and wait for the
completion notification. No polling, and do not start other work while it
runs - the review is the task.

```bash
LOG="$(mktemp /tmp/codex-review-XXXXXX.log)"
# example: uncommitted scope with a focus prompt; swap the flag per the table
codex-cli review --uncommitted "only the API route, watch for security issues" > "$LOG" 2>&1
```

(Started via the Bash tool with `run_in_background: true`; the harness
notifies you when it exits.)

## Output handling - raw passthrough

Codex's review text is relayed **verbatim and unjudged**. Do not summarize
it, do not drop findings, do not rank them, and do not argue against them
unprompted. The user asked for a second opinion - deliver it whole.

The only allowed transformation is noise removal. Strip:

- `exec /bin/zsh -lc ...` tool-call blocks and their `succeeded in Nms` /
  exit-status output,
- unrelated sandbox warnings (e.g. xcodebuild / DVTFilePathFSEvents lines).

Everything else stays. Always report the path of the untouched log file
alongside the cleaned output, so the user can read the raw stream.

**Nothing is fixed automatically.** After presenting the findings, ask which
ones to act on and wait for the user's pick.
