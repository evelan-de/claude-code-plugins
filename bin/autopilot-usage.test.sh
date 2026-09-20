#!/usr/bin/env bash
# Tests for bin/autopilot-usage. Run: bash bin/autopilot-usage.test.sh
set -uo pipefail
BIN="$(cd "$(dirname "$0")" && pwd)/autopilot-usage"
PASS=0; FAIL=0
ok()   { echo "ok   - $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL - $1"; FAIL=$((FAIL+1)); }
if ! command -v jq >/dev/null 2>&1; then echo "SKIP - jq not installed"; exit 0; fi

P="$(mktemp -d)"
MAIN="$P/sess.jsonl"
mkdir -p "$P/sess/subagents/workflows/w1"

rec() { # $1 file $2 input $3 cache_create $4 cache_read $5 output
  printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' "$2" "$3" "$4" "$5" >>"$1"
}

# coordinator: three turns, then the lead dispatch, then two more turns
echo '{"type":"user","message":{"content":"go"}}' >"$MAIN"
rec "$MAIN" 2 100000 0 500
rec "$MAIN" 2 20000 100000 700
rec "$MAIN" 2 30000 120000 900
printf '{"type":"assistant","message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":1000,"cache_read_input_tokens":150000,"output_tokens":300},"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"evelan:autopilot-lead","prompt":"PACKAGE P1"}}]}}\n' >>"$MAIN"
rec "$MAIN" 2 5000 151000 400
rec "$MAIN" 2 100 156000 200

# lead subagent with meta, an explore agent without meta, a nested workflow agent
L="$P/sess/subagents/agent-lead1.jsonl"
rec "$L" 2 50000 0 100
rec "$L" 2 10000 50000 2000
rec "$L" 2 20000 60000 3000
echo '{"agentType":"evelan:autopilot-lead","name":"lead-P1"}' >"$P/sess/subagents/agent-lead1.meta.json"
E="$P/sess/subagents/agent-explore.jsonl"
rec "$E" 2 56000 0 10
rec "$E" 2 4000 56000 20000
W="$P/sess/subagents/workflows/w1/agent-wf.jsonl"
rec "$W" 2 30000 0 50

out="$(sh "$BIN" "$MAIN")"
echo "$out"

echo "$out" | grep -q '^agent ' && ok "prints a header" || fail "header missing"
echo "$out" | grep -E '^coordinator +main +6 +100002 +156102 +156102 +677000/1000000|^coordinator +main +6 +100002 +156102 +156102 +0\.7 +3\.0' >/dev/null && ok "coordinator row: turns, first, last, max, cache reads, output" || fail "coordinator row: $(echo "$out" | grep '^coordinator')"
echo "$out" | grep -E '^agent-lead1 +evelan:autopilot-lead \(lead-P1\) +3 +50002 +80002 +80002 +0\.1 +5\.1' >/dev/null && ok "lead row with type from meta.json" || fail "lead row: $(echo "$out" | grep '^agent-lead1')"
echo "$out" | grep -E '^agent-explore +\? +2 +56002 +60002 +60002 +0\.1 +20\.0' >/dev/null && ok "agent without meta.json gets type ?" || fail "explore row: $(echo "$out" | grep '^agent-explore')"
echo "$out" | grep -E '^agent-wf +\? +1 +30002' >/dev/null && ok "nested workflow agent is included" || fail "workflow row missing"
echo "$out" | grep -E '^TOTAL +12 ' >/dev/null && ok "total turns across all agents" || fail "total: $(echo "$out" | grep '^TOTAL')"
echo "$out" | grep -q 'first autopilot-lead dispatch.*: 150002$' && ok "planning cost = context at the first lead dispatch" || fail "planning cost line: $(echo "$out" | grep dispatch)"

# a session without any lead dispatch prints no planning line
M2="$P/plain.jsonl"; rec "$M2" 2 1000 0 10
out2="$(sh "$BIN" "$M2")"
echo "$out2" | grep -q 'dispatch' && fail "planning line printed without dispatch" || ok "no planning line without a lead dispatch"

# usage errors
sh "$BIN" >/dev/null 2>&1; [ $? -eq 2 ] && ok "no argument -> exit 2" || fail "exit code without argument"
sh "$BIN" "$P/none.jsonl" >/dev/null 2>&1; [ $? -eq 2 ] && ok "missing file -> exit 2" || fail "exit code for missing file"

rm -rf "$P"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
