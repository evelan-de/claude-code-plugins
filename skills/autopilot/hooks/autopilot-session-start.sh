#!/usr/bin/env bash
# Autopilot SessionStart hook (TEMPLATE), matcher "compact".
# Copied into a project's .claude/hooks/ by `autopilot-hooks install` (from /autopilot init and the runner).
# autopilot-hook-version: 2   (raise it with every change to this file)
#
# If compaction happens in a standalone autopilot run, re-inject where the session artifacts
# are (newest date-prefixed session folder). Plain text on stdout is added to the
# post-compaction context. SessionStart does not fire for subagents, so this covers run mode
# only. Inert when no session folder exists.
set -uo pipefail

cat >/dev/null 2>&1 || true
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSIONS="$PROJECT_DIR/docs/autopilot/sessions"
[ -d "$SESSIONS" ] || exit 0

latest="$(ls -1 "$SESSIONS" 2>/dev/null | sort -r | head -n 1)"
[ -n "$latest" ] || exit 0
dir="$SESSIONS/$latest"

echo "Context was compacted. If you are running an autopilot session, its artifacts are in $dir: re-read PLAN.md (package statuses, decisions, goal artifact) and, if present, HANDOFF.md before continuing. The gate command is in .claude/autopilot.json; the gate evidence log is .claude/autopilot-gate.log. Do not re-explore the repo: PLAN.md names the files and seams."
exit 0
