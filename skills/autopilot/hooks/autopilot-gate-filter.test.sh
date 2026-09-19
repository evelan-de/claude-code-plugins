#!/usr/bin/env bash
# Tests for autopilot-gate-filter.sh. Run: bash skills/autopilot/hooks/autopilot-gate-filter.test.sh
set -uo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/autopilot-gate-filter.sh"
PASS=0; FAIL=0

ok()   { echo "ok   - $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL - $1"; FAIL=$((FAIL+1)); }

# Project fixture: a git repo with .claude/autopilot.json and the hook copied in place.
mk_project() {
  local p; p="$(mktemp -d)"
  mkdir -p "$p/.claude/hooks"
  cp "$SRC" "$p/.claude/hooks/autopilot-gate-filter.sh"
  git -C "$p" init -q 2>/dev/null
  git -C "$p" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
  echo "$p"
}

hook_json() {
  # $1 project dir  $2 command
  local scratch; scratch="$(mktemp -d)"
  jq -n --arg cmd "$2" --arg s "$scratch" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, scratchpad_dir:$s, tool_use_id:"toolu_test"}'
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP - jq not installed; hook mode needs jq"; exit 0
fi

# 1. Not autopilot-enabled -> passthrough
P="$(mk_project)"
out="$(hook_json "$P" "pnpm test" | CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh")"
[ "$out" = "{}" ] && ok "no autopilot.json -> {}" || fail "no autopilot.json -> {} (got $out)"

echo '{ "gate": "true" }' > "$P/.claude/autopilot.json"

# 2. Non-runner command -> passthrough
out="$(hook_json "$P" "git status --short" | CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh")"
[ "$out" = "{}" ] && ok "non-runner command -> {}" || fail "non-runner command -> {} (got $out)"

# 3. `# raw` bypass
out="$(hook_json "$P" "pnpm test # raw" | CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh")"
[ "$out" = "{}" ] && ok "# raw bypass -> {}" || fail "# raw bypass -> {} (got $out)"

# 4. Runner commands are rewritten to `<hook> run <cmdfile>`
for c in "pnpm test 2>&1" "npm run lint" "npx vitest run src/x.test.ts" "yarn typecheck" "cd apps/web && pnpm run check-types" "npx tsc --noEmit" "bun run build"; do
  out="$(hook_json "$P" "$c" | CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh")"
  new="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
  case "$new" in
    *autopilot-gate-filter.sh\"\ run\ *) ok "rewrites: $c" ;;
    *) fail "rewrites: $c (got: $out)" ;;
  esac
done

# 5. Rewritten command file holds the original command verbatim
out="$(hook_json "$P" "pnpm test -- --reporter=dot" | CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh")"
cmdfile="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command' | sed -E 's/.* run "([^"]+)"$/\1/')"
[ "$(cat "$cmdfile")" = "pnpm test -- --reporter=dot" ] && ok "cmdfile holds original command" || fail "cmdfile content (got: $(cat "$cmdfile" 2>&1))"

# 6. run mode: green command keeps exit 0, prints GREEN, logs a line
f="$(mktemp)"; printf 'for i in $(seq 1 50); do echo "line $i"; done\necho "Tests  12 passed (12)"\n' >"$f"
res="$(CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh" run "$f")"; rc=$?
[ "$rc" -eq 0 ] && ok "green run exits 0" || fail "green run exit (got $rc)"
case "$res" in *"GATE GREEN"*"12 passed"*) ok "green run prints GREEN + summary";; *) fail "green output: $res";; esac
lines="$(printf '%s\n' "$res" | wc -l | tr -d ' ')"
[ "$lines" -le 14 ] && ok "green run suppresses body ($lines lines)" || fail "green run too long ($lines lines)"
grep -q -E 'exit=0.*cmd=for i' "$P/.claude/autopilot-gate.log" && ok "green run logged" || fail "green run log missing"

# 7. run mode: red command keeps its exit code, shows the failure block, logs it
f="$(mktemp)"; printf 'echo "noise 1"\necho "noise 2"\necho "FAIL src/x.test.ts > adds"\necho "AssertionError: expected 2 to be 3"\necho "Tests  1 failed | 11 passed (12)"\nexit 3\n' >"$f"
res="$(CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh" run "$f")"; rc=$?
[ "$rc" -eq 3 ] && ok "red run keeps exit 3" || fail "red run exit (got $rc)"
case "$res" in *"GATE RED (exit 3)"*"AssertionError"*"1 failed"*) ok "red run prints RED + failure + summary";; *) fail "red output: $res";; esac
grep -q -E 'exit=3' "$P/.claude/autopilot-gate.log" && ok "red run logged with exit=3" || fail "red run log missing"

# 8. run mode: pipefail is honoured (failing producer piped into a passing consumer)
f="$(mktemp)"; printf 'false | cat\n' >"$f"
CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh" run "$f" >/dev/null; rc=$?
[ "$rc" -ne 0 ] && ok "pipefail keeps failure through a pipe" || fail "pipefail lost the failure"

# 9. log line carries head and tree state
grep -q -E 'head=[0-9a-f]+\ttree=(clean|dirty)' "$P/.claude/autopilot-gate.log" && ok "log has head + tree" || fail "log format: $(tail -n1 "$P/.claude/autopilot-gate.log")"

rm -rf "$P"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
