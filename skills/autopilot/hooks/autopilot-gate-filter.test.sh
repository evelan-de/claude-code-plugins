#!/usr/bin/env bash
# Tests for autopilot-gate-filter.sh. Run: bash skills/autopilot/hooks/autopilot-gate-filter.test.sh
set -uo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/autopilot-gate-filter.sh"
PASS=0; FAIL=0
ok()   { echo "ok   - $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL - $1"; FAIL=$((FAIL+1)); }

mk_project() {
  local p; p="$(mktemp -d)"
  mkdir -p "$p/.claude/hooks" "$p/apps/web"
  cp "$SRC" "$p/.claude/hooks/autopilot-gate-filter.sh"
  git -C "$p" init -q 2>/dev/null
  echo "x" >"$p/tracked.txt"
  git -C "$p" add tracked.txt
  git -C "$p" -c user.email=t@t -c user.name=t commit -q -m init 2>/dev/null
  echo "$p"
}

hook_json() {
  # $1 project dir  $2 command  [$3 cwd]
  local scratch; scratch="$(mktemp -d)"
  jq -n --arg cmd "$2" --arg s "$scratch" --arg cwd "${3:-$1}" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, scratchpad_dir:$s, tool_use_id:"toolu_test", cwd:$cwd}'
}
hook() { CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh"; }

if ! command -v jq >/dev/null 2>&1; then echo "SKIP - jq not installed"; exit 0; fi

P="$(mk_project)"
out="$(hook_json "$P" "pnpm test" | hook)"
[ "$out" = "{}" ] && ok "no autopilot.json -> {}" || fail "no autopilot.json (got $out)"

echo '{ "gate": "pnpm test" }' >"$P/.claude/autopilot.json"

# passthrough cases (must NOT rewrite)
for c in "git status --short" "pnpm test # raw" "test -f .env && echo ok" "[ -d x ] || test -d y" "if true; then test 1; fi" "docker build ." "git checkout build" "mkdir build" "git test-branch"; do
  out="$(hook_json "$P" "$c" | hook)"
  [ "$out" = "{}" ] && ok "passthrough: $c" || fail "passthrough: $c (got $out)"
done

# runner cases (must rewrite)
for c in "pnpm test 2>&1" "npm run lint" "npx vitest run src/x.test.ts" "yarn typecheck" "cd apps/web && pnpm run check-types" "npx tsc --noEmit" "bun run build" "npm run build:docs" "pnpm --filter web run test" "pnpm -r test" "yarn workspace foo test" "pnpm exec playwright test" "timeout 600 pnpm test"; do
  out="$(hook_json "$P" "$c" | hook)"
  new="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
  case "$new" in *autopilot-gate-filter.sh\"\ run\ *) ok "rewrites: $c";; *) fail "rewrites: $c (got: $out)";; esac
done

# cmdfile keeps cwd and the original command
out="$(hook_json "$P" "pnpm test -- --reporter=dot" "$P/apps/web" | hook)"
cmdfile="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command' | sed -E 's/.* run "([^"]+)"$/\1/')"
grep -q "^cd .*apps/web" "$cmdfile" && ok "cmdfile starts with cd to the caller cwd" || fail "cmdfile cwd: $(head -n1 "$cmdfile")"
grep -q "^# CMD: pnpm test -- --reporter=dot" "$cmdfile" && ok "cmdfile records the original command" || fail "cmdfile CMD line"
[ "$(tail -n1 "$cmdfile")" = "pnpm test -- --reporter=dot" ] && ok "cmdfile ends with the original command" || fail "cmdfile tail: $(tail -n1 "$cmdfile")"

# run mode: cwd honoured
f="$(mktemp)"; printf 'cd %q || exit 1\n# CMD: pwd\npwd\n' "$P/apps/web" >"$f"
res="$(CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh" run "$f")"
case "$res" in *apps/web*) ok "run mode executes in the recorded cwd";; *) fail "run cwd: $res";; esac

# run mode: green
f="$(mktemp)"; printf '# CMD: pnpm test\nfor i in $(seq 1 50); do echo "line $i"; done\necho "Tests  12 passed (12)"\n' >"$f"
res="$(CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh" run "$f")"; rc=$?
[ "$rc" -eq 0 ] && ok "green run exits 0" || fail "green run exit (got $rc)"
case "$res" in *"GATE GREEN"*"12 passed"*) ok "green run prints GREEN + summary";; *) fail "green output: $res";; esac
lines="$(printf '%s\n' "$res" | wc -l | tr -d ' ')"
[ "$lines" -le 14 ] && ok "green run suppresses body ($lines lines)" || fail "green run too long ($lines lines)"
grep -q -E 'exit=0.*cmd=pnpm test$' "$P/.claude/autopilot-gate.log" && ok "green run logged with the original command" || fail "green run log: $(tail -n1 "$P/.claude/autopilot-gate.log")"

# run mode: red keeps exit code, shows failures
f="$(mktemp)"; printf '# CMD: pnpm test\necho "noise 1"\necho "FAIL src/x.test.ts > adds"\necho "AssertionError: expected 2 to be 3"\necho "Tests  1 failed | 11 passed (12)"\nexit 3\n' >"$f"
res="$(CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh" run "$f")"; rc=$?
[ "$rc" -eq 3 ] && ok "red run keeps exit 3" || fail "red run exit (got $rc)"
case "$res" in *"GATE RED (exit 3)"*"AssertionError"*"1 failed"*) ok "red run prints RED + failure + summary";; *) fail "red output: $res";; esac
grep -q -E 'exit=3' "$P/.claude/autopilot-gate.log" && ok "red run logged with exit=3" || fail "red run log missing"

# pipefail honoured
f="$(mktemp)"; printf '# CMD: false | cat\nfalse | cat\n' >"$f"
CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh" run "$f" >/dev/null; rc=$?
[ "$rc" -ne 0 ] && ok "pipefail keeps failure through a pipe" || fail "pipefail lost the failure"

# tree hash: stable while the working tree is unchanged, changes on an uncommitted edit, matches the log
t1="$(CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh" tree)"
t2="$(CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh" tree)"
[ -n "$t1" ] && [ "$t1" = "$t2" ] && ok "tree hash is stable ($t1)" || fail "tree hash unstable: $t1 vs $t2"
grep -q "tree=$t1" "$P/.claude/autopilot-gate.log" && ok "log line carries the current tree hash" || fail "log tree mismatch: $(tail -n1 "$P/.claude/autopilot-gate.log")"
echo "changed" >"$P/tracked.txt"
t3="$(CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh" tree)"
[ "$t3" != "$t1" ] && ok "tree hash changes on an uncommitted edit" || fail "tree hash ignored the edit"
echo "new" >"$P/untracked.txt"
t4="$(CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh" tree)"
[ "$t4" != "$t3" ] && ok "tree hash includes untracked files" || fail "tree hash ignored untracked file"
git -C "$P" status --porcelain | grep -q "^A " && fail "tree hash touched the real index" || ok "tree hash leaves the real index alone"

# --- login shell: run mode executes the command file in $SHELL as a login shell with pipefail when
# that is bash or zsh, otherwise in bash. HOME and ZDOTDIR point at a scratch dir in every case, so
# no real dotfiles are read; TMPDIR keeps run mode's output folders inside it.
L="$(mktemp -d)"; mkdir -p "$L/home" "$L/sh" "$L/tmp"
REAL_BASH="$(command -v bash)"
run_env() {
  # $1 command file  $2.. extra env (NAME=value)  -> stdout+stderr, exit code in $?
  local f="$1"; shift
  env HOME="$L/home" ZDOTDIR="$L/home" TMPDIR="$L/tmp" "$@" CLAUDE_PROJECT_DIR="$P" \
    bash "$P/.claude/hooks/autopilot-gate-filter.sh" run "$f" 2>&1
}
mkrec() {
  # $1 name -> $L/sh/<name>: writes its arguments one per line to $L/sh/<name>.args, then runs bash
  cat >"$L/sh/$1" <<EOF
#!$REAL_BASH
printf '%s\n' "\$@" >"$L/sh/$1.args"
exec "$REAL_BASH" "\$@"
EOF
  chmod +x "$L/sh/$1"
}
mkrec bash; mkrec dash
f="$L/echo.sh"; printf '# CMD: echo hi\necho hi\n' >"$f"
res="$(run_env "$f" SHELL="$L/sh/bash")"; rc=$?
[ "$rc" -eq 0 ] && ok "SHELL=bash: green run through that shell" || fail "SHELL=bash: exit $rc ($res)"
[ "$(cat "$L/sh/bash.args" 2>/dev/null)" = "$(printf -- '-l\n-o\npipefail\n%s' "$f")" ] \
  && ok "run mode calls \$SHELL -l -o pipefail <cmdfile>" \
  || fail "\$SHELL was not called as -l -o pipefail <cmdfile> (args: $(tr '\n' ' ' 2>/dev/null <"$L/sh/bash.args"))"
# Any other shell (dash rejects -o pipefail, csh -l), an empty SHELL or a missing binary: bash
# (not sh, which on macOS is bash in POSIX mode).
f="$L/is-bash.sh"; printf '# CMD: is bash\n[ ${#BASH_VERSION} -gt 0 ] && ! shopt -oq posix\n' >"$f"
res="$(run_env "$f" SHELL="$L/sh/dash")"; rc=$?
[ "$rc" -eq 0 ] && ok "SHELL=dash: the command runs in bash (green only there)" || fail "SHELL=dash: exit $rc ($res)"
[ ! -f "$L/sh/dash.args" ] && ok "SHELL=dash: dash was not called" || fail "dash was called"
res="$(run_env "$f" SHELL=)"; rc=$?
[ "$rc" -eq 0 ] && ok "empty SHELL: the command runs in bash" || fail "empty SHELL: exit $rc ($res)"
res="$(run_env "$f" SHELL="$L/missing/zsh")"; rc=$?
[ "$rc" -eq 0 ] && ok "SHELL names a missing zsh: the command runs in bash" || fail "missing zsh: exit $rc ($res)"

ZSH_BIN="$(command -v zsh || true)"
if [ -n "$ZSH_BIN" ]; then
  f="$L/is-zsh.sh"; printf '# CMD: is zsh\n[ ${#ZSH_VERSION} -gt 0 ]\n' >"$f"
  res="$(run_env "$f" SHELL="$ZSH_BIN")"; rc=$?
  [ "$rc" -eq 0 ] && ok "SHELL=zsh: the command runs in zsh (green only there)" || fail "SHELL=zsh: exit $rc ($res)"
  # The finding this guards: node/pnpm on PATH only through zsh's startup files. ~/.zprofile is
  # read by login shells only, so green here also proves -l; the probe name exists nowhere else.
  mkdir -p "$L/shim"
  printf '#!/bin/sh\necho probe-ran\n' >"$L/shim/autopilot-login-shell-probe"; chmod +x "$L/shim/autopilot-login-shell-probe"
  printf 'export PATH="%s/shim:$PATH"\n' "$L" >"$L/home/.zprofile"
  f="$L/probe.sh"; printf '# CMD: autopilot-login-shell-probe\nautopilot-login-shell-probe\n' >"$f"
  res="$(run_env "$f" SHELL="$ZSH_BIN")"; rc=$?
  [ "$rc" -eq 0 ] && ok "SHELL=zsh: a tool on PATH only via ~/.zprofile is found, gate green" || fail "SHELL=zsh: exit $rc ($res)"
  res="$(run_env "$f" SHELL="$REAL_BASH")"; rc=$?
  [ "$rc" -ne 0 ] && ok "SHELL=bash: bash never reads ~/.zprofile, the same gate is red" || fail "SHELL=bash: green although the tool is only on zsh's PATH"
  case "$res" in *"GATE RED"*"command not found"*) ok "red because the tool is not on bash's PATH";; *) fail "SHELL=bash output: $res";; esac

  # zsh runs what bash wrote: pipefail holds, and the %q-quoted cd of a cwd with spaces and
  # parentheses lands in the right directory.
  f="$L/pipe.sh"; printf '# CMD: false | cat\nfalse | cat\n' >"$f"
  run_env "$f" SHELL="$ZSH_BIN" >/dev/null; rc=$?
  [ "$rc" -ne 0 ] && ok "SHELL=zsh: pipefail keeps failure through a pipe" || fail "SHELL=zsh: pipefail lost the failure"
  mkdir -p "$P/apps/my web (x)"
  f="$L/cwd.sh"; printf 'cd %q || exit 1\n# CMD: pwd\npwd\n' "$P/apps/my web (x)" >"$f"
  res="$(run_env "$f" SHELL="$ZSH_BIN")"
  case "$res" in *"apps/my web (x)"*) ok "SHELL=zsh: the recorded cwd with spaces is honoured";; *) fail "SHELL=zsh cwd: $res";; esac
else
  echo "note - zsh not found, skipping the zsh login-shell tests"
fi
rm -rf "$L"

rm -rf "$P"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
