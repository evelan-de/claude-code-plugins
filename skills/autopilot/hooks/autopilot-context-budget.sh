#!/usr/bin/env bash
# Autopilot context-budget hook (TEMPLATE). PostToolUse, matcher "" (every tool).
# Copied into a project's .claude/hooks/ by `/autopilot init`.
#
# Replaces auto-compaction with an explicit hand-off. After every tool call it reads the
# transcript of the agent it runs in, takes the context size of the last assistant turns
# (input + cache_creation + cache_read tokens = the context the next turn will carry) and,
# once that exceeds the budget, injects a system reminder via additionalContext: write
# HANDOFF.md into the autopilot session folder, commit, and return the dispatch block as
# `incomplete` so the coordinator dispatches a fresh lead.
#
# Which transcript is measured (verified against Claude Code 2.1.241):
#   - `transcript_path` in the hook input is ALWAYS the main session's transcript, also when
#     the hook fires inside a subagent. Measuring it from a subagent reports the idle
#     coordinator's context: a large number that never moves.
#   - A subagent's own transcript lives at
#     <main transcript without .jsonl>/subagents/agent-<agent_id>.jsonl
#     (workflow agents one level deeper). With `agent_id` present, that file is measured; if
#     it cannot be found the hook stays silent rather than measure the wrong conversation.
#   - The reminder names the measured file so a wrong source is visible at once.
#
# Measurement: the minimum over the last three assistant records that carry usage. Real
# context growth is monotone, so the minimum lags by at most two tool calls, while a single
# outlier record (transcripts do contain one-off spikes far above the neighbouring turns)
# cannot trigger a hand-off on its own.
#
# Inert when:
#   - the project is not autopilot-enabled (.claude/autopilot.json missing),
#   - the session is neither a subagent (no agent_id in the hook input) nor a standalone
#     autopilot run (no .claude/.autopilot-active sentinel), i.e. an interactive session,
#   - jq is missing,
#   - the transcript to measure is missing or has no usage yet, or
#   - the budget has not been reached.
# Budget: AUTOPILOT_CONTEXT_BUDGET env, else "contextBudget" in .claude/autopilot.json,
# else 250000 tokens. Reminders repeat at most every AUTOPILOT_BUDGET_REMIND_EVERY (default
# 10) tool calls after the first hit, tracked in a marker file per agent (per session in a
# standalone run).
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG="$PROJECT_DIR/.claude/autopilot.json"

input="$(cat 2>/dev/null || true)"
[ -f "$CONFIG" ] || { echo '{}'; exit 0; }
command -v jq >/dev/null 2>&1 || { echo '{}'; exit 0; }

agent="$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)"
if [ -z "$agent" ] && [ ! -f "$PROJECT_DIR/.claude/.autopilot-active" ]; then
  echo '{}'; exit 0
fi

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -n "$transcript" ] || { echo '{}'; exit 0; }

# Inside a subagent, measure the subagent's own transcript, never the main session's.
if [ -n "$agent" ]; then
  case "$agent" in *[!A-Za-z0-9_-]*) echo '{}'; exit 0;; esac
  session_dir="${transcript%.jsonl}"
  own="$session_dir/subagents/agent-$agent.jsonl"
  if [ ! -f "$own" ] && [ -d "$session_dir/subagents" ]; then
    own="$(find "$session_dir/subagents" -maxdepth 3 -type f -name "agent-$agent.jsonl" 2>/dev/null | head -n 1)"
  fi
  transcript="$own"
fi
[ -n "$transcript" ] && [ -f "$transcript" ] || { echo '{}'; exit 0; }

budget="${AUTOPILOT_CONTEXT_BUDGET:-}"
if [ -z "$budget" ]; then
  budget="$(jq -r '.contextBudget // empty' "$CONFIG" 2>/dev/null)"
fi
budget="${budget:-250000}"
remind_every="${AUTOPILOT_BUDGET_REMIND_EVERY:-10}"

# Context per assistant record = input + cache_creation + cache_read; take the minimum of the
# last three records that carry usage. tail keeps the scan cheap on multi-megabyte transcripts.
ctx="$(tail -n 400 "$transcript" 2>/dev/null \
  | jq -r 'select(.type=="assistant") | .message.usage // empty
           | ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))' 2>/dev/null \
  | tail -n 3 | sort -n | head -n 1)"
case "$ctx" in
  ''|*[!0-9]*) echo '{}'; exit 0;;
esac

[ "$ctx" -ge "$budget" ] || { echo '{}'; exit 0; }

# Rate-limit reminders per agent (per session in a standalone run) so the model is not
# nagged on every call and a fresh agent never inherits another agent's counter.
key="$(basename "$transcript" .jsonl)"
marker_dir="${TMPDIR:-/tmp}/autopilot-context-budget"
mkdir -p "$marker_dir" 2>/dev/null
marker="$marker_dir/${key}.count"
count=0
[ -f "$marker" ] && count="$(cat "$marker" 2>/dev/null || echo 0)"
case "$count" in ''|*[!0-9]*) count=0;; esac
echo $((count + 1)) >"$marker"
if [ "$count" -ne 0 ] && [ $((count % remind_every)) -ne 0 ]; then
  echo '{}'; exit 0
fi

msg="AUTOPILOT CONTEXT BUDGET REACHED: this conversation now carries about ${ctx} tokens per turn (budget ${budget}; measured from $(basename "$transcript")). Do not continue implementing in this context. Hand off now: (1) make sure every finished change is committed on the session branch; (2) write HANDOFF.md into the autopilot session folder (docs/autopilot/sessions/<slug>/) using the format in the evelan:autopilot skill: current package and its status, what is verified (commands + results), what is open, the exact next step, and pointers to PLAN.md, commits and .claude/autopilot-gate.log instead of copies; (3) update the package status in PLAN.md; (4) commit both files; (5) return your output block with STATUS: incomplete and HANDOFF: <path>. A fresh agent will continue from HANDOFF.md."

jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
exit 0
