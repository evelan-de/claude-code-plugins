#!/usr/bin/env bash
# Autopilot gate-output filter (TEMPLATE).
# Copied into a project's .claude/hooks/ by `/autopilot init`.
#
# Entry points:
#
#   hook  (default; PreToolUse hook for Bash)
#         Reads the hook JSON on stdin. When the project is autopilot-enabled
#         (.claude/autopilot.json exists) and the command is a test/lint/typecheck/build
#         runner, it rewrites the command to `<this script> run <cmdfile>`. The cmdfile keeps
#         the caller's cwd and the original command. Everything else passes through ({}).
#
#   run <cmdfile>
#         Executes the saved command in the saved cwd with pipefail, keeps its exit status,
#         prints a filtered view (RED: failure blocks + summary, GREEN: summary only) and
#         appends one evidence line to .claude/autopilot-gate.log:
#           <utc time> head=<sha> tree=<working-tree hash> exit=<code> cmd=<command>
#
#   tree
#         Prints the working-tree hash used in the log (git write-tree over a temporary
#         index with every tracked and untracked, non-ignored file added, the log itself
#         excluded). A reviewer runs
#         this and compares it with the `tree=` of the log line to know the gate ran on
#         exactly the files it is reviewing, committed or not.
#
# Bypass: put `# raw` anywhere in the command to run it unfiltered.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG="$PROJECT_DIR/.claude/autopilot.json"
LOG="$PROJECT_DIR/.claude/autopilot-gate.log"
SELF="$PROJECT_DIR/.claude/hooks/autopilot-gate-filter.sh"
MAX_LINES="${AUTOPILOT_GATE_MAX_LINES:-200}"

# Package-manager scripts: <pm> [exec|workspace X|--filter X|-r|--recursive|-w X]* [run] <script>
PM_RE='(npx|pnpm|npm|yarn|bun)( (exec|workspace [^ ]+|--filter [^ ]+|-r|--recursive|-w [^ ]+))*( run)? (test|test:[a-z0-9:_-]+|lint|lint:[a-z0-9:_-]+|typecheck|type-check|check-types|format:check|build|build:[a-z0-9:_-]+)([[:space:]]|$)'
# Direct runner binaries (with or without npx/exec prefix)
BIN_RE='((npx|pnpm exec|npm exec|yarn|bunx) )?(vitest|jest|mocha|playwright|tsc|eslint|biome|prettier)([[:space:]]|$)'
PREFIX='(^|[;&|(]|then |do )[[:space:]]*(timeout [0-9]+[smh]? )?'
FAIL_RE='FAIL|✗|×|✘|✕|●|Error|error|ERR!|AssertionError|Expected|expected|Received|received|failed|Failed|TS[0-9]{4}|not ok|✖|Timed out|timed out'

tree_hash() {
  local dir="${1:-$PROJECT_DIR}" idx
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || { echo nogit; return; }
  idx="$(mktemp)"
  rm -f "$idx"
  # Seed from HEAD first: an empty index plus "add -A" skips tracked-but-gitignored files
  # (hooks and settings force-added under an ignored .claude/), so two different trees
  # would hash the same. A repo without a commit has no HEAD; then the seed is skipped.
  ( cd "$dir" \
    && { GIT_INDEX_FILE="$idx" git read-tree HEAD >/dev/null 2>&1 || true; } \
    && GIT_INDEX_FILE="$idx" git -c core.safecrlf=false add -A . >/dev/null 2>&1 \
    && GIT_INDEX_FILE="$idx" git rm -q --cached --ignore-unmatch .claude/autopilot-gate.log >/dev/null 2>&1 \
    && GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null ) | cut -c1-12
  rm -f "$idx"
}

mode="${1:-hook}"

if [ "$mode" = "tree" ]; then
  tree_hash "$PROJECT_DIR"
  exit 0
fi

if [ "$mode" = "run" ]; then
  cmdfile="${2:-}"
  if [ -z "$cmdfile" ] || [ ! -f "$cmdfile" ]; then
    echo "autopilot-gate-filter: missing command file" >&2
    exit 1
  fi
  tmp="$(mktemp -d)"
  raw="$tmp/raw.txt"
  orig="$(sed -n 's/^# CMD: //p' "$cmdfile" | head -n1 | cut -c1-160)"
  bash -o pipefail "$cmdfile" >"$raw" 2>&1
  rc=$?
  total="$(wc -l <"$raw" | tr -d ' ')"
  head_sha="$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo nogit)"
  tree="$(tree_hash "$PROJECT_DIR")"
  mkdir -p "$(dirname "$LOG")"
  printf '%s\thead=%s\ttree=%s\texit=%s\tcmd=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$head_sha" "$tree" "$rc" "$orig" >>"$LOG"

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

[ -f "$CONFIG" ] || { echo '{}'; exit 0; }
command -v jq >/dev/null 2>&1 || { echo '{}'; exit 0; }

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$tool" = "Bash" ] || { echo '{}'; exit 0; }

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || { echo '{}'; exit 0; }

case "$cmd" in
  *"# raw"*|*autopilot-gate-filter*|*autopilot-gate.sh*) echo '{}'; exit 0;;
esac

if ! printf '%s' "$cmd" | grep -q -E "${PREFIX}${PM_RE}" && ! printf '%s' "$cmd" | grep -q -E "${PREFIX}${BIN_RE}"; then
  echo '{}'; exit 0
fi

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PROJECT_DIR"
scratch="$(printf '%s' "$input" | jq -r '.scratchpad_dir // empty' 2>/dev/null)"
[ -n "$scratch" ] && [ -d "$scratch" ] || scratch="$(mktemp -d)"
id="$(printf '%s' "$input" | jq -r '.tool_use_id // empty' 2>/dev/null)"
cmdfile="$scratch/autopilot-gate-${id:-$$}-$(date +%s%N 2>/dev/null || date +%s).sh"
{
  printf 'cd %q || exit 1\n' "$cwd"
  printf '# CMD: %s\n' "$(printf '%s' "$cmd" | head -n1)"
  printf '%s\n' "$cmd"
} >"$cmdfile"

jq -n --arg c "bash \"$SELF\" run \"$cmdfile\"" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: {command: $c}}}'
exit 0
