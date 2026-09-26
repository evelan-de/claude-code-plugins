#!/usr/bin/env bash
# Autopilot Stop-hook gate (TEMPLATE).
# Copied into a project's .claude/hooks/ by `autopilot-hooks install` (from /autopilot init and the runner).
# autopilot-hook-version: 2   (raise it with every change to this file)
#
# Blocks turn-end while an autopilot run is active AND (a) the newest session has
# neither REPORT.md nor HANDOFF.md (in a headless run, ending the turn ends the
# process: nothing may be "waited for" across a turn) or (b) the project gate is
# red, so the model cannot claim "done" on a red gate. Sentinel-guarded: inert in
# normal interactive sessions.
#
# Yield rule: consecutive blocks are counted in .claude/.autopilot-gate-blocks
# (a stop with stop_hook_active=false starts a new count). After the third
# consecutive block the stop is allowed with the reason on stderr, so a run that
# cannot go green does not loop forever. A green gate resets the counter.
# On abort, remove the counter file together with the sentinel (.autopilot-active).
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SENTINEL="$PROJECT_DIR/.claude/.autopilot-active"
BLOCKS="$PROJECT_DIR/.claude/.autopilot-gate-blocks"
MAX_BLOCKS=3

# Only gate during autopilot runs.
[ -f "$SENTINEL" ] || exit 0

if command -v jq >/dev/null 2>&1; then
  ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)"
else
  # Exact spellings only; a wider pattern would match any later "true" in the JSON.
  case "$INPUT" in
    *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) ACTIVE=true;;
    *) ACTIVE=false;;
  esac
fi

CONFIG="$PROJECT_DIR/.claude/autopilot.json"
# Last-resort fallback ONLY: /autopilot init always writes the PM-correct gate to
# autopilot.json; this npm default applies just when that file is missing or unreadable.
DEFAULT_GATE="npm run typecheck && npm run lint && npm test"
GATE=""
if [ -f "$CONFIG" ]; then
  if command -v jq >/dev/null 2>&1; then
    GATE="$(jq -r '.gate // empty' "$CONFIG" 2>/dev/null)"
  else
    GATE="$(sed -n 's/.*"gate"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$CONFIG" | head -n1)"
  fi
fi
GATE="${GATE:-$DEFAULT_GATE}"

cd "$PROJECT_DIR" || exit 0

# count_block: consecutive-block counter shared by both checks. Sets $count; returns 1
# when the yield limit is exceeded (caller allows the stop).
count_block() {
  count=0
  if [ "$ACTIVE" = "true" ] && [ -f "$BLOCKS" ]; then
    count="$(cat "$BLOCKS" 2>/dev/null || echo 0)"
    case "$count" in ''|*[!0-9]*) count=0;; esac
  fi
  count=$((count + 1))
  if [ "$count" -gt "$MAX_BLOCKS" ]; then rm -f "$BLOCKS"; return 1; fi
  echo "$count" >"$BLOCKS"
  return 0
}

# (a) The run's artifacts: the newest session folder (by PLAN.md) must hold REPORT.md
# (done or blocked) or HANDOFF.md before the turn may end. Cheap, runs before the gate.
SESSION_DIR=""
if [ -d "$PROJECT_DIR/docs/autopilot/sessions" ]; then
  SESSION_DIR="$(ls -t "$PROJECT_DIR"/docs/autopilot/sessions/*/PLAN.md 2>/dev/null | head -n 1)"
  SESSION_DIR="${SESSION_DIR%/PLAN.md}"
fi
if [ -n "$SESSION_DIR" ] && [ ! -f "$SESSION_DIR/REPORT.md" ] && [ ! -f "$SESSION_DIR/HANDOFF.md" ]; then
  if count_block; then
    {
      echo "Autopilot run is not finished - do not end the turn. $(basename "$SESSION_DIR") has neither REPORT.md nor HANDOFF.md. (block $count of $MAX_BLOCKS)"
      echo "In a headless run, ending the turn ends the process: nothing runs on after it, no notification arrives. Run what you are waiting for in the foreground (a review, a CI watch, a server check), then continue with the skill's steps until REPORT.md exists; or hand off with HANDOFF.md."
    } >&2
    exit 2
  fi
  echo "Autopilot run still has no REPORT.md or HANDOFF.md after $MAX_BLOCKS consecutive blocks; allowing the stop (the runner will restart or report it)." >&2
  exit 0
fi

# (b) A done report in a project with the Claude review workflow must say what the review
# bot returned ("## Review bot" section): the loop in the skill is easy to skip, this is not.
if [ -n "$SESSION_DIR" ] && [ -f "$SESSION_DIR/REPORT.md" ] \
   && [ -f "$PROJECT_DIR/.github/workflows/claude-code-review.yml" ] \
   && head -n 1 "$SESSION_DIR/REPORT.md" | grep -q '^Status: done' \
   && ! grep -q '^## Review bot' "$SESSION_DIR/REPORT.md"; then
  if count_block; then
    {
      echo "REPORT.md says done but has no '## Review bot' section, and this project runs the Claude review workflow on every PR. (block $count of $MAX_BLOCKS)"
      echo "Wait for the review bot on the PR as the skill describes (poll in the foreground, up to 40 minutes), fix or rebut its findings, then add '## Review bot' to REPORT.md with the outcome (findings and what happened to them, 'No issues found', skipped/incomplete notice, or size notice). Commit and push before ending the turn."
    } >&2
    exit 2
  fi
  echo "REPORT.md still lacks a '## Review bot' section after $MAX_BLOCKS consecutive blocks; allowing the stop." >&2
  exit 0
fi

if OUTPUT="$(bash -lc "$GATE" 2>&1)"; then
  rm -f "$BLOCKS"
  exit 0   # green -> allow the turn to end
fi

# Red -> count consecutive blocks. A stop not caused by a previous block starts over.
if ! count_block; then
  {
    echo "Autopilot gate is still RED after $MAX_BLOCKS consecutive blocks; allowing the stop so the run can hand off or abort."
    echo "--- gate output (tail) ---"
    echo "$OUTPUT" | tail -n 40
  } >&2
  exit 0
fi

# Red -> block the stop. exit 2 + stderr is the documented "block" signal.
{
  echo "Autopilot gate is RED - do not end the turn. Fix the root cause, then re-run the gate. (block $count of $MAX_BLOCKS)"
  echo "Do NOT skip tests, weaken assertions, or suppress errors to go green."
  echo "--- gate output (tail) ---"
  echo "$OUTPUT" | tail -n 40
} >&2
exit 2
