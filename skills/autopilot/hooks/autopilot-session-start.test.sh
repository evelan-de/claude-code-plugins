#!/usr/bin/env bash
# Tests for autopilot-session-start.sh. Run: bash skills/autopilot/hooks/autopilot-session-start.test.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/autopilot-session-start.sh"
PASS=0; FAIL=0
ok()   { echo "ok   - $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL - $1"; FAIL=$((FAIL+1)); }

# 1. no sessions directory -> exit 0, silent
P="$(mktemp -d)"
out="$(echo '{}' | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"; rc=$?
[ "$rc" -eq 0 ] && ok "no session dir -> exit 0" || fail "no session dir -> exit $rc"
[ -z "$out" ] && ok "no session dir -> silent" || fail "no session dir printed: $out"
rm -rf "$P"

# 2. empty sessions directory -> exit 0, silent
P="$(mktemp -d)"; mkdir -p "$P/docs/autopilot/sessions"
out="$(echo '{}' | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "empty session dir -> exit 0, silent" || fail "empty session dir (rc $rc, out: $out)"
rm -rf "$P"

# 3. two sessions -> message names the newest and mentions PLAN.md and HANDOFF.md
P="$(mktemp -d)"
mkdir -p "$P/docs/autopilot/sessions/2026-09-01-old" "$P/docs/autopilot/sessions/2026-09-20-new"
out="$(echo '{}' | CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"; rc=$?
[ "$rc" -eq 0 ] && ok "session dir -> exit 0" || fail "session dir -> exit $rc"
case "$out" in *"$P/docs/autopilot/sessions/2026-09-20-new"*) ok "names the newest session dir";; *) fail "newest dir missing: $out";; esac
case "$out" in *"2026-09-01-old"*) fail "names the older session dir";; *) ok "ignores the older session dir";; esac
case "$out" in *PLAN.md*) ok "mentions PLAN.md";; *) fail "PLAN.md missing";; esac
case "$out" in *HANDOFF.md*) ok "mentions HANDOFF.md";; *) fail "HANDOFF.md missing";; esac
rm -rf "$P"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
