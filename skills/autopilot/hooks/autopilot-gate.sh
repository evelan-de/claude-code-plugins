#!/usr/bin/env bash
# Autopilot Stop-hook gate (TEMPLATE).
# Copied into a project's .claude/hooks/ by `/autopilot init`.
#
# Blocks turn-end while an autopilot run is active AND the project gate is red,
# so the model cannot claim "done" on a red gate. Sentinel-guarded: inert in
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

if OUTPUT="$(bash -lc "$GATE" 2>&1)"; then
  rm -f "$BLOCKS"
  exit 0   # green -> allow the turn to end
fi

# Red -> count consecutive blocks. A stop not caused by a previous block starts over.
count=0
if [ "$ACTIVE" = "true" ] && [ -f "$BLOCKS" ]; then
  count="$(cat "$BLOCKS" 2>/dev/null || echo 0)"
  case "$count" in ''|*[!0-9]*) count=0;; esac
fi
count=$((count + 1))

if [ "$count" -gt "$MAX_BLOCKS" ]; then
  rm -f "$BLOCKS"
  {
    echo "Autopilot gate is still RED after $MAX_BLOCKS consecutive blocks; allowing the stop so the run can hand off or abort."
    echo "--- gate output (tail) ---"
    echo "$OUTPUT" | tail -n 40
  } >&2
  exit 0
fi
echo "$count" >"$BLOCKS"

# Red -> block the stop. exit 2 + stderr is the documented "block" signal.
{
  echo "Autopilot gate is RED - do not end the turn. Fix the root cause, then re-run the gate. (block $count of $MAX_BLOCKS)"
  echo "Do NOT skip tests, weaken assertions, or suppress errors to go green."
  echo "--- gate output (tail) ---"
  echo "$OUTPUT" | tail -n 40
} >&2
exit 2
