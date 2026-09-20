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

# Codex Review

Run `codex review` over a local diff and relay the findings untouched. Use
the native `codex review` subcommand; do not rebuild it with `codex exec`.
Shared procedure (preflight, model, background run, reporting):
`references/codex-common.md` in this folder.

## Preflight

1. Preflight per codex-common.md (binary, git repo). Outside a repo: stop.
2. Select the scope and confirm the diff is non-empty. Empty diff: stop and
   say so.

## Scope

An explicit user argument wins (forward it verbatim). Otherwise:

| Situation | Flag | Non-empty check |
|---|---|---|
| Working tree dirty (`git status --porcelain` non-empty) | `--uncommitted` | `git status --porcelain` has output |
| Clean tree on a feature branch | `--base <default branch>` | `git diff <b>...HEAD --stat` has output |
| User names a commit | `--commit <SHA>` | `git show --stat <sha>` lists files |

Default branch: `git-default-branch` (prints it; exit 1 with a message when
none is found).

## Run

A scope flag and a focus prompt are mutually exclusive; the CLI rejects
`codex review --base <b> "focus"`. Pick one form, log file from
`mktemp /tmp/codex-XXXXXX`, background run:

- Scoped (default): `codex-cli review --base <b> > /tmp/codex-<log> 2>&1`
  (swap the flag per the table).
- Focused (user steers: "only the API route", "watch for security"): pass the
  instructions as the prompt and drop the scope flag. Codex then reviews the
  current working changes; this form cannot target a `--base`/`--commit`
  range. Multi-line prompt: `codex-cli review - < /tmp/codex-<prompt> > /tmp/codex-<log> 2>&1`.

Both a range and focus text requested: use the scoped form and tell the user
the focus note could not be passed; use the focused form only when the range
is the uncommitted diff.

Model override goes through `-c model=<slug>` (`codex review` has no `-m`):
`codex-cli review -c model=<slug> --base <b> > /tmp/codex-<log> 2>&1`. Say so
when the user picks a cheaper model for a security-sensitive review.

## Failure

Non-zero exit and no review text in the log = failed review (rate limit,
quota, auth expired, service down). Then:

1. Tell the user Codex could not review, quote the relevant log line, give
   the log path.
2. Fall back to a Claude review of the same diff (a review agent available in
   the session, else review directly) and label it as the Claude fallback
   review.

A non-zero exit with a real review in the log is not a failure. Never pretend
Codex reviewed when it did not.

Called by another skill (`evelan:autopilot` or `evelan:code-review`): no
fallback. Report the failure in one line and return; the caller records the
skip.

## Output

Relay the review text verbatim: no summary, no dropped or ranked findings, no
unprompted rebuttal. Only the noise stripping from codex-common.md. Report
the log path and the `model:` line.

Nothing is fixed automatically. Ask which findings to act on and wait.
Exception: inside an autopilot run return the findings to the autopilot
skill, which fixes real gaps test-first and rebuts the rest in `REPORT.md`.
