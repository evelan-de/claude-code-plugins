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

rec() { # $1 file $2 message id $3 input $4 cache_create $5 cache_read $6 output [$7 repeat lines, default 1]
  local n="${7:-1}" i=0
  while [ "$i" -lt "$n" ]; do
    printf '{"type":"assistant","message":{"id":"%s","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' "$2" "$3" "$4" "$5" "$6" >>"$1"
    i=$((i+1))
  done
}

# coordinator: three requests (the second written as three lines: thinking, text, tool use),
# then the dispatch request (two lines: thinking + the Agent tool use), then two more requests
echo '{"type":"user","message":{"content":"go"}}' >"$MAIN"
rec "$MAIN" m1 2 100000 0 500
rec "$MAIN" m2 2 20000 100000 700 3
rec "$MAIN" m3 2 30000 120000 900
printf '{"type":"assistant","message":{"id":"m4","usage":{"input_tokens":2,"cache_creation_input_tokens":1000,"cache_read_input_tokens":150000,"output_tokens":300},"content":[{"type":"thinking","thinking":"x"}]}}\n' >>"$MAIN"
printf '{"type":"assistant","message":{"id":"m4","usage":{"input_tokens":2,"cache_creation_input_tokens":1000,"cache_read_input_tokens":150000,"output_tokens":300},"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"evelan:autopilot-lead","prompt":"PACKAGE P1"}}]}}\n' >>"$MAIN"
rec "$MAIN" m5 2 5000 151000 400
rec "$MAIN" m6 2 100 156000 200

# lead subagent with meta (second request written twice), an explore agent without meta, a nested workflow agent
L="$P/sess/subagents/agent-lead1.jsonl"
rec "$L" l1 2 50000 0 100
rec "$L" l2 2 10000 50000 2000 2
rec "$L" l3 2 20000 60000 3000
echo '{"agentType":"evelan:autopilot-lead","name":"lead-P1"}' >"$P/sess/subagents/agent-lead1.meta.json"
E="$P/sess/subagents/agent-explore.jsonl"
rec "$E" e1 2 56000 0 10
rec "$E" e2 2 4000 56000 20000
W="$P/sess/subagents/workflows/w1/agent-wf.jsonl"
rec "$W" w1 2 30000 0 50

out="$(sh "$BIN" "$MAIN")"
echo "$out"

echo "$out" | grep -q '^agent ' && ok "prints a header" || fail "header missing"
echo "$out" | grep -E '^coordinator +main +6 +100002 +156102 +156102 +0\.7 +0\.16 +3\.0' >/dev/null && ok "coordinator: 6 requests (repeated lines collapsed), first, last, max, cache reads, cache writes, output" || fail "coordinator row: $(echo "$out" | grep '^coordinator')"
echo "$out" | grep -E '^agent-lead1 +evelan:autopilot-lead \(lead-P1\) +3 +50002 +80002 +80002 +0\.1 +0\.08 +5\.1' >/dev/null && ok "lead row with type from meta.json, duplicate line counted once" || fail "lead row: $(echo "$out" | grep '^agent-lead1')"
echo "$out" | grep -E '^agent-explore +\? +2 +56002 +60002 +60002 +0\.1 +0\.06 +20\.0' >/dev/null && ok "agent without meta.json gets type ?" || fail "explore row: $(echo "$out" | grep '^agent-explore')"
echo "$out" | grep -E '^agent-wf +\? +1 +30002' >/dev/null && ok "nested workflow agent is included" || fail "workflow row missing"
echo "$out" | grep -E '^TOTAL +12 ' >/dev/null && ok "total requests across all agents" || fail "total: $(echo "$out" | grep '^TOTAL')"
echo "$out" | grep -q 'first autopilot-lead dispatch.*: 151002$' && ok "planning cost = context of the dispatch request itself" || fail "planning cost line: $(echo "$out" | grep dispatch)"

# records without a message id are counted per line (synthetic transcripts)
M3="$P/noid.jsonl"
printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":10,"cache_read_input_tokens":0,"output_tokens":1}}}\n' >>"$M3"
printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":10,"cache_read_input_tokens":11,"output_tokens":1}}}\n' >>"$M3"
sh "$BIN" "$M3" | grep -E '^coordinator +main +2 ' >/dev/null && ok "lines without message id count individually" || fail "no-id transcript"

# a session without any lead dispatch prints no planning line
M2="$P/plain.jsonl"; rec "$M2" p1 2 1000 0 10
out2="$(sh "$BIN" "$M2")"
echo "$out2" | grep -q 'dispatch' && fail "planning line printed without dispatch" || ok "no planning line without a lead dispatch"

# usage errors
sh "$BIN" >/dev/null 2>&1; [ $? -eq 2 ] && ok "no argument -> exit 2" || fail "exit code without argument"
sh "$BIN" "$P/none.jsonl" >/dev/null 2>&1; [ $? -eq 2 ] && ok "missing file -> exit 2" || fail "exit code for missing file"

rm -rf "$P"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
