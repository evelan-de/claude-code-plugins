#!/usr/bin/env bash
# Autopilot SessionStart hook (TEMPLATE), matcher "compact".
# Copied into a project's .claude/hooks/ by `/autopilot init`.
#
# Auto-compaction is not the intended path (the context-budget hook hands off first), but
# if it happens anyway, the summary loses hook context and skill bodies. This hook re-injects
# the one pointer that matters: where the autopilot session artifacts are. It prints plain
# text, which Claude Code adds to the post-compaction context. Inert when no session folder
# exists.
set -uo pipefail

cat >/dev/null 2>&1 || true
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSIONS="$PROJECT_DIR/docs/autopilot/sessions"
[ -d "$SESSIONS" ] || exit 0

latest="$(ls -1t "$SESSIONS" 2>/dev/null | head -n 1)"
[ -n "$latest" ] || exit 0
dir="$SESSIONS/$latest"

echo "Context was compacted. If you are running an autopilot session, its artifacts are in $dir: re-read PLAN.md (package statuses, decisions, goal artifact) and, if present, HANDOFF.md before continuing. The gate command is in .claude/autopilot.json; the gate evidence log is .claude/autopilot-gate.log. Do not re-explore the repo: CONTEXT.md in the session folder is the digest."
exit 0
