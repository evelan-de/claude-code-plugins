#!/usr/bin/env bash
# Autopilot context-budget hook (TEMPLATE). PostToolUse, matcher "" (every tool).
# Copied into a project's .claude/hooks/ by `/autopilot init`.
#
# Replaces auto-compaction with an explicit hand-off. After every tool call it reads the
# last assistant record of the session's own transcript (transcript_path from the hook
# input), sums input + cache_creation + cache_read tokens (= the context the next turn
# will carry) and, once that exceeds the budget, injects a system reminder via
# additionalContext: write HANDOFF.md into the autopilot session folder, commit, and
# return the dispatch block as `incomplete` so the coordinator dispatches a fresh lead.
#
# Deterministic, no model summary involved. Inert when:
#   - the project is not autopilot-enabled (.claude/autopilot.json missing),
#   - jq is missing,
#   - the transcript has no usage yet, or
#   - the budget has not been reached.
# Budget: AUTOPILOT_CONTEXT_BUDGET env, else "contextBudget" in .claude/autopilot.json,
# else 250000 tokens. Reminders repeat at most every AUTOPILOT_BUDGET_REMIND_EVERY (default
# 10) tool calls after the first hit, tracked in a per-session marker file.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG="$PROJECT_DIR/.claude/autopilot.json"

input="$(cat 2>/dev/null || true)"
[ -f "$CONFIG" ] || { echo '{}'; exit 0; }
command -v jq >/dev/null 2>&1 || { echo '{}'; exit 0; }

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -n "$transcript" ] && [ -f "$transcript" ] || { echo '{}'; exit 0; }

budget="${AUTOPILOT_CONTEXT_BUDGET:-}"
if [ -z "$budget" ]; then
  budget="$(jq -r '.contextBudget // empty' "$CONFIG" 2>/dev/null)"
fi
budget="${budget:-250000}"
remind_every="${AUTOPILOT_BUDGET_REMIND_EVERY:-10}"

# Last assistant record with usage: context = input + cache_creation + cache_read.
# tail keeps the scan cheap on multi-megabyte transcripts.
ctx="$(tail -n 400 "$transcript" 2>/dev/null \
  | jq -r 'select(.type=="assistant") | .message.usage // empty
           | ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))' 2>/dev/null \
  | tail -n 1)"
case "$ctx" in
  ''|*[!0-9]*) echo '{}'; exit 0;;
esac

[ "$ctx" -ge "$budget" ] || { echo '{}'; exit 0; }

# Rate-limit reminders per session so the model is not nagged on every call.
session="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)"
agent="$(printf '%s' "$input" | jq -r '.agent_id // "main"' 2>/dev/null)"
marker_dir="${TMPDIR:-/tmp}/autopilot-context-budget"
mkdir -p "$marker_dir" 2>/dev/null
marker="$marker_dir/${session}-${agent}.count"
count=0
[ -f "$marker" ] && count="$(cat "$marker" 2>/dev/null || echo 0)"
case "$count" in ''|*[!0-9]*) count=0;; esac
echo $((count + 1)) >"$marker"
if [ "$count" -ne 0 ] && [ $((count % remind_every)) -ne 0 ]; then
  echo '{}'; exit 0
fi

msg="AUTOPILOT CONTEXT BUDGET REACHED: this conversation now carries about ${ctx} tokens per turn (budget ${budget}). Do not continue implementing in this context. Hand off now: (1) make sure every finished change is committed on the session branch; (2) write HANDOFF.md into the autopilot session folder (docs/autopilot/sessions/<slug>/) using the format in the evelan:autopilot skill: current package and its status, what is verified (commands + results), what is open, the exact next step, and pointers to PLAN.md, commits and .claude/autopilot-gate.log instead of copies; (3) update the package status in PLAN.md; (4) commit both files; (5) return your output block with STATUS: incomplete and HANDOFF: <path>. A fresh agent will continue from HANDOFF.md."

jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
exit 0
