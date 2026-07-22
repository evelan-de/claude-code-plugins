# Codex Delegation Skills - Design

Date: 2026-07-22
Status: Approved (design), not implemented

## Goal

Let Claude Code delegate work to the locally installed **Codex CLI**: a focused code-review
delegation (`codex-review`) and a general-purpose delegation (`codex-ask`). Both ship in the
existing `evelan` plugin.

## Environment facts (verified 2026-07-22 on Andreas' machine)

- Codex is installed as **Codex.app**, not via npm. The binary lives at
  `/Applications/Codex.app/Contents/Resources/codex` and is **not on `PATH`**.
  Version: `codex-cli 0.144.0-alpha.4`.
- The plugin's own `bin/` directory **is** on `PATH` when the plugin is installed
  (`~/.claude/plugins/cache/evelan-plugins/evelan/<version>/bin`).
- `codex review [PROMPT]` exists as a native, non-interactive subcommand with
  `--uncommitted`, `--base <BRANCH>`, `--commit <SHA>`, `--title`, `-c key=value`.
  It has **no** `--json` and no `--model` flag (model override goes through `-c model=...`).
- `codex exec` supports `--sandbox`, `--json`, `--output-schema <FILE>`,
  `-o/--output-last-message <FILE>`, `-i/--image`, `-C/--cd`, `--add-dir`.
- A probe run (`codex review --commit HEAD` in this repo) succeeded and printed a plain-text
  stream: interleaved `exec /bin/zsh -lc ...` tool-call blocks (plus unrelated xcodebuild
  warnings from the sandbox) followed by the final review verdict.

## Deliverables

```
skills/codex-review/SKILL.md     # review delegation, wraps `codex review`
skills/codex-ask/SKILL.md        # general delegation, wraps `codex exec`
bin/codex-cli                    # PATH resolver, execs the real binary
commands/codex-review.md         # /codex-review [--uncommitted | --base X | --commit SHA]
```

Plus a one-line addition to `skills/autopilot/SKILL.md` (step 6, "On demand" list).

## Component: `bin/codex-cli`

A small POSIX shell wrapper. Resolution order:

1. `command -v codex` (npm / homebrew installs)
2. `/Applications/Codex.app/Contents/Resources/codex` (macOS desktop app)
3. `$HOME/.local/bin/codex`

If none resolves: exit non-zero with a clear message ("Codex CLI not found - install it or open
Codex.app once") so the calling skill can stop instead of producing a confusing failure.
All arguments are forwarded verbatim (`exec "$CODEX_BIN" "$@"`).

Rationale: hardcoding the Codex.app path in two SKILL.md files would break for teammates with an
npm install, and both skills need the same lookup.

## Component: `skills/codex-review/SKILL.md`

### Triggering

Explicit only: "Codex-Review", "lass Codex reviewen / drüberschauen", "zweite Meinung von Codex",
"Cross-Model-Review", `/codex-review`. The description must state that a generic "review this"
does **not** trigger it, so the normal Claude review flow stays untouched.

### Scope selection

An explicit argument always wins. Otherwise:

| Situation | Flag |
|---|---|
| Working tree dirty | `--uncommitted` |
| Clean tree on a feature branch | `--base <default branch>` |
| User points at a specific commit | `--commit <SHA>` |

The default branch is derived from `origin/HEAD` (`git symbolic-ref refs/remotes/origin/HEAD`),
with a fallback probe for `main`/`master` - never assumed.

### Preflight

1. Resolve the binary via `codex-cli` (abort with the resolver's message if missing).
2. Confirm the cwd is a git repository.
3. **Confirm the selected diff is non-empty** (`git diff --stat` / `git diff <base>...HEAD --stat`).
   An empty diff aborts with an explanation instead of spending a model call.

Focus instructions from the user ("only the API route", "watch for security issues") are passed as
the positional `PROMPT` argument.

### Execution

A review can run for several minutes; foreground Bash is capped at 10 minutes. The skill therefore
starts the run **in the background**, redirects combined output to a log file, and waits for the
completion notification. No polling, no continuing on other work while it runs.

Model override, when the user asks for one, uses `-c model="<id>"`.

### Output handling - raw passthrough

Codex' review text is relayed **verbatim and unjudged**. Claude does not summarize it, does not
drop findings, does not rank them, and does not argue against them unprompted.

The only transformation is noise removal: the `exec /bin/zsh -lc ...` tool-call blocks, their
`succeeded in Nms` output, and unrelated sandbox warnings (e.g. xcodebuild/DVTFilePathFSEvents
lines) are stripped. The full untouched log file path is reported alongside the output.

**Nothing is fixed automatically.** After presenting the findings the skill asks which ones to act
on.

## Component: `skills/codex-ask/SKILL.md`

### Triggering

Explicit only: "frag Codex", "lass Codex das machen", "was sagt Codex zu ...", "delegiere das an
Codex". Never auto-triggered.

### Invocation

```bash
codex-cli exec \
  --sandbox workspace-write \
  -c approval_policy=on-request \
  -c approvals_reviewer=auto_review \
  -o <last-message-file> \
  - < <brief-file>
```

- `workspace-write`: Codex may edit inside the working directory (explicit user choice).
- `approval_policy=on-request` + `approvals_reviewer=auto_review`: escalations go to Codex' own
  reviewer agent instead of blocking on a human prompt that nobody can answer in a headless run.
- The brief is passed **on stdin** (trailing bare `-`), never as a trailing positional - a
  positional prompt gets swallowed by variadic flags such as `--image`. This failure mode is
  already documented in `skills/codex-imagegen/SKILL.md`.
- `-o <file>` captures the clean final message separately from the event stream.

### The brief

Codex runs without our conversation history, so the skill writes a structured brief rather than
forwarding a one-liner: goal, relevant files/context, constraints (stack conventions, what must
not change), expected result, and a definition of done. The user's intent is preserved verbatim;
no invented requirements.

### Write-safety

Because Codex may write:

1. Record the git state before the call (`git status --porcelain`, current HEAD).
2. Warn the user beforehand if the tree already carries uncommitted work of our own.
3. After the run, show `git status --short` plus a diffstat of what Codex touched, so the change
   is never silent.

A short section covers `--output-schema <FILE>` for cases where a structured (JSON) answer is
wanted; free text is the default.

## Component: `commands/codex-review.md`

Thin slash command that invokes the `codex-review` skill and forwards an optional scope argument
(`--uncommitted`, `--base <branch>`, `--commit <sha>`). `codex-ask` needs no command; its skill
trigger is sufficient.

## Autopilot integration

`skills/autopilot/SKILL.md`, step 6 ("Review"), **On demand** bullet gains one item: run a Codex
cross-model review (`codex review --base <base>`) when the prompt asks for it ("mit Codex
reviewen", "Cross-Model-Review"). Behaviour is otherwise unchanged - no Codex call on a default
autopilot run, and a missing Codex CLI simply means the option is unavailable.

## Explicitly out of scope (YAGNI)

- No Codex MCP server integration (`codex mcp-server`).
- No findings cache or history.
- No auto-fix loop for review findings.
- No hand-written review prompt template - the native `codex review` prompt is used.
- No JSON parsing of review output (the subcommand offers none, and raw passthrough is wanted).

## Key decision record

**Native `codex review` vs. `codex exec` with a custom review brief.** Chosen: native. OpenAI
maintains the review prompt and the diff selection logic (`--base`, `--commit`, `--uncommitted`),
which is exactly the part that is easy to get subtly wrong. The cost is losing `--json` /
`--output-schema`, which is irrelevant under raw passthrough. `codex-ask` uses `codex exec`
precisely because those flags matter there.
