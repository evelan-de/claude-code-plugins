---
name: codex-ask
description: >-
  Delegate a self-contained task or question to the locally installed Codex
  CLI (`codex exec`) and report back its answer and any file changes it made.
  This is a manually-invoked skill: use it ONLY when the user explicitly
  routes work to Codex - "frag Codex", "was sagt Codex zu ...", "lass Codex
  das machen", "delegiere das an Codex", "ask Codex", "delegate this to
  Codex", "let Codex handle this" - or when another Evelan skill explicitly
  routes to it.
---

# Codex Ask

Hand a briefed task to Codex, report its answer and what it changed on disk.
Shared procedure (preflight, model, background run, reporting):
`${CLAUDE_PLUGIN_ROOT}/skills/codex-review/references/codex-common.md`.
Brief template: `references/brief.md` in this folder.

## Before the run

1. Preflight per codex-common.md.
2. `git status --porcelain`. Dirty tree: tell the user Codex's edits will land
   on top of their uncommitted work and wait for their go-ahead.
3. `codex-snapshot save`. Note the printed id.
   Outside a git repo: skip the snapshot and add `--skip-git-repo-check`.
4. Write the brief (references/brief.md) to a file from `mktemp /tmp/codex-XXXXXX`.

## Run

Log file from `mktemp /tmp/codex-XXXXXX`, then in the background:

```bash
codex-cli exec --sandbox workspace-write -c approval_policy=on-request -c approvals_reviewer=auto_review -o /tmp/codex-<last> - < /tmp/codex-<brief> > /tmp/codex-<log> 2>&1
```

- `-o <file>` (a third mktemp path) captures the final message apart from the
  event stream.
- The brief goes in on stdin (trailing `-`), never as a positional argument:
  variadic flags such as `--image` swallow a positional prompt.
- One `--image <FILE>` flag per reference image. `-C <dir>` / `--add-dir <dir>`
  widen the scope when needed.
- Model override: `-m <slug>` from `codex-model resolve`.

## After the run

1. Present the `-o` file unedited, with the log path and the `model:` line.
2. `codex-snapshot diff <id>` (files changed and commits made since the
   snapshot; `codex-snapshot patch <id>` for the full patch). Summarize and
   ask the user whether to keep, adjust or revert. Never commit Codex's
   changes on your own. The snapshot covers git-visible files only; an ignored
   artifact the task was meant to touch is checked separately.
3. Empty final message or failed run: say so with the log excerpt.

## Not here

- Image generation: `codex-imagegen`.
- Reviewing a diff: `codex-review`.
- Anything the user did not tie to Codex: do it yourself.
