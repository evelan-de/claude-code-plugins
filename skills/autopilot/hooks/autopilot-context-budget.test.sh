#!/usr/bin/env bash
# Tests for autopilot-context-budget.sh. Run: bash skills/autopilot/hooks/autopilot-context-budget.test.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/autopilot-context-budget.sh"
PASS=0; FAIL=0
ok()   { echo "ok   - $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL - $1"; FAIL=$((FAIL+1)); }

if ! command -v jq >/dev/null 2>&1; then echo "SKIP - jq not installed"; exit 0; fi

P="$(mktemp -d)"; mkdir -p "$P/.claude"
export TMPDIR="$P/tmp"; mkdir -p "$TMPDIR"

mk_transcript() {
  # $1 file  $2 cache_read of the last assistant record
  local f="$1" cr="$2"
  {
    echo '{"type":"user","message":{"content":"hi"}}'
    echo '{"type":"assistant","message":{"usage":{"input_tokens":5,"cache_creation_input_tokens":1000,"cache_read_input_tokens":50000}}}'
    echo '{"type":"user","message":{"content":[{"type":"tool_result","content":"x"}]}}'
    printf '{"type":"assistant","message":{"usage":{"input_tokens":3,"cache_creation_input_tokens":2000,"cache_read_input_tokens":%s}}}\n' "$cr"
  } >"$f"
}

hook_input() {
  # $1 transcript  $2 session  [$3 agent_id, default "lead-a1"; pass "-" for no agent_id]
  local a="${3:-lead-a1}"
  if [ "$a" != "-" ]; then
    jq -n --arg t "$1" --arg s "$2" --arg a "$a" '{tool_name:"Bash",transcript_path:$t,session_id:$s,agent_id:$a,hook_event_name:"PostToolUse"}'
  else
    jq -n --arg t "$1" --arg s "$2" '{tool_name:"Bash",transcript_path:$t,session_id:$s,hook_event_name:"PostToolUse"}'
  fi
}

T="$P/t.jsonl"

# 1. not autopilot-enabled -> {}
mk_transcript "$T" 900000
out="$(hook_input "$T" s1 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "no autopilot.json -> {}" || fail "no autopilot.json (got $out)"

echo '{ "gate": "true" }' >"$P/.claude/autopilot.json"

# 2. below budget -> {}
mk_transcript "$T" 100000
out="$(hook_input "$T" s2 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "below budget -> {}" || fail "below budget (got $out)"

# 3. above default budget (250k) -> additionalContext with the hand-off instruction
mk_transcript "$T" 300000
out="$(hook_input "$T" s3 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
ac="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty')"
case "$ac" in *"CONTEXT BUDGET REACHED"*"HANDOFF.md"*"STATUS: incomplete"*) ok "above budget -> hand-off instruction";; *) fail "above budget output: $out";; esac
printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName=="PostToolUse"' >/dev/null && ok "hookEventName is PostToolUse" || fail "hookEventName"
case "$ac" in *"302003 tokens"*) ok "reports the measured context (302003)";; *) fail "context figure missing: $ac";; esac

# 4. reminder rate limit: second call in same session/agent is silent, 11th fires again
out="$(hook_input "$T" s3 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "second hit in same session is silent" || fail "rate limit (got $out)"
for i in $(seq 1 8); do hook_input "$T" s3 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >/dev/null; done
out="$(hook_input "$T" s3 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 && ok "reminder repeats after 10 calls" || fail "reminder repeat (got $out)"

# 5. a different transcript (= different agent) has its own counter
T2="$P/t2.jsonl"; mk_transcript "$T2" 300000
out="$(hook_input "$T2" s3 agentB | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 && ok "separate counter per transcript/agent" || fail "per-agent counter (got $out)"

# 5b. interactive session (no agent_id, no sentinel) -> silent even above budget
T3="$P/t3.jsonl"; mk_transcript "$T3" 300000
out="$(hook_input "$T3" s8 - | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "interactive session (no agent_id, no sentinel) -> {}" || fail "interactive guard (got $out)"

# 5c. standalone autopilot run (sentinel present, no agent_id) -> fires
touch "$P/.claude/.autopilot-active"
out="$(hook_input "$T3" s8 - | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 && ok "standalone run with sentinel -> fires" || fail "sentinel run (got $out)"
rm -f "$P/.claude/.autopilot-active"

# 6. budget from autopilot.json
echo '{ "gate": "true", "contextBudget": 400000 }' >"$P/.claude/autopilot.json"
out="$(hook_input "$T" s4 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "contextBudget from autopilot.json respected (300k < 400k)" || fail "config budget (got $out)"

# 7. env override wins (fresh transcript so the rate limiter does not interfere)
T4="$P/t4.jsonl"; mk_transcript "$T4" 300000
out="$(hook_input "$T4" s5 | AUTOPILOT_CONTEXT_BUDGET=200000 CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 && ok "env budget override" || fail "env budget (got $out)"

# 8. transcript without usage -> {}
echo '{"type":"user","message":{"content":"hi"}}' >"$T"
out="$(hook_input "$T" s6 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "no usage yet -> {}" || fail "no usage (got $out)"

# 9. missing transcript -> {}
out="$(hook_input "$P/none.jsonl" s7 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "missing transcript -> {}" || fail "missing transcript (got $out)"

rm -rf "$P"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
