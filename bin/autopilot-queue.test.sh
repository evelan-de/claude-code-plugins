#!/usr/bin/env bash
# Tests for bin/autopilot-queue. Run: bash bin/autopilot-queue.test.sh
# Fake claude, gh, curl and osascript scripts record their arguments; no network, no real runs.
set -uo pipefail

BIN="$(cd "$(dirname "$0")" && pwd)"
TOOL="$BIN/autopilot-queue"
PASS=0; FAIL=0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

ok() { echo "ok   - $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL - $1"; FAIL=$((FAIL+1)); }
check() { # $1 desc, then the command that must succeed
  c_desc="$1"; shift
  if "$@"; then ok "$c_desc"; else fail "$c_desc"; fi
}
has() { printf '%s' "$2" | grep -qF -- "$1"; }   # $1 needle $2 haystack
lacks() { ! has "$1" "$2"; }
count_lines() { grep -c . "$1" 2>/dev/null; }
live_lines() { grep -c -v -E '^[[:space:]]*(#|$)' "$1" 2>/dev/null; }
is_main_clean() { [ "$(git -C "$proj" symbolic-ref --short HEAD)" = main ] && [ -z "$(git -C "$proj" status --porcelain)" ]; }

# ---------- fakes ----------
mkdir -p "$tmp/fakes"
cat >"$tmp/fakes/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_RECORD/claude.args"
case "${FAKE_SCENARIO:-}" in
  ok) echo OK; exit 0 ;;
  notloggedin) echo "Not logged in"; exit 1 ;;
esac
item="${2#/autopilot }"
case "$item" in
  docs/autopilot/sessions/*) sd="$item" ;;
  *) sd="docs/autopilot/sessions/2026-09-20-$(printf '%s' "$item" | tr -c 'A-Za-z0-9-' '-')" ;;
esac
n="$(grep -c . "$FAKE_RECORD/claude.args")"
if ! git symbolic-ref -q HEAD >/dev/null; then git checkout -q -B "feat/$(basename "$sd")"; fi
mkdir -p "$sd"
case "${FAKE_SCENARIO:-report}" in
  report) rm -f "$sd/HANDOFF.md"; printf '# REPORT\n\nshipped %s\n' "$item" >"$sd/REPORT.md" ;;
  handoff-then-report)
    if [ "$n" -eq 1 ]; then echo "# HANDOFF" >"$sd/HANDOFF.md"
    else rm -f "$sd/HANDOFF.md"; echo "# REPORT" >"$sd/REPORT.md"; fi ;;
  handoff-always) echo "# HANDOFF $n" >"$sd/HANDOFF.md" ;;
esac
git add -A >/dev/null
git -c user.name=t -c user.email=t@t commit -q -m "fake run $n"
echo '{"type":"result","total_cost_usd":0.1}'
EOF
cat >"$tmp/fakes/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_RECORD/gh.args"
prs="${FAKE_GH_PRS:-/nonexistent}"
case "$1 $2" in
  "auth status"|"label create"|"pr ready"|"pr edit"|"pr comment") exit 0 ;;
  "label list") printf '%s\n' autopilot-ready autopilot-done autopilot-blocked; exit 0 ;;
  "pr view") grep "^$3 " "$prs"; exit 0 ;;
  "pr list")
    case "$*" in
      *--label*) [ -f "$prs" ] && cat "$prs"; exit 0 ;;
      *--head*)
        [ -n "${FAKE_GH_NO_PR:-}" ] && exit 0
        b=""; while [ $# -gt 0 ]; do [ "$1" = --head ] && b="$2"; shift; done
        line="$(grep " $b " "$prs" 2>/dev/null | head -n 1)"
        if [ -n "$line" ]; then set -- $line; echo "$1 true $3"; else echo "7 true https://github.com/e/r/pull/7"; fi
        exit 0 ;;
    esac ;;
esac
exit 0
EOF
cat >"$tmp/fakes/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_RECORD/curl.args"
exit 0
EOF
cat >"$tmp/fakes/osascript" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_RECORD/osascript.args"
exit 0
EOF
chmod +x "$tmp/fakes"/*

# ---------- the project: a repo with main, an origin, and two PR branches ----------
proj="$tmp/proj"
git init -q -b main "$proj"
git -C "$proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git init -q --bare "$tmp/origin.git"
git -C "$proj" remote add origin "$tmp/origin.git"
git -C "$proj" push -q origin main
# PR branch with a plan
git -C "$proj" checkout -q -b feat/PAUL-9-thing
mkdir -p "$proj/docs/autopilot/sessions/2026-09-19-PAUL-9-thing"
echo "# PLAN" >"$proj/docs/autopilot/sessions/2026-09-19-PAUL-9-thing/PLAN.md"
git -C "$proj" add -A
git -C "$proj" -c user.name=t -c user.email=t@t commit -q -m "plan"
git -C "$proj" push -q origin feat/PAUL-9-thing
# PR branch without a plan
git -C "$proj" checkout -q main
git -C "$proj" checkout -q -b feat/PAUL-10-noplan
git -C "$proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "work"
git -C "$proj" push -q origin feat/PAUL-10-noplan
git -C "$proj" checkout -q main

export CLAUDE_BIN="$tmp/fakes/claude" GH_BIN="$tmp/fakes/gh"
export AUTOPILOT_QUEUE_WATCH_MIN=0 AUTOPILOT_QUEUE_NO_NOTIFY=1 AUTOPILOT_QUEUE_TIMEOUT_MIN=5
unset FAKE_GH_PRS FAKE_GH_NO_PR

# fresh_home <name>: new AUTOPILOT_QUEUE_HOME and record dir; sets QH and REC.
fresh_home() {
  QH="$tmp/home-$1"; REC="$tmp/rec-$1"
  mkdir -p "$QH" "$REC"
  export AUTOPILOT_QUEUE_HOME="$QH" FAKE_RECORD="$REC"
}

# ---------- (a) text item, REPORT.md -> done ----------
fresh_home a
export FAKE_SCENARIO=report
printf '# comment\n%s PAUL-1\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(a) run exits 0" [ "$got" -eq 0 ]
check "(a) queue.txt emptied" [ "$(live_lines "$QH/queue.txt")" = 0 ]
done_line="$(cat "$QH/done.txt" 2>/dev/null)"
check "(a) done.txt has status done and the PR url" grep -qE "^[0-9T:Z-]+ $proj PAUL-1 done https://github.com/e/r/pull/7( no-plan)?$" "$QH/done.txt"
check "(a) done.txt marks no-plan (PAUL-1 had none)" has " no-plan" "$done_line"
gh_args="$(cat "$REC/gh.args")"
check "(a) gh pr ready called" has "pr ready 7" "$gh_args"
check "(a) gh pr edit swaps labels to autopilot-done" has "pr edit 7 --remove-label autopilot-ready --add-label autopilot-done" "$gh_args"
check "(a) gh pr comment called" has "pr comment 7 --body-file" "$gh_args"
check "(a) claude started with /autopilot PAUL-1 and the launch flags" has "-p /autopilot PAUL-1 --model sonnet --effort medium --advisor fable --fallback-model opus --permission-mode auto --max-budget-usd 60 --output-format json" "$(cat "$REC/claude.args")"
check "(a) progress lines on stdout" has "[autopilot-queue] proj PAUL-1: done (PR https://github.com/e/r/pull/7" "$out"
check "(a) worktree removed after done" [ ! -e "$QH/worktrees/proj-PAUL-1/.git" ]
check "(a) main checkout untouched (still on main, clean)" is_main_clean
check "(a) log file written" ls "$QH"/logs/*-PAUL-1.log >/dev/null 2>&1

# ---------- (b) HANDOFF.md then REPORT.md -> done with restarts=1 ----------
fresh_home b
export FAKE_SCENARIO=handoff-then-report
printf '%s PAUL-2\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(b) run exits 0" [ "$got" -eq 0 ]
check "(b) claude called twice" [ "$(count_lines "$REC/claude.args")" = 2 ]
check "(b) done with restarts=1" grep -q " PAUL-2 done .* restarts=1" "$QH/done.txt"
check "(b) restart announced" has "hand-off found, restart 1/3" "$out"

# ---------- (c) HANDOFF.md every time -> handoff-limit ----------
fresh_home c
export FAKE_SCENARIO=handoff-always AUTOPILOT_QUEUE_MAX_RESTARTS=2
printf '%s PAUL-3\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(c) run exits 0" [ "$got" -eq 0 ]
check "(c) claude called 1 + MAX_RESTARTS times" [ "$(count_lines "$REC/claude.args")" = 3 ]
check "(c) status handoff-limit in done.txt" grep -q " PAUL-3 handoff-limit " "$QH/done.txt"
check "(c) PR labelled autopilot-blocked" has "pr edit 7 --remove-label autopilot-ready --add-label autopilot-blocked" "$(cat "$REC/gh.args")"
check "(c) worktree kept" [ -e "$QH/worktrees/proj-PAUL-3/.git" ]
unset AUTOPILOT_QUEUE_MAX_RESTARTS

# ---------- (d) PR items from repos.txt ----------
fresh_home d
export FAKE_SCENARIO=report
printf '11 feat/PAUL-9-thing https://github.com/e/r/pull/11\n12 feat/PAUL-10-noplan https://github.com/e/r/pull/12\n' >"$REC/prs.txt"
export FAKE_GH_PRS="$REC/prs.txt"
printf '%s\n' "$proj" >"$QH/repos.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(d) run exits 0" [ "$got" -eq 0 ]
cl="$(cat "$REC/claude.args")"
check "(d) PR 11 run with the session dir found on its branch" has "/autopilot docs/autopilot/sessions/2026-09-19-PAUL-9-thing " "$cl"
check "(d) PR 12 run with the ticket key from the branch name" has "/autopilot PAUL-10 " "$cl"
check "(d) PR 11 done without no-plan" grep -q " docs/autopilot/sessions/2026-09-19-PAUL-9-thing done https://github.com/e/r/pull/11$" "$QH/done.txt"
check "(d) PR 12 done and marked no-plan" grep -q " PAUL-10 done https://github.com/e/r/pull/12 no-plan$" "$QH/done.txt"
gh_args="$(cat "$REC/gh.args")"
check "(d) labels swapped on PR 11" has "pr edit 11 --remove-label autopilot-ready --add-label autopilot-done" "$gh_args"
check "(d) labels swapped on PR 12" has "pr edit 12 --remove-label autopilot-ready --add-label autopilot-done" "$gh_args"
check "(d) main checkout still on main, clean" is_main_clean
unset FAKE_GH_PRS

# ---------- (e) list prints both sources without running ----------
fresh_home e
printf '%s PAUL-4\n%s "Move the picker"\n' "$proj" "$proj" >"$QH/queue.txt"
printf '%s\n' "$proj" >"$QH/repos.txt"
printf '11 feat/PAUL-9-thing https://github.com/e/r/pull/11\n' >"$REC/prs.txt"
export FAKE_GH_PRS="$REC/prs.txt"
out="$(sh "$TOOL" list 2>&1)"; got=$?
check "(e) list exits 0" [ "$got" -eq 0 ]
check "(e) list shows the ticket item" has "queue  $proj  PAUL-4 (no plan)" "$out"
check "(e) list shows the quoted topic" has "queue  $proj  \"Move the picker\" (no plan)" "$out"
check "(e) list shows the labelled PR" has "pr     $proj  #11 feat/PAUL-9-thing https://github.com/e/r/pull/11" "$out"
check "(e) list did not start claude" [ ! -e "$REC/claude.args" ]
check "(e) list left queue.txt alone" [ "$(live_lines "$QH/queue.txt")" = 2 ]
unset FAKE_GH_PRS

# ---------- (f) add quoting ----------
fresh_home f
sh "$TOOL" add "$proj" PAUL-5 >/dev/null
sh "$TOOL" add "$proj" Move the picker into the composer >/dev/null
check "(f) add writes a plain item unquoted" grep -qxF "$proj PAUL-5" "$QH/queue.txt"
check "(f) add quotes an item with spaces" grep -qxF "$proj \"Move the picker into the composer\"" "$QH/queue.txt"
out="$(sh "$TOOL" add "$tmp/nowhere" X 2>&1)"; got=$?
check "(f) add refuses a non-repo (exit 1)" [ "$got" -eq 1 ]
check "(f) add names the reason" has "not a git repository" "$out"

# ---------- (g) doctor ----------
fresh_home g
printf '%s\n' "$proj" >"$QH/repos.txt"
export FAKE_SCENARIO=notloggedin
out="$(sh "$TOOL" doctor 2>&1)"; got=$?
check "(g) doctor exits 1 when claude is not logged in" [ "$got" -eq 1 ]
check "(g) doctor explains the Keychain-over-SSH caveat" has "Keychain" "$out"
export FAKE_SCENARIO=ok
printf 'SLACK_WEBHOOK_URL=x\n' >"$QH/env"; chmod 644 "$QH/env"
out="$(sh "$TOOL" doctor 2>&1)"; got=$?
check "(g) doctor exits 1 on env mode 644" [ "$got" -eq 1 ]
check "(g) doctor names the wanted mode" has "want 600" "$out"
chmod 600 "$QH/env"
out="$(sh "$TOOL" doctor 2>&1)"; got=$?
check "(g) doctor passes with login, gh, repo, labels, env 600" [ "$got" -eq 0 ]
check "(g) doctor reports all checks passed" has "all checks passed" "$out"
check "(g) doctor checked the labels" has "label autopilot-blocked in proj" "$out"

# ---------- (h) lock ----------
fresh_home h
export FAKE_SCENARIO=report
printf '%s PAUL-6\n' "$proj" >"$QH/queue.txt"
mkdir -p "$QH/run.lock"; echo "$$" >"$QH/run.lock/pid"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(h) second run refused while the lock is held by a live pid" [ "$got" -eq 1 ]
check "(h) refusal names the lock" has "another run is active" "$out"
check "(h) refused run did not start claude" [ ! -e "$REC/claude.args" ]
echo 999999 >"$QH/run.lock/pid"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(h) stale lock (dead pid) is taken over" [ "$got" -eq 0 ]
check "(h) lock released after the run" [ ! -e "$QH/run.lock" ]

# ---------- (i) no secret printed ----------
fresh_home i
export FAKE_SCENARIO=report
unset AUTOPILOT_QUEUE_NO_NOTIFY
secret="https://hooks.slack.com/services/T000/B000/SECRETXYZ"
printf 'SLACK_WEBHOOK_URL=%s\n' "$secret" >"$QH/env"; chmod 600 "$QH/env"
printf '%s PAUL-7\n' "$proj" >"$QH/queue.txt"
out="$(PATH="$tmp/fakes:$PATH" sh "$TOOL" run 2>&1)"; got=$?
check "(i) run exits 0 with notifications on" [ "$got" -eq 0 ]
check "(i) Slack webhook was called" has "SECRETXYZ" "$(cat "$REC/curl.args" 2>/dev/null)"
check "(i) macOS notification was sent" has "PAUL-7: done" "$(cat "$REC/osascript.args" 2>/dev/null)"
check "(i) stdout never contains the webhook URL" lacks "SECRETXYZ" "$out"
check "(i) logs never contain the webhook URL" lacks "SECRETXYZ" "$(cat "$QH"/logs/*.log)"
export AUTOPILOT_QUEUE_NO_NOTIFY=1

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
