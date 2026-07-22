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

A scope flag and a focus prompt are **mutually exclusive** - the CLI rejects
`codex review --base <b> "focus"` with
`error: the argument '--base <BRANCH>' cannot be used with '[PROMPT]'` (same
for `--uncommitted` and `--commit`). So pick one of two forms:

- **Scoped review (default, no custom instructions):** pass the scope flag
  alone. This is the normal path and reviews exactly the diff from the table.

  ```bash
  LOG="$(mktemp /tmp/codex-review-XXXXXX)"
  codex-cli review --base "$base" > "$LOG" 2>&1   # swap the flag per the table
  ```

- **Focused review (custom instructions, no scope flag):** when the user wants
  to steer the review ("only the API route", "watch for security issues"),
  pass the instructions as the `PROMPT` and drop the scope flag. Use `-` to
  feed a multi-line prompt on stdin. Without a scope flag Codex reviews the
  current working changes under your guidance - so this form fits the
  uncommitted case; it cannot target an arbitrary `--base`/`--commit` range.

  ```bash
  LOG="$(mktemp /tmp/codex-review-XXXXXX)"
  printf '%s\n' "only the API route, watch for security issues" \
    | codex-cli review - > "$LOG" 2>&1
  ```

If the user asks for both a specific base/commit range AND focus text, you
cannot pass both - prefer the scoped flag (the explicit range is the harder
requirement) and tell the user the focus note could not be handed to Codex,
or fall back to the focused form if the range is really the uncommitted diff.

A model override, only when the user asks for one, goes through
`-c model="<id>"` - there is no `--model` flag on this subcommand.

**mktemp:** the template must end in the `X` run (`/tmp/codex-review-XXXXXX`).
On macOS/BSD `mktemp`, X's followed by a suffix like `...-XXXXXX.log` are
**not** expanded - you get a literal, non-random filename that collides on the
next run. X's-at-end works on both BSD and GNU.

A review can run for several minutes and foreground Bash is capped at 10
minutes, so run it **in the background** (Bash `run_in_background: true`), log
to a file, and wait for the completion notification. No polling, and do not
start other work while it runs - the review is the task.

## Fallback when Codex is rate-limited or unavailable

Codex can refuse a run because a usage/rate limit is hit, auth expired, or the
service is down. Detect this and **fall back to a normal Claude review** rather
than leaving the user with nothing. Treat the run as failed-to-review when the
process exits non-zero **and** produced no actual review, especially when the
log matches a limit/availability signature (case-insensitive):

`rate limit`, `usage limit`, `quota`, `429`, `too many requests`,
`limit reached`, `reached your usage`, `insufficient_quota`, `unauthorized`,
`401`, `login`, `not found` (binary).

On such a failure:

1. Tell the user plainly that Codex could not review and why (quote the matched
   line), with the log path.
2. **Fall back:** review the same diff yourself as Claude - the normal review
   flow the user would otherwise get. If a dedicated review agent is available
   in the session (e.g. a `code-reviewer` subagent, or in an autopilot run the
   `evelan:autopilot-reviewer`), dispatch that; otherwise review it directly.
   Label the output clearly as the **Claude fallback review**, not Codex's.

Do not silently swallow a Codex failure and do not pretend Codex reviewed when
it did not. A genuine transient (e.g. the benign `failed to renew cache TTL`
line) with a real review still present is **not** a limit - only fall back when
there is no usable review.

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
