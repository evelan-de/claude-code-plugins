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

# $1 label, then the commands: each must pass through untouched, with nothing on stderr
assert_passthrough() {
  local label="$1" c out; shift
  for c in "$@"; do
    out="$(hook_json "$P" "$c" | hook 2>&1)"
    [ "$out" = "{}" ] && ok "$label: $c" || fail "$label: $c (got $out)"
  done
}
# $1 label, then the commands: each must be rewritten to the filter's run mode
assert_rewrites() {
  local label="$1" c out new; shift
  for c in "$@"; do
    out="$(hook_json "$P" "$c" | hook)"
    new="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
    case "$new" in *autopilot-gate-filter.sh\"\ run\ *) ok "$label: $c";; *) fail "$label: $c (got: $out)";; esac
  done
}

if ! command -v jq >/dev/null 2>&1; then echo "SKIP - jq not installed"; exit 0; fi

P="$(mk_project)"
out="$(hook_json "$P" "pnpm test" | hook)"
[ "$out" = "{}" ] && ok "no autopilot.json -> {}" || fail "no autopilot.json (got $out)"

echo '{ "gate": "pnpm test" }' >"$P/.claude/autopilot.json"

# passthrough cases (must NOT rewrite)
assert_passthrough "passthrough" "git status --short" "pnpm test # raw" "test -f .env && echo ok" "[ -d x ] || test -d y" "if true; then test 1; fi" "docker build ." "git checkout build" "mkdir build" "git test-branch"

# runner cases (must rewrite)
assert_rewrites "rewrites" "pnpm test 2>&1" "npm run lint" "npx vitest run src/x.test.ts" "yarn typecheck" "cd apps/web && pnpm run check-types" "npx tsc --noEmit" "bun run build" "npm run build:docs" "pnpm --filter web run test" "pnpm -r test" "yarn workspace foo test" "pnpm exec playwright test" "timeout 600 pnpm test"

# in front of a runner: NAME=value assignments, env, cross-env, timeout, an export (must rewrite)
assert_rewrites "rewrites with an env prefix" "TZ=Europe/Berlin npm run lint" "env TZ=UTC npm run test" "TZ=UTC LANG=C pnpm test" "FOO=\"a b\" npm test" "env TZ=UTC timeout 600 npm test" "timeout 600 env TZ=UTC npm test" "cross-env TZ=UTC npm test" "npx cross-env TZ=UTC npm run lint" "export TZ=Europe/Berlin; npm run typecheck && npm test" "cd apps/web && TZ=UTC npx vitest run"
# an assignment or env in front of something that is no runner passes through
assert_passthrough "passthrough" "TZ=UTC git status" "env" "env TZ=UTC date" "FOO=bar" "cross-env TZ=UTC node server.js" "timeout 5 curl -s localhost"

# the project's own gate commands: a script called gate, and whatever autopilot.json names
echo '{ "gate": "npm run gate", "gateFull": "./check.sh --mode=a.b (all)" }' >"$P/.claude/autopilot.json"
assert_rewrites "rewrites the project's gate" "npm run gate" "npm run gate:full" "TZ=Europe/Berlin npm run gate" "env TZ=UTC npm run gate" "cd apps/web && npm run gate" "./check.sh --mode=a.b (all)" "CI=1 ./check.sh --mode=a.b (all) 2>&1"
# a command that only mentions the gate, or looks like it, passes through; # raw still bypasses
assert_passthrough "passthrough" "echo run the gate" "git commit -m 'gate green'" "echo npm run gate" "grep gate package.json" "cat .claude/autopilot-gate.log" "./check.sh --mode=aXb (all)" "./check.sh --mode=a.b (all)-docs" "npm run gate # raw" "TZ=Europe/Berlin npm run gate # raw"
# a gate command inside quotes, a heredoc body or a comment is text, not a command
assert_passthrough "passthrough (quoted)" \
  $'cat <<EOF > notes.md\nnpm run gate\nEOF' \
  $'cat <<\'EOF\'\nTZ=UTC npm test\nEOF' \
  $'cat <<-EOF\n\tnpm run gate\n\tEOF' \
  $'cat <<EOF <<MORE\nx\nEOF\nnpm run gate\nMORE' \
  'git commit -m "wip (FOO=1 npm test fails)"' \
  "git commit -m 'x; npm run gate now logs'" \
  'echo "x (./check.sh --mode=a.b (all))"' \
  'git commit -m $'"'"'fix\n\nTZ=UTC npm test'"'"'' \
  $'git commit -m "fix\n\nTZ=UTC npm test"' \
  $'git commit -m $\'fix\n\nTZ=UTC npm test\'' \
  'git status # then npm test' \
  'echo "and then npm test"' \
  'echo "a \" ; npm test"' \
  $'echo "unterminated\nnpm run gate'
# ... while a real second command, also after a heredoc or a continued line, still counts
assert_rewrites "rewrites (second command)" \
  $'cd apps/web &&\nnpm run gate' \
  $'cat <<EOF\nnotes\nEOF\nnpm run gate' \
  $'TZ=UTC \\\n  npm test' \
  'echo "done" ; npm run gate' \
  "echo 'it''s' && npm run gate"

# assignment values with substitutions and escaped quotes, env with options
assert_rewrites "rewrites with an env prefix" 'FOO=$(date) npm test' 'FOO="a \"b\"" npm test' "FOO='a b'c npm test" 'env -i TZ=UTC npm test' 'env -u FOO npm test' 'env --ignore-environment npm test' 'env -i -u FOO TZ=UTC npm run gate'
assert_passthrough "passthrough" 'env -i' 'env -u FOO printenv'

# the project's gate counts as a whole command: followed by an operator or a redirect it is
# the gate, followed by further arguments it is another command
assert_rewrites "rewrites the project's gate" "./check.sh --mode=a.b (all)>out.txt" "./check.sh --mode=a.b (all);echo done" "./check.sh --mode=a.b (all) | tail -n 5" "npm run gate;echo done" "npm run gate>out.txt" "npx tsc --noEmit;echo done"
assert_passthrough "passthrough" "./check.sh --mode=a.b (all) --help" "./check.sh --mode=a.b (all) extra"
echo '{ "gate": "make" }' >"$P/.claude/autopilot.json"
assert_rewrites "rewrites the project's gate" "make" "TZ=UTC make 2>&1"
assert_passthrough "passthrough" "make -C docs html" "make clean" "cmake ." "git commit -m make"
# the gate string is read trimmed; a gate of several lines is no single command to recognise
printf '{ "gate": "  ./a.sh \\n", "gateFull": "\\n" }\n' >"$P/.claude/autopilot.json"
assert_rewrites "rewrites the trimmed gate" "./a.sh"
assert_passthrough "passthrough (blank gateFull)" "git status"
printf '{ "gate": "./a.sh\\n./b.sh" }\n' >"$P/.claude/autopilot.json"
assert_passthrough "passthrough (gate of several lines)" "./a.sh" "./b.sh" "git status"
# a config without a usable gate does not break the hook
echo '{ "gate": "", "gateFull": 7 }' >"$P/.claude/autopilot.json"
out="$(hook_json "$P" "git status" | hook)"
[ "$out" = "{}" ] && ok "empty gate in autopilot.json: other commands pass through" || fail "empty gate: $out"
out="$(hook_json "$P" "pnpm test" | hook)"
case "$out" in *autopilot-gate-filter.sh*) ok "empty gate in autopilot.json: runners are still rewritten";; *) fail "empty gate: runner not rewritten ($out)";; esac

# the evidence line keeps the whole command, env prefix included, and the prefix is in effect
echo '{ "gate": "printenv TZ" }' >"$P/.claude/autopilot.json"
out="$(hook_json "$P" "TZ=Europe/Berlin printenv TZ" | hook)"
new="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
res="$(cd "$P" && CLAUDE_PROJECT_DIR="$P" bash -c "$new")"; rc=$?
[ -n "$new" ] && [ "$rc" -eq 0 ] && ok "the rewritten gate with an env prefix runs green" || fail "env-prefixed gate: rewritten to '$new', exit $rc ($res)"
case "$res" in *"GATE GREEN"*"Europe/Berlin"*) ok "the env prefix is in effect for the gate";; *) fail "env prefix not in effect: $res";; esac
grep -q -E 'exit=0.*cmd=TZ=Europe/Berlin printenv TZ$' "$P/.claude/autopilot-gate.log" \
  && ok "the evidence line keeps the env prefix" || fail "evidence line: $(tail -n1 "$P/.claude/autopilot-gate.log" 2>/dev/null)"
# a gate made of several commands gets its environment through an export in front: every
# command of the chain runs with it, and the gate string as a whole is recognised
echo '{ "gate": "export TZ=Europe/Berlin; printenv TZ && printenv TZ" }' >"$P/.claude/autopilot.json"
out="$(hook_json "$P" "export TZ=Europe/Berlin; printenv TZ && printenv TZ" | hook)"
new="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
res="$(cd "$P" && CLAUDE_PROJECT_DIR="$P" bash -c "$new")"; rc=$?
[ -n "$new" ] && [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$res" | grep -c '^Europe/Berlin$')" = 2 ] \
  && ok "an exported environment reaches every command of a chained gate" || fail "chained gate with export: '$new' exit $rc ($res)"
grep -q -E 'cmd=export TZ=Europe/Berlin; printenv TZ && printenv TZ$' "$P/.claude/autopilot-gate.log" \
  && ok "the evidence line of a chained gate equals the gate string" || fail "chained gate evidence: $(tail -n1 "$P/.claude/autopilot-gate.log")"
echo '{ "gate": "pnpm test" }' >"$P/.claude/autopilot.json"

# cmdfile: a `# CWD:` line, then the command verbatim
out="$(hook_json "$P" "pnpm test -- --reporter=dot" "$P/apps/web" | hook)"
cmdfile="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command' | sed -E 's/.* run "([^"]+)"$/\1/')"
[ "$(head -n1 "$cmdfile")" = "# CWD: $P/apps/web" ] && ok "cmdfile starts with the caller cwd" || fail "cmdfile cwd: $(head -n1 "$cmdfile")"
[ "$(tail -n +2 "$cmdfile")" = "pnpm test -- --reporter=dot" ] && ok "cmdfile holds the original command" || fail "cmdfile body: $(tail -n +2 "$cmdfile")"

# $1 cwd, $2 command -> a command file
mkcmd() { local f; f="$(mktemp)"; printf '# CWD: %s\n%s\n' "$1" "$2" >"$f"; echo "$f"; }
run_mode() { CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/autopilot-gate-filter.sh" run "$@"; }
last_cmd() { tail -n1 "$P/.claude/autopilot-gate.log" | sed $'s/.*\\tcmd=//'; }

# run mode: cwd honoured and named in the evidence when it is not the project root
f="$(mkcmd "$P/apps/web" "pwd")"
res="$(run_mode "$f")"
case "$res" in *apps/web*) ok "run mode executes in the recorded cwd";; *) fail "run cwd: $res";; esac
[ "$(last_cmd)" = "cd apps/web && pwd" ] && ok "a run below the project root is logged as cd <dir> && <command>" || fail "cwd evidence: $(last_cmd)"
f="$(mkcmd "$P" "pwd")"; run_mode "$f" >/dev/null
[ "$(last_cmd)" = "pwd" ] && ok "a run in the project root is logged as the command alone" || fail "root evidence: $(last_cmd)"

# run mode: the evidence is what ran, never a declared command
f="$(mkcmd "$P" "$(printf '# CMD: npm run gate\ntrue')")"; run_mode "$f" >/dev/null
[ "$(last_cmd)" = '# CMD: npm run gate\ntrue' ] && ok "a declared command is logged as the comment it is, line breaks as \\n" || fail "declared command evidence: $(last_cmd)"
f="$(mktemp)"; printf 'true\n' >"$f"
res="$(run_mode "$f" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && case "$res" in *"# CWD:"*) ok "run mode refuses a command file without the cwd line";; *) fail "no-cwd message: $res";; esac || fail "no-cwd exit $rc"
f="$(mkcmd "$P/missing" "true")"
run_mode "$f" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "run mode refuses a cwd that does not exist" || fail "missing cwd exit $rc"

# run mode: green
f="$(mkcmd "$P" 'seq 1 50; echo "Tests  12 passed (12)"')"
res="$(run_mode "$f")"; rc=$?
[ "$rc" -eq 0 ] && ok "green run exits 0" || fail "green run exit (got $rc)"
case "$res" in *"GATE GREEN"*"12 passed"*) ok "green run prints GREEN + summary";; *) fail "green output: $res";; esac
lines="$(printf '%s\n' "$res" | wc -l | tr -d ' ')"
[ "$lines" -le 14 ] && ok "green run suppresses body ($lines lines)" || fail "green run too long ($lines lines)"
[ "$(last_cmd)" = 'seq 1 50; echo "Tests  12 passed (12)"' ] && ok "green run logged with the whole command" || fail "green run log: $(last_cmd)"
grep -q -E $'\\texit=0\\tcmd=seq' "$P/.claude/autopilot-gate.log" && ok "green run logged with exit=0" || fail "green run log: $(tail -n1 "$P/.claude/autopilot-gate.log")"

# run mode: red keeps exit code, shows failures
f="$(mkcmd "$P" "$(printf 'echo "noise 1"\necho "FAIL src/x.test.ts > adds"\necho "AssertionError: expected 2 to be 3"\necho "Tests  1 failed | 11 passed (12)"\nexit 3')")"
res="$(run_mode "$f")"; rc=$?
[ "$rc" -eq 3 ] && ok "red run keeps exit 3" || fail "red run exit (got $rc)"
case "$res" in *"GATE RED (exit 3)"*"AssertionError"*"1 failed"*) ok "red run prints RED + failure + summary";; *) fail "red output: $res";; esac
grep -q -E $'\\texit=3\\t' "$P/.claude/autopilot-gate.log" && ok "red run logged with exit=3" || fail "red run log missing"

# pipefail honoured
f="$(mkcmd "$P" "false | cat")"
run_mode "$f" >/dev/null; rc=$?
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
f="$L/echo.sh"; printf '# CWD: %s\necho hi\n' "$P" >"$f"
res="$(run_env "$f" SHELL="$L/sh/bash")"; rc=$?
[ "$rc" -eq 0 ] && ok "SHELL=bash: green run through that shell" || fail "SHELL=bash: exit $rc ($res)"
[ "$(head -n3 "$L/sh/bash.args" 2>/dev/null)" = "$(printf -- '-l\n-o\npipefail')" ] && [ "$(sed -n 4p "$L/sh/bash.args" 2>/dev/null)" != "$f" ] \
  && ok "run mode calls \$SHELL -l -o pipefail <its own script>" \
  || fail "\$SHELL was not called as -l -o pipefail <script> (args: $(tr '\n' ' ' 2>/dev/null <"$L/sh/bash.args"))"
# Any other shell (dash rejects -o pipefail, csh -l), an empty SHELL or a missing binary: bash
# (not sh, which on macOS is bash in POSIX mode).
f="$L/is-bash.sh"; printf '# CWD: %s\n[ ${#BASH_VERSION} -gt 0 ] && ! shopt -oq posix\n' "$P" >"$f"
res="$(run_env "$f" SHELL="$L/sh/dash")"; rc=$?
[ "$rc" -eq 0 ] && ok "SHELL=dash: the command runs in bash (green only there)" || fail "SHELL=dash: exit $rc ($res)"
[ ! -f "$L/sh/dash.args" ] && ok "SHELL=dash: dash was not called" || fail "dash was called"
res="$(run_env "$f" SHELL=)"; rc=$?
[ "$rc" -eq 0 ] && ok "empty SHELL: the command runs in bash" || fail "empty SHELL: exit $rc ($res)"
res="$(run_env "$f" SHELL="$L/missing/zsh")"; rc=$?
[ "$rc" -eq 0 ] && ok "SHELL names a missing zsh: the command runs in bash" || fail "missing zsh: exit $rc ($res)"

ZSH_BIN="$(command -v zsh || true)"
if [ -n "$ZSH_BIN" ]; then
  f="$L/is-zsh.sh"; printf '# CWD: %s\n[ ${#ZSH_VERSION} -gt 0 ]\n' "$P" >"$f"
  res="$(run_env "$f" SHELL="$ZSH_BIN")"; rc=$?
  [ "$rc" -eq 0 ] && ok "SHELL=zsh: the command runs in zsh (green only there)" || fail "SHELL=zsh: exit $rc ($res)"
  # The finding this guards: node/pnpm on PATH only through zsh's startup files. ~/.zprofile is
  # read by login shells only, so green here also proves -l; the probe name exists nowhere else.
  mkdir -p "$L/shim"
  printf '#!/bin/sh\necho probe-ran\n' >"$L/shim/autopilot-login-shell-probe"; chmod +x "$L/shim/autopilot-login-shell-probe"
  printf 'export PATH="%s/shim:$PATH"\n' "$L" >"$L/home/.zprofile"
  f="$L/probe.sh"; printf '# CWD: %s\nautopilot-login-shell-probe\n' "$P" >"$f"
  res="$(run_env "$f" SHELL="$ZSH_BIN")"; rc=$?
  [ "$rc" -eq 0 ] && ok "SHELL=zsh: a tool on PATH only via ~/.zprofile is found, gate green" || fail "SHELL=zsh: exit $rc ($res)"
  res="$(run_env "$f" SHELL="$REAL_BASH")"; rc=$?
  [ "$rc" -ne 0 ] && ok "SHELL=bash: bash never reads ~/.zprofile, the same gate is red" || fail "SHELL=bash: green although the tool is only on zsh's PATH"
  case "$res" in *"GATE RED"*"command not found"*) ok "red because the tool is not on bash's PATH";; *) fail "SHELL=bash output: $res";; esac

  # zsh runs what bash wrote: pipefail holds, and the %q-quoted cd of a cwd with spaces and
  # parentheses lands in the right directory.
  f="$L/pipe.sh"; printf '# CWD: %s\nfalse | cat\n' "$P" >"$f"
  run_env "$f" SHELL="$ZSH_BIN" >/dev/null; rc=$?
  [ "$rc" -ne 0 ] && ok "SHELL=zsh: pipefail keeps failure through a pipe" || fail "SHELL=zsh: pipefail lost the failure"
  mkdir -p "$P/apps/my web (x)"
  f="$L/cwd.sh"; printf '# CWD: %s\npwd\n' "$P/apps/my web (x)" >"$f"
  res="$(run_env "$f" SHELL="$ZSH_BIN")"
  case "$res" in *"apps/my web (x)"*) ok "SHELL=zsh: the recorded cwd with spaces is honoured";; *) fail "SHELL=zsh cwd: $res";; esac
else
  echo "note - zsh not found, skipping the zsh login-shell tests"
fi
rm -rf "$L"

rm -rf "$P"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
