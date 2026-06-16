#!/usr/bin/env bash
# Autopilot Stop-hook gate (TEMPLATE).
# Copied into a project's .claude/hooks/ by `/autopilot init`.
#
# Blocks turn-end while an autopilot run is active AND the project gate is red,
# so the model cannot claim "done" on a red gate. Sentinel-guarded: inert in
# normal interactive sessions.
set -uo pipefail

cat >/dev/null 2>&1 || true   # drain the JSON Claude Code sends on stdin (unused)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SENTINEL="$PROJECT_DIR/.claude/.autopilot-active"

# Only gate during autopilot runs.
[ -f "$SENTINEL" ] || exit 0

CONFIG="$PROJECT_DIR/.claude/autopilot.json"
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
  exit 0   # green -> allow the turn to end
fi

# Red -> block the stop. exit 2 + stderr is the documented "block" signal.
{
  echo "Autopilot gate is RED — do not end the turn. Fix the root cause, then re-run the gate."
  echo "Do NOT skip tests, weaken assertions, or suppress errors to go green."
  echo "--- gate output (tail) ---"
  echo "$OUTPUT" | tail -n 40
} >&2
exit 2
