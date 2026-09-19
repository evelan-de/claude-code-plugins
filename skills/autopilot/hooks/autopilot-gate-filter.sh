#!/usr/bin/env bash
# Autopilot gate-output filter (TEMPLATE).
# Copied into a project's .claude/hooks/ by `/autopilot init`.
#
# Two entry points:
#
#   hook  (default, called by Claude Code as a PreToolUse hook for Bash)
#         Reads the hook JSON on stdin. When the project is autopilot-enabled
#         (.claude/autopilot.json exists) and the command is a test/lint/typecheck/build
#         runner, it rewrites the command to `<this script> run <cmdfile>` so the model sees
#         only failures plus the summary instead of the full runner output. Everything else
#         passes through untouched ({}).
#
#   run <cmdfile>
#         Executes the saved command with pipefail, keeps its exit status, prints a filtered
#         view (RED: failure blocks + summary, GREEN: summary only) and appends one evidence
#         line to .claude/autopilot-gate.log (timestamp, HEAD, tree state, exit code, command).
#         The log is written by this hook, never by the model, so a reviewer may trust it.
#
# Bypass: put `# raw` anywhere in the command to run it unfiltered.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG="$PROJECT_DIR/.claude/autopilot.json"
LOG="$PROJECT_DIR/.claude/autopilot-gate.log"
SELF="$PROJECT_DIR/.claude/hooks/autopilot-gate-filter.sh"
MAX_LINES="${AUTOPILOT_GATE_MAX_LINES:-200}"

# Runner detection: package-manager scripts and direct runner invocations.
RUNNER_RE='(^|[;&|(]|then |do )[[:space:]]*(timeout [0-9]+[smh]? )?(npx |pnpm |npm |yarn |bun |pnpm exec |npm exec )?(run )?(--filter [^ ]+ )?(-w [^ ]+ )?(vitest|jest|mocha|playwright|tsc|eslint|biome|prettier|test|test:[a-z0-9:-]+|lint|lint:[a-z0-9:-]+|typecheck|type-check|check-types|format:check|build)([[:space:]]|$)'
FAIL_RE='FAIL|✗|×|✘|✕|●|Error|error|ERR!|AssertionError|Expected|expected|Received|received|failed|Failed|TS[0-9]{4}|not ok|✖|Timed out|timed out'

mode="${1:-hook}"

if [ "$mode" = "run" ]; then
  cmdfile="${2:-}"
  if [ -z "$cmdfile" ] || [ ! -f "$cmdfile" ]; then
    echo "autopilot-gate-filter: missing command file" >&2
    exit 1
  fi
  tmp="$(mktemp -d)"
  raw="$tmp/raw.txt"
  cd "$PROJECT_DIR" 2>/dev/null || true
  bash -o pipefail "$cmdfile" >"$raw" 2>&1
  rc=$?
  total="$(wc -l <"$raw" | tr -d ' ')"
  head_sha="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then tree="dirty"; else tree="clean"; fi
  first_line="$(head -n1 "$cmdfile" | cut -c1-160)"
  mkdir -p "$(dirname "$LOG")"
  printf '%s\thead=%s\ttree=%s\texit=%s\tcmd=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$head_sha" "$tree" "$rc" "$first_line" >>"$LOG"

  if [ "$rc" -eq 0 ]; then
    echo "GATE GREEN (exit 0) · $total lines, showing summary only · full output: $raw"
    tail -n 12 "$raw"
  else
    echo "GATE RED (exit $rc) · $total lines, showing failures + summary · full output: $raw"
    echo "--- failures ---"
    grep -n -E -B2 -A8 "$FAIL_RE" "$raw" | head -n "$MAX_LINES"
    echo "--- summary (tail) ---"
    tail -n 15 "$raw"
  fi
  exit "$rc"
fi

# ---- hook mode -------------------------------------------------------------------------
input="$(cat 2>/dev/null || true)"

# Only in autopilot-enabled projects, and only with jq available.
[ -f "$CONFIG" ] || { echo '{}'; exit 0; }
command -v jq >/dev/null 2>&1 || { echo '{}'; exit 0; }

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$tool" = "Bash" ] || { echo '{}'; exit 0; }

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || { echo '{}'; exit 0; }

# Bypass and re-entrancy guards.
case "$cmd" in
  *"# raw"*|*autopilot-gate-filter*|*autopilot-gate.sh*) echo '{}'; exit 0;;
esac

printf '%s' "$cmd" | grep -q -E "$RUNNER_RE" || { echo '{}'; exit 0; }

scratch="$(printf '%s' "$input" | jq -r '.scratchpad_dir // empty' 2>/dev/null)"
[ -n "$scratch" ] && [ -d "$scratch" ] || scratch="$(mktemp -d)"
id="$(printf '%s' "$input" | jq -r '.tool_use_id // empty' 2>/dev/null)"
cmdfile="$scratch/autopilot-gate-${id:-$$}-$(date +%s%N 2>/dev/null || date +%s).sh"
printf '%s\n' "$cmd" >"$cmdfile"

jq -n --arg c "bash \"$SELF\" run \"$cmdfile\"" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: {command: $c}}}'
exit 0
