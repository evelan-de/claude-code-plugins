#!/usr/bin/env bash
# Tests for bin/autopilot-watchdog. Run: bash bin/autopilot-watchdog.test.sh
set -uo pipefail
BIN="$(cd "$(dirname "$0")" && pwd)/autopilot-watchdog"
PASS=0; FAIL=0
ok()   { echo "ok   - $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL - $1"; FAIL=$((FAIL+1)); }

R="$(mktemp -d)"; S="$R/state"
git -C "$R" init -q
git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$R" checkout -q -b feat/x
mkdir -p "$R/docs/autopilot/sessions/2026-09-19-x"; echo "# plan" >"$R/docs/autopilot/sessions/2026-09-19-x/PLAN.md"

out="$(sh "$BIN" "$R" feat/x "$S")"; rc=$?
case "$out" in PROGRESS*stalls=0*) ok "first tick is PROGRESS (rc $rc)";; *) fail "first tick: $out";; esac

out="$(sh "$BIN" "$R" feat/x "$S")"; rc=$?
case "$out" in STALL*stalls=1*) [ $rc -eq 0 ] && ok "unchanged tick is STALL stalls=1, exit 0" || fail "stall rc $rc";; *) fail "second tick: $out";; esac

out="$(sh "$BIN" "$R" feat/x "$S")"
case "$out" in STALL*stalls=2*) ok "consecutive stall counts to 2";; *) fail "third tick: $out";; esac

git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m wp1
out="$(sh "$BIN" "$R" feat/x "$S")"
case "$out" in PROGRESS*stalls=0*) ok "new commit resets to PROGRESS";; *) fail "commit tick: $out";; esac

sleep 1; echo "- [x] WP1" >>"$R/docs/autopilot/sessions/2026-09-19-x/PLAN.md"
sh "$BIN" "$R" feat/x "$S" >/dev/null   # consume commit progress
touch -t 203001010000 "$R/docs/autopilot/sessions/2026-09-19-x/PLAN.md"
out="$(sh "$BIN" "$R" feat/x "$S")"
case "$out" in PROGRESS*) ok "PLAN.md mtime change counts as progress";; *) fail "plan tick: $out";; esac

out="$(sh "$BIN" "$R" nobranch "$S.2" 2>/dev/null)"
case "$out" in *commit=none*age=-1*) ok "missing branch reports commit=none";; *) fail "missing branch: $out";; esac

sh "$BIN" >/dev/null 2>&1; [ $? -eq 2 ] && ok "usage error exits 2" || fail "usage exit code"

R2="$(mktemp -d)"; git -C "$R2" init -q; git -C "$R2" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init; git -C "$R2" checkout -q -b feat/x
out1="$(sh "$BIN" "$R" feat/x)"; out2="$(sh "$BIN" "$R2" feat/x)"
case "$out2" in PROGRESS*) ok "default state file is keyed per repo (second repo starts fresh)";; *) fail "repo key: $out2";; esac
rm -rf "$R2"; rm -f "${TMPDIR:-/tmp}"/autopilot-watchdog-*-feat_x.state

rm -rf "$R"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
