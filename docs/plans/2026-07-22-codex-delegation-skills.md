# Codex Delegation Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship two Codex CLI delegation skills (`codex-review`, `codex-ask`), a shared `bin/codex-cli` resolver wrapper, and a `/codex-review` slash command in the evelan plugin, per the approved spec `docs/specs/2026-07-22-codex-delegation-skills-design.md`.

**Architecture:** Both skills are prose (SKILL.md) that instruct Claude how to brief and invoke the Codex CLI - `codex-review` wraps the native `codex review` subcommand with raw-passthrough output, `codex-ask` wraps `codex exec` with a structured stdin brief. The only real code is `bin/codex-cli`, a POSIX shell resolver that finds the Codex binary (PATH, then Codex.app, then `~/.local/bin`) and execs it; the plugin's `bin/` directory lands on PATH when the plugin is installed.

**Tech Stack:** POSIX sh (wrapper), bash (test script, matching `skills/autopilot/hooks/autopilot-gate.test.sh`), Markdown/YAML (skills, command, docs).

## Global Constraints

- The spec `docs/specs/2026-07-22-codex-delegation-skills-design.md` is the source of truth. Do not redesign it.
- Codex binary facts (verified 2026-07-22, do NOT re-verify by running codex - it costs model calls): binary at `/Applications/Codex.app/Contents/Resources/codex`, version `codex-cli 0.144.0-alpha.4`, NOT on PATH. `codex review [PROMPT]` supports `--uncommitted`, `--base <BRANCH>`, `--commit <SHA>`, `--title`, `-c key=value`; it has NO `--json` and NO `--model` (model override via `-c model=...`). `codex exec` supports `--sandbox`, `--json`, `--output-schema <FILE>`, `-o/--output-last-message <FILE>`, `-i/--image`, `-C/--cd`, `--add-dir`, `--skip-git-repo-check`.
- All documentation, skill prose, and commit messages in English. German appears only inside trigger-phrase lists, with proper umlauts (ü, ö, ä, ß).
- Never use the em dash character in any new or edited content - use plain "-".
- Conventional Commits, granular local commits, NO co-author trailer, NO push/PR until the whole feature is done and verified (then Andreas decides).
- Skill triggering is explicit-only for both new skills: a generic "review this" must NOT trigger `codex-review`, and nothing auto-triggers `codex-ask`. The descriptions must state this (mirror the pattern in `skills/codex-imagegen/SKILL.md`).
- Manifest facts (verified against the installed plugin cache): `commands/` is auto-discovered - the `commit-commands` plugin ships a `commands/` dir with no `commands` key in its plugin.json. `bin/` is on PATH when installed (spec-verified). So `.claude-plugin/plugin.json` needs only a version bump, no new keys. `.claude-plugin/marketplace.json` needs no change.
- Verification tooling available on this machine: `python3` with PyYAML (frontmatter checks), `python3 -m json.tool` (manifest check). shellcheck is NOT installed - do not plan on it.

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `bin/codex-cli` | Create | Resolve + exec the real Codex binary; the one piece of real code |
| `bin/codex-cli.test.sh` | Create | Bash tests for the wrapper (colocated, matching the `autopilot-gate.test.sh` precedent; NOT chmod +x, so it never surfaces as a PATH command) |
| `skills/codex-review/SKILL.md` | Create | Review delegation, wraps `codex review`, raw passthrough |
| `skills/codex-ask/SKILL.md` | Create | General delegation, wraps `codex exec` with a stdin brief |
| `commands/codex-review.md` | Create | Thin `/codex-review` slash command, forwards scope args to the skill |
| `skills/autopilot/SKILL.md` | Modify (step 6 only) | One added "On demand" bullet for Codex cross-model review |
| `README.md` | Modify | Document the two new skills in the Skills section |
| `.claude-plugin/plugin.json` | Modify | Version bump 1.2.1 -> 1.3.0 |

All work happens on a feature branch; docs/plans history and CLAUDE.md conventions apply.

---

### Task 0: Feature branch

**Files:** none (git only)

- [ ] **Step 1: Create the branch**

```bash
cd /Users/astraub/dev/tools/claude-code-plugins
git checkout -b feat/codex-delegation-skills
```

- [ ] **Step 2: Verify**

Run: `git branch --show-current`
Expected: `feat/codex-delegation-skills`

---

### Task 1: `bin/codex-cli` resolver wrapper (TDD)

**Files:**
- Create: `bin/codex-cli`
- Test: `bin/codex-cli.test.sh`

**Interfaces:**
- Produces: an executable named `codex-cli` that later tasks' SKILL.md prose invokes as `codex-cli <subcommand> ...`. Resolution order: (1) `codex` on PATH, (2) `$CODEX_CLI_APP_BIN` defaulting to `/Applications/Codex.app/Contents/Resources/codex`, (3) `$HOME/.local/bin/codex`. On failure: exit 127 with a one-line message on stderr containing "Codex CLI not found". All arguments forwarded verbatim via `exec`.
- The `CODEX_CLI_APP_BIN` override exists ONLY so the not-found and precedence paths are testable on a machine where Codex.app is actually installed; it is not documented as a user feature.

- [ ] **Step 1: Write the failing test**

Create `bin/codex-cli.test.sh` with exactly this content (style matches `skills/autopilot/hooks/autopilot-gate.test.sh`):

```bash
#!/usr/bin/env bash
# Tests for bin/codex-cli. Run: bash bin/codex-cli.test.sh
set -uo pipefail

WRAPPER="$(cd "$(dirname "$0")" && pwd)/codex-cli"
PASS=0; FAIL=0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/pathbin" "$tmp/appbin" "$tmp/home/.local/bin" "$tmp/emptyhome"

fake() { # $1 target file  $2 marker
  cat > "$1" <<EOF
#!/bin/sh
echo "$2"
for a in "\$@"; do echo "arg:\$a"; done
EOF
  chmod +x "$1"
}

check() { # $1 desc  $2 want_exit  $3 want_substring  $4 got_exit  $5 got_output
  if [ "$4" -eq "$2" ] && printf '%s' "$5" | grep -qF "$3"; then
    echo "ok   - $1 (exit $4)"; PASS=$((PASS+1))
  else
    echo "FAIL - $1 (want exit $2 + '$3'; got exit $4, output: $5)"; FAIL=$((FAIL+1))
  fi
}

fake "$tmp/pathbin/codex" "FROM_PATH"
fake "$tmp/appbin/codex" "FROM_APP"
fake "$tmp/home/.local/bin/codex" "FROM_HOME"

# 1. PATH wins over app bin and HOME fallback
out="$(PATH="$tmp/pathbin:/usr/bin:/bin" HOME="$tmp/home" \
  CODEX_CLI_APP_BIN="$tmp/appbin/codex" sh "$WRAPPER" exec hello 2>&1)"; got=$?
check "codex on PATH wins" 0 "FROM_PATH" "$got" "$out"

# 2. App bin wins when PATH has no codex
out="$(PATH="/usr/bin:/bin" HOME="$tmp/home" \
  CODEX_CLI_APP_BIN="$tmp/appbin/codex" sh "$WRAPPER" exec hello 2>&1)"; got=$?
check "app bin is second" 0 "FROM_APP" "$got" "$out"

# 3. ~/.local/bin/codex is the last fallback
out="$(PATH="/usr/bin:/bin" HOME="$tmp/home" \
  CODEX_CLI_APP_BIN="$tmp/nonexistent" sh "$WRAPPER" exec hello 2>&1)"; got=$?
check "HOME local bin is third" 0 "FROM_HOME" "$got" "$out"

# 4. Arguments with spaces are forwarded verbatim as single args
out="$(PATH="$tmp/pathbin:/usr/bin:/bin" HOME="$tmp/emptyhome" \
  CODEX_CLI_APP_BIN="$tmp/nonexistent" sh "$WRAPPER" review --base main "two words" 2>&1)"; got=$?
check "args forwarded verbatim" 0 "arg:two words" "$got" "$out"

# 5. Nothing resolvable -> exit 127 + clear message
out="$(PATH="/usr/bin:/bin" HOME="$tmp/emptyhome" \
  CODEX_CLI_APP_BIN="$tmp/nonexistent" sh "$WRAPPER" --version 2>&1)"; got=$?
check "not found -> exit 127 + message" 127 "Codex CLI not found" "$got" "$out"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

Do NOT `chmod +x` the test file - `bin/` is on PATH for installed users, and a non-executable file never surfaces as a command. It is run via `bash bin/codex-cli.test.sh`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash bin/codex-cli.test.sh`
Expected: all 5 cases FAIL (wrapper file does not exist yet; `sh` on a missing file exits 127 but output lacks the markers/message, so cases 1-4 fail; case 5 may accidentally pass on exit code but must fail on the "Codex CLI not found" substring). Final line `PASS=0 FAIL=5`, script exit code 1.

- [ ] **Step 3: Write the wrapper**

Create `bin/codex-cli` with exactly this content:

```sh
#!/bin/sh
# codex-cli - locate the locally installed Codex CLI and exec it.
#
# The Codex desktop app does not put its binary on PATH, and teammates may
# instead have an npm or homebrew install. Skills call this wrapper so they
# never hardcode a machine-specific path. Resolution order:
#   1. `codex` on PATH (npm / homebrew installs)
#   2. /Applications/Codex.app/Contents/Resources/codex (macOS desktop app)
#   3. $HOME/.local/bin/codex
# All arguments are forwarded verbatim.

APP_BIN="${CODEX_CLI_APP_BIN:-/Applications/Codex.app/Contents/Resources/codex}"

if command -v codex >/dev/null 2>&1; then
  CODEX_BIN="$(command -v codex)"
elif [ -x "$APP_BIN" ]; then
  CODEX_BIN="$APP_BIN"
elif [ -x "$HOME/.local/bin/codex" ]; then
  CODEX_BIN="$HOME/.local/bin/codex"
else
  echo "codex-cli: Codex CLI not found - install it (npm/homebrew) or open Codex.app once, then retry." >&2
  exit 127
fi

exec "$CODEX_BIN" "$@"
```

Then make it executable:

```bash
chmod +x bin/codex-cli
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash bin/codex-cli.test.sh`
Expected: `PASS=5 FAIL=0`, exit code 0.

- [ ] **Step 5: Smoke-test against the real binary (this machine only)**

Run: `bin/codex-cli --version`
Expected: `codex-cli 0.144.0-alpha.4`
(`--version` is free - it is not a model call. This step is machine-specific and intentionally NOT part of the test script, which must stay portable.)

Also verify the executable bit survived: `ls -l bin/codex-cli` shows `-rwxr-xr-x` (git will record mode 100755).

- [ ] **Step 6: Commit**

```bash
git add bin/codex-cli bin/codex-cli.test.sh
git commit -m "feat(bin): add codex-cli resolver wrapper with tests"
```

---

### Task 2: `skills/codex-review/SKILL.md`

**Files:**
- Create: `skills/codex-review/SKILL.md`

**Interfaces:**
- Consumes: `codex-cli` (Task 1) as the invocation entry point.
- Produces: the skill the `/codex-review` command (Task 3) and the autopilot bullet (Task 5) reference by name `codex-review` (plugin-qualified: `evelan:codex-review`).

- [ ] **Step 1: Write the skill file**

Create `skills/codex-review/SKILL.md` with exactly this content:

````markdown
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
````

- [ ] **Step 2: Validate the frontmatter**

Run:
```bash
python3 -c "import yaml,re,sys; t=open('skills/codex-review/SKILL.md').read(); m=re.match(r'^---\n(.*?)\n---\n', t, re.S); d=yaml.safe_load(m.group(1)); assert d['name']=='codex-review'; assert 'does NOT trigger' in d['description']; print('frontmatter ok:', d['name'])"
```
Expected: `frontmatter ok: codex-review`

- [ ] **Step 3: Trigger-wording check (observable, not automatable)**

Read the description once more and confirm all of these hold:
- It lists the explicit triggers from the spec: "Codex-Review", "lass Codex reviewen / drüberschauen", "zweite Meinung von Codex", "Cross-Model-Review", `/codex-review`.
- It states plainly that a generic "review this" does NOT trigger it.
- German phrases use proper umlauts, no em dash anywhere in the file:
```bash
grep -c $'—' skills/codex-review/SKILL.md || echo "no em dash - ok"
```
Expected: `0` from grep plus `no em dash - ok` (grep exits 1 on zero matches).

- [ ] **Step 4: Commit**

```bash
git add skills/codex-review/SKILL.md
git commit -m "feat(skills): add codex-review skill (cross-model review via Codex CLI)"
```

---

### Task 3: `commands/codex-review.md` slash command

**Files:**
- Create: `commands/codex-review.md`

**Interfaces:**
- Consumes: the `codex-review` skill by name (Task 2).
- Note: this creates the repo's first `commands/` directory. No plugin.json change is needed - commands are auto-discovered (verified precedent: the installed `commit-commands` plugin ships `commands/` with no `commands` key in its manifest).

- [ ] **Step 1: Write the command file**

Create `commands/codex-review.md` with exactly this content:

```markdown
---
description: "Cross-model code review via the Codex CLI"
argument-hint: "[--uncommitted | --base <branch> | --commit <sha>] [focus instructions]"
---

Invoke the `codex-review` skill from the evelan plugin and follow it exactly.

Arguments to forward verbatim to the skill: $ARGUMENTS

An explicit scope flag in the arguments always wins over the skill's
auto-detection. Any remaining text is the focus prompt for the review.
```

No `allowed-tools` restriction on purpose: the skill needs git, background Bash, and file reads; a narrow allowlist here would break it.

- [ ] **Step 2: Validate the frontmatter**

Run:
```bash
python3 -c "import yaml,re; t=open('commands/codex-review.md').read(); m=re.match(r'^---\n(.*?)\n---\n', t, re.S); d=yaml.safe_load(m.group(1)); assert 'description' in d and 'argument-hint' in d; print('command frontmatter ok')"
```
Expected: `command frontmatter ok`

- [ ] **Step 3: Commit**

```bash
git add commands/codex-review.md
git commit -m "feat(commands): add /codex-review command"
```

---

### Task 4: `skills/codex-ask/SKILL.md`

**Files:**
- Create: `skills/codex-ask/SKILL.md`

**Interfaces:**
- Consumes: `codex-cli` (Task 1).
- Produces: standalone skill; no command file (the spec says the skill trigger is sufficient).

- [ ] **Step 1: Write the skill file**

Create `skills/codex-ask/SKILL.md` with exactly this content:

````markdown
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
````

- [ ] **Step 2: Validate the frontmatter**

Run:
```bash
python3 -c "import yaml,re; t=open('skills/codex-ask/SKILL.md').read(); m=re.match(r'^---\n(.*?)\n---\n', t, re.S); d=yaml.safe_load(m.group(1)); assert d['name']=='codex-ask'; assert 'Never auto-trigger' in d['description']; print('frontmatter ok:', d['name'])"
```
Expected: `frontmatter ok: codex-ask`

- [ ] **Step 3: Spec-fidelity check (observable)**

Confirm against the spec, reading the file once more:
- Invocation matches the spec exactly: `--sandbox workspace-write`, `-c approval_policy=on-request`, `-c approvals_reviewer=auto_review`, `-o <file>`, stdin via bare `-`.
- The brief template covers: goal, relevant files/context, constraints, expected result, definition of done.
- Write-safety covers: pre-run git snapshot, dirty-tree warning, post-run `git status --short` + diffstat.
- `--output-schema` has its short section; free text is stated as default.
- No em dash: `grep -c $'—' skills/codex-ask/SKILL.md || echo "no em dash - ok"` -> `no em dash - ok`.

- [ ] **Step 4: Commit**

```bash
git add skills/codex-ask/SKILL.md
git commit -m "feat(skills): add codex-ask skill (general Codex CLI delegation)"
```

---

### Task 5: Autopilot integration (one bullet)

**Files:**
- Modify: `skills/autopilot/SKILL.md` (section "### 6. Review (fresh context, hybrid depth)", currently lines 147-155)

**Interfaces:**
- Consumes: the `evelan:codex-review` skill name from Task 2.

- [ ] **Step 1: Apply the exact edit**

In `skills/autopilot/SKILL.md`, insert one bullet between the existing "On demand" bullet and the "Max 2 review cycles" line. Exact Edit:

old_string:
```
  record nice-to-have in `REPORT.md` with rationale.
- Max 2 review cycles; unresolved real gaps → mark the package `[!]`, log it, move on.
```

new_string:
```
  record nice-to-have in `REPORT.md` with rationale.
- **On demand (cross-model):** if the prompt asks for it ("mit Codex reviewen", "Cross-Model-Review"),
  additionally run a Codex review via the `evelan:codex-review` skill (`codex review --base <base>`);
  never on a default run, and a missing Codex CLI simply means the option is unavailable.
- Max 2 review cycles; unresolved real gaps → mark the package `[!]`, log it, move on.
```

(The `→` in the surrounding context lines is pre-existing text and must be matched as-is; the added bullet itself uses only plain "-".)

- [ ] **Step 2: Verify the edit is minimal**

Run: `git diff --stat skills/autopilot/SKILL.md`
Expected: exactly one file, `3 insertions(+)`, 0 deletions. Then `git diff skills/autopilot/SKILL.md` shows only the new bullet inside step 6.

- [ ] **Step 3: Commit**

```bash
git add skills/autopilot/SKILL.md
git commit -m "feat(autopilot): offer Codex cross-model review on demand"
```

---

### Task 6: README + version bump

**Files:**
- Modify: `README.md` (Skills section - append two new skill entries after "### reflect-on-changes")
- Modify: `.claude-plugin/plugin.json` (version 1.2.1 -> 1.3.0)

- [ ] **Step 1: Append the README sections**

Append to the end of `README.md` (after the reflect-on-changes section) exactly:

```markdown

### codex-review

Cross-model code review: delegates a review of your local diff to the Codex CLI (`codex review`) and relays its findings verbatim - no summarizing, no filtering, no auto-fixing. Useful as an independent second opinion next to the normal Claude review flow, which stays untouched.

**Features:**
- Scope auto-detection: dirty tree -> `--uncommitted`, clean feature branch -> `--base <default branch>`, or a specific `--commit <sha>` - an explicit argument always wins
- Preflight guards: Codex binary resolution, git-repo check, empty-diff abort (no wasted model calls)
- Runs in the background with a log file (reviews can take minutes); the untouched log path is always reported
- Output is passed through raw - only tool-call noise and sandbox warnings are stripped
- Never fixes anything on its own; asks which findings to act on

**Usage:** `/codex-review [--uncommitted | --base <branch> | --commit <sha>] [focus instructions]`

**Trigger phrases:** "Codex-Review", "lass Codex reviewen", "lass Codex drüberschauen", "zweite Meinung von Codex", "Cross-Model-Review". A generic "review this" does NOT trigger it.

### codex-ask

General-purpose delegation to the Codex CLI (`codex exec`): writes a structured brief (goal, context, constraints, expected result, definition of done), runs Codex in the `workspace-write` sandbox with auto-review escalations, and reports back the answer plus everything Codex changed on disk.

**Features:**
- Structured stdin brief - Codex has no access to the conversation, so the skill briefs it properly instead of forwarding a one-liner
- Write-safety: git state recorded before the run, dirty-tree warning, post-run `git status` + diffstat so changes are never silent
- Clean final answer captured via `-o` and relayed verbatim
- Optional `--output-schema` for structured JSON answers
- Never auto-triggered - only when you explicitly route work to Codex

**Trigger phrases:** "frag Codex", "was sagt Codex zu ...", "lass Codex das machen", "delegiere das an Codex", "ask Codex", "delegate this to Codex"
```

Note: the plugin's `bin/codex-cli` resolver is an internal helper shared by both skills (and needed because Codex.app does not put its binary on PATH); it does not get its own README section.

- [ ] **Step 2: Bump the plugin version**

In `.claude-plugin/plugin.json`, change `"version": "1.2.1"` to `"version": "1.3.0"` (minor bump: new features, no breaking change - matches the repo's `chore(plugin): bump version` convention).

- [ ] **Step 3: Validate**

Run: `python3 -m json.tool .claude-plugin/plugin.json`
Expected: pretty-printed JSON, exit 0, `"version": "1.3.0"`.

Run: `grep -c $'—' README.md || echo "no new em dash"` - the pre-existing README sections already use "—"; confirm the two NEW sections do not add any (check `git diff README.md` for `—` in added lines: `git diff README.md | grep '^+' | grep -c $'—'` -> expected `0` (grep exits 1)).

- [ ] **Step 4: Commit (two granular commits, matching repo convention)**

```bash
git add README.md
git commit -m "docs(readme): document codex-review and codex-ask skills"
git add .claude-plugin/plugin.json
git commit -m "chore(plugin): bump version to 1.3.0"
```

---

### Task 7: End-to-end verification pass

**Files:** none (verification only)

- [ ] **Step 1: Full test + lint sweep**

```bash
bash bin/codex-cli.test.sh
bash skills/autopilot/hooks/autopilot-gate.test.sh
python3 -m json.tool .claude-plugin/plugin.json > /dev/null && echo "plugin.json ok"
python3 -m json.tool .claude-plugin/marketplace.json > /dev/null && echo "marketplace.json ok"
```
Expected: `PASS=5 FAIL=0`, `PASS=4 FAIL=0`, `plugin.json ok`, `marketplace.json ok`.

- [ ] **Step 2: Frontmatter sweep over every skill**

```bash
for f in skills/*/SKILL.md; do python3 -c "import yaml,re,sys; t=open(sys.argv[1]).read(); m=re.match(r'^---\n(.*?)\n---\n', t, re.S); d=yaml.safe_load(m.group(1)); print('ok', d['name'])" "$f"; done
```
Expected: `ok` for all 8 skills including `codex-review` and `codex-ask`, no traceback.

- [ ] **Step 3: Live plugin smoke test (interactive, Andreas or executor with a fresh session)**

Launch a fresh Claude Code session with the local plugin:
```bash
claude --plugin-dir /Users/astraub/dev/tools/claude-code-plugins
```
Checks:
- `/codex-review` appears in the command list and `/help`.
- Prompt "zweite Meinung von Codex zu meinen Änderungen" -> the codex-review skill is picked up.
- Prompt "review my changes" (no Codex mention) -> the skill is NOT invoked; normal review flow runs.
- Prompt "frag Codex, was es von diesem Repo hält" -> codex-ask triggers, and its preflight (`codex-cli --version`) resolves the Codex.app binary.
This is the "skill triggers on intended phrases and not on generic ones" check - it cannot be scripted; observe it.

- [ ] **Step 4: Confirm git state - and stop**

```bash
git log --oneline main..HEAD
git status --short
```
Expected: 7 commits on `feat/codex-delegation-skills` (wrapper, codex-review skill, command, codex-ask skill, autopilot bullet, README, version bump), clean tree.

**Do NOT push and do NOT open a PR.** Per repo policy the feature is pushed only when complete and verified, and Andreas decides on the PR/merge (repo history has both direct-to-main and PR flows).

---

## Deliberately out of scope (per spec, YAGNI)

- No Codex MCP server integration, no findings cache, no auto-fix loop, no hand-written review prompt, no JSON parsing of review output.
- No slash command for codex-ask (spec: skill trigger is sufficient).
- No changes to `.claude-plugin/marketplace.json` and no `commands`/`bin` keys in plugin.json (auto-discovery verified).

## Open questions for Andreas

1. **Version bump:** 1.3.0 (minor) is assumed for the three new user-facing pieces. OK, or do you want a different number?
2. **README gap (pre-existing):** the README Skills section is missing entries for the existing `preview` and `codex-imagegen` skills. This plan only adds the two new skills. Should the missing entries be added in a separate follow-up commit, or folded into Task 6?
3. **Merge path:** the branch stays local per policy. When done, do you want a PR (like autopilot/reflect-on-changes) or a direct merge to main (like preview/port-from-repo)?
