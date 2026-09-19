#!/usr/bin/env bash
# Tests for autopilot-context-budget.sh. Run: bash skills/autopilot/hooks/autopilot-context-budget.test.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/autopilot-context-budget.sh"
PASS=0; FAIL=0
ok()   { echo "ok   - $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL - $1"; FAIL=$((FAIL+1)); }

if ! command -v jq >/dev/null 2>&1; then echo "SKIP - jq not installed"; exit 0; fi

P="$(mktemp -d)"; mkdir -p "$P/.claude" "$P/tr"
export TMPDIR="$P/tmp"; mkdir -p "$TMPDIR"

mk_transcript() {
  # $1 file  $2 cache_read of the last three assistant records (ctx = $2 + 2003)
  # $3 optional cache_read of one extra, final outlier record
  local f="$1" cr="$2" spike="${3:-}"
  mkdir -p "$(dirname "$f")"
  {
    echo '{"type":"user","message":{"content":"hi"}}'
    echo '{"type":"assistant","message":{"usage":{"input_tokens":5,"cache_creation_input_tokens":1000,"cache_read_input_tokens":50000}}}'
    echo '{"type":"user","message":{"content":[{"type":"tool_result","content":"x"}]}}'
    for _ in 1 2 3; do
      printf '{"type":"assistant","message":{"usage":{"input_tokens":3,"cache_creation_input_tokens":2000,"cache_read_input_tokens":%s}}}\n' "$cr"
    done
    if [ -n "$spike" ]; then
      printf '{"type":"assistant","message":{"usage":{"input_tokens":3,"cache_creation_input_tokens":2000,"cache_read_input_tokens":%s}}}\n' "$spike"
    fi
  } >"$f"
}

hook_input() {
  # $1 transcript_path (the MAIN session transcript, as Claude Code passes it)
  # $2 session id  [$3 agent_id, default "lead1"; pass "-" for no agent_id]
  local a="${3:-lead1}"
  if [ "$a" != "-" ]; then
    jq -n --arg t "$1" --arg s "$2" --arg a "$a" '{tool_name:"Bash",transcript_path:$t,session_id:$s,agent_id:$a,hook_event_name:"PostToolUse"}'
  else
    jq -n --arg t "$1" --arg s "$2" '{tool_name:"Bash",transcript_path:$t,session_id:$s,hook_event_name:"PostToolUse"}'
  fi
}

# Layout as on disk: <projects>/<session>.jsonl and <projects>/<session>/subagents/agent-<id>.jsonl
MAIN="$P/tr/sess1.jsonl"
SUB="$P/tr/sess1/subagents"
fires() { printf '%s' "$1" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; }

# 1. not autopilot-enabled -> {}
mk_transcript "$SUB/agent-lead1.jsonl" 900000
out="$(hook_input "$MAIN" sess1 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "no autopilot.json -> {}" || fail "no autopilot.json (got $out)"

echo '{ "gate": "true" }' >"$P/.claude/autopilot.json"

# 2. subagent below budget -> {}
mk_transcript "$SUB/agent-lead1.jsonl" 100000
out="$(hook_input "$MAIN" sess1 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "subagent below budget -> {}" || fail "below budget (got $out)"

# 3. THE 2026-09-19 BUG: main session far above budget, subagent below -> must stay silent.
#    (transcript_path always names the main transcript, also inside a subagent.)
mk_transcript "$MAIN" 900000
mk_transcript "$SUB/agent-lead1.jsonl" 100000
out="$(hook_input "$MAIN" sess1 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "subagent never measures the main session's transcript" || fail "measured the parent (got $out)"

# 4. subagent above budget (main below) -> hand-off instruction naming the measured file
mk_transcript "$MAIN" 100000
mk_transcript "$SUB/agent-lead1.jsonl" 300000
out="$(hook_input "$MAIN" sess1 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
ac="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty')"
case "$ac" in *"CONTEXT BUDGET REACHED"*"HANDOFF.md"*"STATUS: incomplete"*) ok "subagent above budget -> hand-off instruction";; *) fail "above budget output: $out";; esac
printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName=="PostToolUse"' >/dev/null && ok "hookEventName is PostToolUse" || fail "hookEventName"
case "$ac" in *"302003 tokens"*) ok "reports the measured context (302003)";; *) fail "context figure missing: $ac";; esac
case "$ac" in *"measured from agent-lead1.jsonl"*) ok "names the measured transcript";; *) fail "measured-from missing: $ac";; esac

# 5. reminder rate limit: second call for the same agent is silent, 11th fires again
out="$(hook_input "$MAIN" sess1 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "second hit for the same agent is silent" || fail "rate limit (got $out)"
for i in $(seq 1 8); do hook_input "$MAIN" sess1 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >/dev/null; done
out="$(hook_input "$MAIN" sess1 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
fires "$out" && ok "reminder repeats after 10 calls" || fail "reminder repeat (got $out)"

# 6. a second agent in the same session has its own transcript and its own counter
mk_transcript "$SUB/agent-lead2.jsonl" 300000
out="$(hook_input "$MAIN" sess1 lead2 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
fires "$out" && ok "separate transcript and counter per agent" || fail "per-agent counter (got $out)"

# 7. subagent transcript missing -> silent (never fall back to the main transcript)
mk_transcript "$MAIN" 900000
out="$(hook_input "$MAIN" sess1 ghost | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "unknown agent transcript -> {} (no fallback to main)" || fail "ghost agent (got $out)"

# 8. workflow agents live one level deeper and are still found
mk_transcript "$SUB/workflows/wf1/agent-wfa.jsonl" 300000
out="$(hook_input "$MAIN" sess1 wfa | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
fires "$out" && ok "nested workflow transcript is found" || fail "nested transcript (got $out)"

# 9. a single outlier record does not trigger (minimum of the last three records)
mk_transcript "$SUB/agent-lead3.jsonl" 100000 900000
out="$(hook_input "$MAIN" sess1 lead3 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "single spike record ignored" || fail "spike (got $out)"

# 10. agent_id with path characters is rejected
mk_transcript "$MAIN" 900000
out="$(hook_input "$MAIN" sess1 '../../sess1' | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "agent_id with path characters -> {}" || fail "path traversal (got $out)"

# 11. interactive session (no agent_id, no sentinel) -> silent even above budget
MAIN2="$P/tr/sess2.jsonl"; mk_transcript "$MAIN2" 300000
out="$(hook_input "$MAIN2" sess2 - | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "interactive session (no agent_id, no sentinel) -> {}" || fail "interactive guard (got $out)"

# 12. standalone autopilot run (sentinel, no agent_id) measures the main transcript and fires
touch "$P/.claude/.autopilot-active"
out="$(hook_input "$MAIN2" sess2 - | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
ac="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty')"
case "$ac" in *"measured from sess2.jsonl"*) ok "standalone run with sentinel -> fires on the main transcript";; *) fail "sentinel run (got $out)";; esac
rm -f "$P/.claude/.autopilot-active"

# 13. budget from autopilot.json
echo '{ "gate": "true", "contextBudget": 400000 }' >"$P/.claude/autopilot.json"
mk_transcript "$SUB/agent-lead4.jsonl" 300000
out="$(hook_input "$MAIN" sess1 lead4 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "contextBudget from autopilot.json respected (300k < 400k)" || fail "config budget (got $out)"

# 14. env override wins
out="$(hook_input "$MAIN" sess1 lead4 | AUTOPILOT_CONTEXT_BUDGET=200000 CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
fires "$out" && ok "env budget override" || fail "env budget (got $out)"

# 15. transcript without usage -> {}
echo '{"type":"user","message":{"content":"hi"}}' >"$SUB/agent-lead5.jsonl"
out="$(hook_input "$MAIN" sess1 lead5 | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "no usage yet -> {}" || fail "no usage (got $out)"

# 16. missing main transcript in a standalone run -> {}
touch "$P/.claude/.autopilot-active"
out="$(hook_input "$P/tr/none.jsonl" sess9 - | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"
[ "$out" = "{}" ] && ok "missing transcript -> {}" || fail "missing transcript (got $out)"
rm -f "$P/.claude/.autopilot-active"

rm -rf "$P"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
