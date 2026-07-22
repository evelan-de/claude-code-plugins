---
name: codex-ask
description: >-
  Delegate a self-contained task or question to the locally installed Codex
  CLI (`codex exec`) and report back its answer and any file changes it made.
  This is a manually-invoked skill: use it ONLY when the user explicitly
  routes work to Codex - "frag Codex", "was sagt Codex zu ...", "lass Codex
  das machen", "delegiere das an Codex", "ask Codex", "delegate this to
  Codex", "let Codex handle this". Never auto-trigger: without an explicit
  Codex signal, do the work yourself as usual.
---

# Codex Ask - general delegation to the Codex CLI

Hand a well-briefed, self-contained task to Codex and report back honestly
what came out - including anything it changed on disk. Codex runs without our
conversation history, so the quality of the result is decided by the brief
you write, not by the shell command.

## Preflight and write-safety snapshot

1. **Resolve the binary:** run `codex-cli --version`. The plugin's `bin/` is
   on PATH when installed; in a local checkout use `<repo>/bin/codex-cli`.
   If it exits non-zero, relay its stderr message and stop.
2. **Record the git state** (Codex may write into the workspace):
   `git status --porcelain` and `git rev-parse HEAD`. Keep both for the
   after-run diff.
3. **Warn before running if the tree is already dirty** with our own
   uncommitted work - the user should know Codex edits will land on top of
   it. Wait for their go-ahead in that case.
4. Outside a git repo, add `--skip-git-repo-check` to the invocation and
   skip the git snapshot/diff steps.

If the session's permission setup denies `codex-cli` Bash calls outright, the
fix is a one-time allow rule for `codex-cli` in `.claude/settings.json` - tell
the user that rather than routing around the denial.

## The brief

Never forward a one-liner. Write a structured brief to a temp file. Preserve
the user's intent verbatim - do not invent requirements, constraints, or
scope they did not state.

```text
GOAL
<the user's actual ask, faithfully restated>

CONTEXT
- Relevant files: <paths Codex should read first>
- Stack/conventions that matter here: <only the ones that apply>

CONSTRAINTS
- <what must not change>
- <project rules that bind this task>

EXPECTED RESULT
<what a good answer or change looks like>

DEFINITION OF DONE
<how Codex should verify its own work before finishing>
```

Fill only the lines that matter - a clean short brief beats a padded one.

## Invocation

```bash
BRIEF="$(mktemp /tmp/codex-ask-brief-XXXXXX.txt)"
LAST="$(mktemp /tmp/codex-ask-last-XXXXXX.md)"
# write the brief into "$BRIEF", then:
codex-cli exec \
  --sandbox workspace-write \
  -c approval_policy=on-request \
  -c approvals_reviewer=auto_review \
  -o "$LAST" \
  - < "$BRIEF"
```

- `--sandbox workspace-write`: Codex may edit inside the working directory -
  that is the point of delegating, and an explicit user choice.
- `approval_policy=on-request` + `approvals_reviewer=auto_review`:
  escalations go to Codex's own reviewer agent instead of blocking on a
  human prompt nobody can answer in a headless run.
- **The brief goes in on stdin** (the trailing bare `-`), never as a trailing
  positional - variadic flags such as `--image` swallow a positional prompt
  and Codex then reports "No prompt provided". This failure mode is
  documented in `skills/codex-imagegen/SKILL.md`; do not reintroduce it.
- `-o "$LAST"` captures the clean final message separately from the noisy
  event stream.
- Reference images go in via a separate `--image <FILE>` flag per file;
  `-C <dir>` / `--add-dir <dir>` widen the working scope when the task needs
  it.

A delegated task can run long and foreground Bash is capped at 10 minutes,
so run the command **in the background** (Bash `run_in_background: true`),
redirect combined output to a log file, and wait for the completion
notification. No polling, no side work while it runs.

## Structured output (optional)

When the user wants a machine-readable answer, write a JSON schema to a file
and add `--output-schema <FILE>`; the final message then conforms to it.
Free text is the default - do not add a schema unasked.

## After the run

1. **Relay the answer verbatim:** read `$LAST` and present it unedited.
   Report the log file path alongside it.
2. **Show what Codex touched - never silently:**
   `git status --short` plus `git diff --stat` (and `git diff <pre-run HEAD>
   --stat` if Codex committed anything). If the tree changed, summarize the
   changes and ask the user whether to keep, adjust, or revert. Do not
   commit Codex's changes on your own.
3. If `$LAST` is empty or the run failed, say so plainly with the log
   excerpt - a silent no-op is not an acceptable outcome.

## What not to route here

- Image generation -> `codex-imagegen` skill.
- Reviewing a diff -> `codex-review` skill.
- Anything the user did not explicitly tie to Codex -> just do it yourself.
