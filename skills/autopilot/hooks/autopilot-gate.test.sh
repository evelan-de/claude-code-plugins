#!/usr/bin/env bash
# Tests for autopilot-gate.sh. Run: bash skills/autopilot/hooks/autopilot-gate.test.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/autopilot-gate.sh"
PASS=0; FAIL=0

run_case() {
  # $1 desc  $2 expected_exit  $3 sentinel(yes/no)  $4 gate_command(or "")
  local desc="$1" want="$2" sentinel="$3" gate="$4"
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/.claude"
  [ "$sentinel" = "yes" ] && touch "$tmp/.claude/.autopilot-active"
  if [ -n "$gate" ]; then
    printf '{\n  "gate": "%s"\n}\n' "$gate" > "$tmp/.claude/autopilot.json"
  fi
  local err; err="$tmp/stderr.txt"
  CLAUDE_PROJECT_DIR="$tmp" bash "$HOOK" </dev/null 2>"$err"
  local got=$?
  if [ "$got" -eq "$want" ]; then
    echo "ok   - $desc (exit $got)"; PASS=$((PASS+1))
  else
    echo "FAIL - $desc (want $want, got $got)"; FAIL=$((FAIL+1))
  fi
  LAST_ERR="$(cat "$err")"
  rm -rf "$tmp"
}

run_case "no sentinel -> allow (exit 0) even with red gate" 0 no "false"
run_case "sentinel + green gate -> allow (exit 0)" 0 yes "true"
run_case "sentinel + red gate -> block (exit 2)" 2 yes "false"
case "$LAST_ERR" in
  *RED*) echo "ok   - red gate prints RED to stderr"; PASS=$((PASS+1));;
  *) echo "FAIL - red gate stderr missing 'RED'"; FAIL=$((FAIL+1));;
esac

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
