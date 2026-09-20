#!/usr/bin/env bash
# Tests for autopilot-gate.sh. Run: bash skills/autopilot/hooks/autopilot-gate.test.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/autopilot-gate.sh"
PASS=0; FAIL=0
LAST_ERR=""

setup() {
  # $1 sentinel(yes/no)  $2 gate_command(or "")  -> prints the project dir
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/.claude"
  [ "$1" = "yes" ] && touch "$tmp/.claude/.autopilot-active"
  if [ -n "$2" ]; then
    printf '{\n  "gate": "%s"\n}\n' "$2" > "$tmp/.claude/autopilot.json"
  fi
  echo "$tmp"
}

invoke() {
  # $1 project dir  $2 stop_hook_active (true/false)  -> exit code in $?, stderr in LAST_ERR
  local err="$1/stderr.txt"
  printf '{"session_id":"s1","hook_event_name":"Stop","stop_hook_active":%s}' "$2" \
    | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>"$err"
  local got=$?
  LAST_ERR="$(cat "$err")"
  return "$got"
}

check() {
  # $1 desc  $2 want  $3 got
  if [ "$3" -eq "$2" ]; then
    echo "ok   - $1 (exit $3)"; PASS=$((PASS+1))
  else
    echo "FAIL - $1 (want $2, got $3)"; FAIL=$((FAIL+1))
  fi
}

check_err() {
  # $1 desc  $2 substring expected in LAST_ERR
  case "$LAST_ERR" in
    *"$2"*) echo "ok   - $1"; PASS=$((PASS+1));;
    *) echo "FAIL - $1 (stderr: $LAST_ERR)"; FAIL=$((FAIL+1));;
  esac
}

P="$(setup no false)"
invoke "$P" false; check "no sentinel -> allow (exit 0) even with red gate" 0 $?
rm -rf "$P"

P="$(setup yes true)"
invoke "$P" false; check "sentinel + green gate -> allow (exit 0)" 0 $?
rm -rf "$P"

P="$(setup yes false)"
invoke "$P" false; check "sentinel + red gate -> block 1 (exit 2)" 2 $?
check_err "block 1 prints RED to stderr" "RED"
[ "$(cat "$P/.claude/.autopilot-gate-blocks")" = "1" ] && { echo "ok   - counter file is 1"; PASS=$((PASS+1)); } || { echo "FAIL - counter file"; FAIL=$((FAIL+1)); }
invoke "$P" true; check "red gate, stop_hook_active -> block 2 (exit 2)" 2 $?
invoke "$P" true; check "red gate, stop_hook_active -> block 3 (exit 2)" 2 $?
invoke "$P" true; check "red gate, 4th consecutive -> allow (exit 0)" 0 $?
check_err "4th block prints the yield reason" "after 3 consecutive blocks"
[ ! -f "$P/.claude/.autopilot-gate-blocks" ] && { echo "ok   - counter removed after yield"; PASS=$((PASS+1)); } || { echo "FAIL - counter not removed after yield"; FAIL=$((FAIL+1)); }
invoke "$P" true; check "after yield the next red stop blocks again (exit 2)" 2 $?
rm -rf "$P"

# a fresh stop (stop_hook_active=false) restarts the count
P="$(setup yes false)"
invoke "$P" false; invoke "$P" true; invoke "$P" true
invoke "$P" false; check "stop_hook_active=false restarts the count -> block (exit 2)" 2 $?
[ "$(cat "$P/.claude/.autopilot-gate-blocks")" = "1" ] && { echo "ok   - counter restarted at 1"; PASS=$((PASS+1)); } || { echo "FAIL - counter restart"; FAIL=$((FAIL+1)); }
rm -rf "$P"

# green resets the counter
P="$(setup yes false)"
invoke "$P" false; invoke "$P" true
printf '{\n  "gate": "true"\n}\n' > "$P/.claude/autopilot.json"
invoke "$P" true; check "green gate -> allow (exit 0)" 0 $?
[ ! -f "$P/.claude/.autopilot-gate-blocks" ] && { echo "ok   - green gate resets the counter"; PASS=$((PASS+1)); } || { echo "FAIL - counter survives green gate"; FAIL=$((FAIL+1)); }
rm -rf "$P"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
