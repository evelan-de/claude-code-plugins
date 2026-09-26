#!/usr/bin/env bash
# Tests for bin/mission-control. Run: bash bin/mission-control.test.sh
# Fake claude, gh, curl and osascript scripts record their arguments; no network, no real runs.
set -uo pipefail

BIN="$(cd "$(dirname "$0")" && pwd)"
TOOL="$BIN/mission-control"
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
commit() { git -C "$1" -c user.name=t -c user.email=t@t commit -q "${@:2}"; }

# ---------- fakes ----------
mkdir -p "$tmp/fakes"
cat >"$tmp/fakes/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_RECORD/claude.args"
case "${FAKE_SCENARIO:-}" in
  ok) echo OK; exit 0 ;;
  notloggedin) echo "Not logged in"; exit 1 ;;
  noop) echo '{"type":"result"}'; exit 0 ;;
  sleep) echo "$$" >"$FAKE_RECORD/claude.pid"; exec sleep 30 ;;
esac
item="${2#/autopilot }"
case "$item" in
  docs/autopilot/sessions/*) sd="$item" ;;
  *) sd="docs/autopilot/sessions/2026-09-20-$(printf '%s' "$item" | tr -c 'A-Za-z0-9-' '-')" ;;
esac
n="$(grep -c . "$FAKE_RECORD/claude.args")"
[ -f .claude/.autopilot-active ] && echo "attempt $n" >>"$FAKE_RECORD/sentinel.seen"
[ -f "$FAKE_RECORD/jira.args" ] && cp "$FAKE_RECORD/jira.args" "$FAKE_RECORD/jira-at-claude-start.$n"
mkdir -p .claude; echo "2026-09-21T00:00:00Z ctx=1 tool=Bash" >.claude/.autopilot-status
if ! git symbolic-ref -q HEAD >/dev/null; then git checkout -q -B "feat/$(basename "$sd")"; fi
git log --oneline -20 >"$FAKE_RECORD/claude.gitlog.$n"
mkdir -p "$sd"
case "${FAKE_SCENARIO:-report}" in
  report) rm -f "$sd/HANDOFF.md"; printf 'Status: done\n\n# REPORT\n\nshipped %s\n' "$item" >"$sd/REPORT.md" ;;
  report-blocked) printf 'Status: blocked - cannot reach the API\n\n# REPORT\n' >"$sd/REPORT.md" ;;
  report-nostatus) printf '# REPORT\n\nno status here\n' >"$sd/REPORT.md" ;;
  handoff-then-report)
    if [ "$n" -eq 1 ]; then echo "# HANDOFF" >"$sd/HANDOFF.md"
    else rm -f "$sd/HANDOFF.md"; printf 'Status: done\n' >"$sd/REPORT.md"; fi ;;
  handoff-always) echo "# HANDOFF $n" >"$sd/HANDOFF.md" ;;
  early-exit-then-report)
    # first attempt commits work but ends its turn without REPORT.md or HANDOFF.md
    if [ "$n" -eq 1 ]; then echo "wip" >"$sd/NOTES.md"
    else printf 'Status: done\n' >"$sd/REPORT.md"; fi ;;
  early-exit-always) echo "wip $n" >"$sd/NOTES.md" ;;
  handoff-then-abort)
    if [ "$n" -eq 1 ]; then echo "# HANDOFF" >"$sd/HANDOFF.md"
    else sleep 1; printf 'Status: blocked - gate needs a database\n' >"$sd/REPORT.md"; fi ;;
  budget) echo '{"type":"result","subtype":"error_max_budget_usd","is_error":true,"total_cost_usd":60.1}'; exit 1 ;;
esac
git add -A -- . ':!.claude' >/dev/null
git -c user.name=t -c user.email=t@t commit -q -m "fake run $n"
echo '{"type":"result","total_cost_usd":0.1}'
EOF
cat >"$tmp/fakes/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_RECORD/gh.args"
prs="${FAKE_GH_PRS:-/nonexistent}"
case "$*" in *"${FAKE_GH_FAIL:-@@none@@}"*) echo "fake gh: failing on purpose" >&2; exit 1 ;; esac
if [ "$1 $2" = "auth status" ] && [ -n "${FAKE_GH_AUTH_FAIL:-}" ]; then
  echo "You are not logged into any GitHub hosts. To log in, run: gh auth login" >&2; exit 1
fi
case "$1 $2" in
  "auth status"|"label create"|"pr ready"|"pr edit") exit 0 ;;
  "pr comment")
    n="$(ls "$FAKE_RECORD" | grep -c '^comment\.')"
    while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$FAKE_RECORD/comment.$((n+1))"; shift; done
    exit 0 ;;
  "label list") printf '%s\n' ${FAKE_GH_LABELS-autopilot-ready autopilot-done autopilot-blocked}; exit 0 ;;
  "pr view")
    # prs.txt lines: <number> <head branch> <url> [<base branch, default main>]
    case "$*" in *"--json author"*) echo andreas; exit 0 ;; esac
    grep "^$3 " "$prs" | awk '{ print $1, $2, ($4 != "" ? $4 : "main"), $3 }'; exit 0 ;;
  "repo view") echo e/r; exit 0 ;;
  "api "*)
    # review-bot comments: FAKE_REVIEW_INLINE / FAKE_REVIEW_TOP hold the login lists
    apipath="$2"; jqexpr=""; while [ $# -gt 0 ]; do [ "$1" = --jq ] && jqexpr="$2"; shift; done
    case "$apipath" in
      */pulls/*/comments) logins="${FAKE_REVIEW_INLINE:-}" ;;
      */issues/*/comments) logins="${FAKE_REVIEW_TOP:-}" ;;
      *) exit 1 ;;
    esac
    # each login may carry a thread spec: "bot:1" = comment id 1 starting a thread,
    # "andreas>1" = the author's reply to comment 1; a bare login is a thread start with a fresh id
    json="["; i=100
    for spec in $logins; do
      i=$((i+1))
      case "$spec" in
        *'>'*) l="${spec%%>*}"; json="$json{\"id\":$i,\"user\":{\"login\":\"$l\"},\"in_reply_to_id\":${spec#*>}}," ;;
        *:*) l="${spec%%:*}"; json="$json{\"id\":${spec#*:},\"user\":{\"login\":\"$l\"},\"in_reply_to_id\":null}," ;;
        *) json="$json{\"id\":$i,\"user\":{\"login\":\"$spec\"},\"in_reply_to_id\":null}," ;;
      esac
    done; json="${json%,}]"
    printf '%s' "$json" | jq "$jqexpr"; exit 0 ;;
  "pr list")
    case "$*" in
      *--label*) [ -f "$prs" ] && awk '{ print $1, $2, $3 }' "$prs"; exit 0 ;;
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
cat >"$tmp/fakes/jira" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_RECORD/jira.args"
[ -n "${FAKE_JIRA_FAIL:-}" ] && { echo "jira: HTTP 401 on GET /rest/api/2/myself: Unauthorized" >&2; exit 1; }
case "$1" in
  start) echo "started: $2  In Arbeit  Andreas Straub  Do the thing" ;;
  comment) n="$(ls "$FAKE_RECORD" | grep -c '^jira-comment\.')"; cat >"$FAKE_RECORD/jira-comment.$((n+1))"; echo "commented: $2 comment 9001 (12 chars read back)" ;;
esac
exit 0
EOF
cat >"$tmp/fakes/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_RECORD/curl.args"
exit "${FAKE_CURL_EXIT:-0}"
EOF
cat >"$tmp/fakes/osascript" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_RECORD/osascript.args"
exit 0
EOF
chmod +x "$tmp/fakes"/*

# ---------- the project: a repo with main, an origin, and feature branches ----------
proj="$tmp/proj"
git init -q -b main "$proj"
commit "$proj" --allow-empty -m init
# an old, unrelated session with a REPORT.md on main (must never count for another item)
mkdir -p "$proj/docs/autopilot/sessions/2026-01-01-OLD-1-unrelated"
printf 'Status: done\n' >"$proj/docs/autopilot/sessions/2026-01-01-OLD-1-unrelated/REPORT.md"
# a planned session on main with an Effort header
mkdir -p "$proj/docs/autopilot/sessions/2026-09-18-PAUL-20-effort"
printf '# PLAN\n\nEffort: high\n' >"$proj/docs/autopilot/sessions/2026-09-18-PAUL-20-effort/PLAN.md"
# planned sessions on main with a Model header
mkdir -p "$proj/docs/autopilot/sessions/2026-09-25-PAUL-160-opus" "$proj/docs/autopilot/sessions/2026-09-25-PAUL-161-sonnet" \
  "$proj/docs/autopilot/sessions/2026-09-25-PAUL-162-sonnetmax"
printf '# PLAN\nModel: opus\nEffort: medium\n' >"$proj/docs/autopilot/sessions/2026-09-25-PAUL-160-opus/PLAN.md"
printf '# PLAN\nModel: sonnet   (sonnet | opus)\nEffort: medium\n' >"$proj/docs/autopilot/sessions/2026-09-25-PAUL-161-sonnet/PLAN.md"
printf '# PLAN\nModel: Sonnet\nEffort: max\n' >"$proj/docs/autopilot/sessions/2026-09-25-PAUL-162-sonnetmax/PLAN.md"
git -C "$proj" add -A; commit "$proj" -m "sessions on main"
git init -q --bare "$tmp/origin.git"
git -C "$proj" remote add origin "$tmp/origin.git"
git -C "$proj" push -q origin main
# PR branch with a plan
git -C "$proj" checkout -q -b feat/PAUL-9-thing
mkdir -p "$proj/docs/autopilot/sessions/2026-09-19-PAUL-9-thing"
printf '# PLAN - PAUL-9 - 2026-09-19\nBranch: feat/PAUL-9-thing   Base: main   Ticket: PAUL-9\nEffort: medium\n' >"$proj/docs/autopilot/sessions/2026-09-19-PAUL-9-thing/PLAN.md"
git -C "$proj" add -A; commit "$proj" -m "plan"
git -C "$proj" push -q origin feat/PAUL-9-thing
# PR branch without a plan
git -C "$proj" checkout -q main
git -C "$proj" checkout -q -b feat/PAUL-10-noplan
commit "$proj" --allow-empty -m "work"
git -C "$proj" push -q origin feat/PAUL-10-noplan
# a session dir committed only on a feature branch (list item with a branch)
git -C "$proj" checkout -q main
git -C "$proj" checkout -q -b feat/PAUL-21-branchy
mkdir -p "$proj/docs/autopilot/sessions/2026-09-18-PAUL-21-branchy"
printf '# PLAN\n\nModel: opus\nEffort: low\n' >"$proj/docs/autopilot/sessions/2026-09-18-PAUL-21-branchy/PLAN.md"
git -C "$proj" add -A; commit "$proj" -m "plan on branch"
git -C "$proj" push -q origin feat/PAUL-21-branchy
# PR branch whose plan names an unknown model
git -C "$proj" checkout -q main
git -C "$proj" checkout -q -b feat/PAUL-163-bogus
mkdir -p "$proj/docs/autopilot/sessions/2026-09-25-PAUL-163-bogus"
printf '# PLAN\nModel: gpt-5\nEffort: high\n' >"$proj/docs/autopilot/sessions/2026-09-25-PAUL-163-bogus/PLAN.md"
git -C "$proj" add -A; commit "$proj" -m "plan with an unknown model"
git -C "$proj" push -q origin feat/PAUL-163-bogus
# PRs that target preview, as in jexity-chatbot #276/#277: preview holds a finished session
# that main does not have yet; PR branches start from preview and add their own plan
git -C "$proj" checkout -q main
git -C "$proj" checkout -q -b preview
mkdir -p "$proj/docs/autopilot/sessions/2026-09-23-two-factor-auth"
printf '# PLAN\nBranch: feat/two-factor-auth   Base: preview   Ticket: none\nBranch mode: session     PR: per session\n' >"$proj/docs/autopilot/sessions/2026-09-23-two-factor-auth/PLAN.md"
printf 'Status: done\n' >"$proj/docs/autopilot/sessions/2026-09-23-two-factor-auth/REPORT.md"
git -C "$proj" add -A; commit "$proj" -m "finished session merged into preview"
git -C "$proj" push -q origin preview
git -C "$proj" checkout -q -b feat/default-org-redirect
mkdir -p "$proj/docs/autopilot/sessions/2026-09-23-default-org-redirect"
printf '# PLAN\nBranch: feat/default-org-redirect   Base: preview   Ticket: none\nBranch mode: session     PR: per session\n' >"$proj/docs/autopilot/sessions/2026-09-23-default-org-redirect/PLAN.md"
git -C "$proj" add -A; commit "$proj" -m "plan for default-org-redirect"
git -C "$proj" push -q origin feat/default-org-redirect
git -C "$proj" checkout -q preview
git -C "$proj" checkout -q -b feat/borrowed-plan
mkdir -p "$proj/docs/autopilot/sessions/2026-09-24-borrowed"
printf '# PLAN\nBranch: feat/somewhere-else   Base: preview   Ticket: none\nBranch mode: session     PR: per session\n' >"$proj/docs/autopilot/sessions/2026-09-24-borrowed/PLAN.md"
git -C "$proj" add -A; commit "$proj" -m "plan that names another branch"
git -C "$proj" push -q origin feat/borrowed-plan
git -C "$proj" checkout -q preview
git -C "$proj" checkout -q -b feat/big
mkdir -p "$proj/docs/autopilot/sessions/2026-09-24-big-s2"
printf '# PLAN\nBranch: feat/big-s2   Base: preview   Ticket: none\nBranch mode: feature-branch feat/big     PR: none\n' >"$proj/docs/autopilot/sessions/2026-09-24-big-s2/PLAN.md"
git -C "$proj" add -A; commit "$proj" -m "feature-branch session plan"
git -C "$proj" push -q origin feat/big
git -C "$proj" checkout -q main

export CLAUDE_BIN="$tmp/fakes/claude" GH_BIN="$tmp/fakes/gh"
# Never the real Jira: the fake jira, and a JIRA_HOME without credentials unless a test
# points it at $tmp/jirahome. Without this the runner used bin/jira with the machine's real
# ~/.claude/jira/env and changed the real ticket PAUL-9 on every test run.
export JIRA_BIN="$tmp/fakes/jira" JIRA_HOME="$tmp/nojira"
export MISSION_CONTROL_WATCH_MIN=0 MISSION_CONTROL_NO_NOTIFY=1 MISSION_CONTROL_TIMEOUT_MIN=5
unset FAKE_GH_PRS FAKE_GH_NO_PR FAKE_GH_FAIL FAKE_GH_LABELS FAKE_GH_AUTH_FAIL MISSION_CONTROL_EFFORT MISSION_CONTROL_MODEL

# fresh_home <name>: new MISSION_CONTROL_HOME and record dir; sets QH and REC.
fresh_home() {
  QH="$tmp/home-$1"; REC="$tmp/rec-$1"
  mkdir -p "$QH" "$REC"
  export MISSION_CONTROL_HOME="$QH" FAKE_RECORD="$REC"
}

# write_plist <fake HOME> <hour> <minute> [legacy]: a LaunchAgent plist as install-schedule
# writes it; "legacy" leaves out --scheduled (a plist from before the pause feature).
write_plist() {
  mkdir -p "$1/Library/LaunchAgents"
  wp_args='<string>run</string><string>--scheduled</string>'
  [ "${4:-}" = legacy ] && wp_args='<string>run</string>'
  printf '<dict><key>ProgramArguments</key><array><string>/x/mission-control</string>%s</array><key>StartCalendarInterval</key><dict><key>Hour</key><integer>%s</integer><key>Minute</key><integer>%s</integer></dict></dict>\n' \
    "$wp_args" "$2" "$3" >"$1/Library/LaunchAgents/de.evelan.mission-control.plist"
}

# ---------- (a) text item, REPORT.md with Status: done -> done ----------
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
check "(a) PR comment body contains the report head" has "shipped PAUL-1" "$(cat "$REC/comment.1")"
check "(a) PR comment body starts with the report heading" has "## Autopilot report" "$(head -n 1 "$REC/comment.1")"
check "(a) claude started with /autopilot PAUL-1 and the launch flags" has "-p /autopilot PAUL-1 --model sonnet --effort xhigh --advisor fable --fallback-model opus --permission-mode auto --max-budget-usd 100 --output-format json" "$(cat "$REC/claude.args")"
check "(a) progress lines on stdout" has "[mission-control] proj PAUL-1: done (PR https://github.com/e/r/pull/7" "$out"
check "(a) worktree removed after done" [ ! -e "$QH/worktrees/proj-PAUL-1/.git" ]
check "(a) main checkout untouched (still on main, clean)" is_main_clean
check "(a) log file written" ls "$QH"/logs/*-PAUL-1.log >/dev/null 2>&1
check "(a) the run saw the sentinel .claude/.autopilot-active" grep -q "attempt 1" "$REC/sentinel.seen"

# ---------- (a2) Status: blocked -> blocked with the reason ----------
fresh_home a2
export FAKE_SCENARIO=report-blocked
printf '%s PAUL-31\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(a2) run exits 0" [ "$got" -eq 0 ]
check "(a2) status blocked in done.txt" grep -q " PAUL-31 blocked " "$QH/done.txt"
check "(a2) reason from the Status line on stdout" has "blocked: cannot reach the API" "$out"
check "(a2) PR labelled autopilot-blocked" has "pr edit 7 --remove-label autopilot-ready --add-label autopilot-blocked" "$(cat "$REC/gh.args")"
check "(a2) PR comment carries the reason" has "cannot reach the API" "$(cat "$REC/comment.1")"
check "(a2) worktree kept" [ -e "$QH/worktrees/proj-PAUL-31/.git" ]
check "(a2) sentinel removed from the kept worktree" [ ! -e "$QH/worktrees/proj-PAUL-31/.claude/.autopilot-active" ]
check "(a2) status file removed from the kept worktree" [ ! -e "$QH/worktrees/proj-PAUL-31/.claude/.autopilot-status" ]

# ---------- (a2b) budget exhausted, no REPORT.md or HANDOFF.md -> blocked with the budget named ----------
fresh_home a2b
export FAKE_SCENARIO=budget
printf '%s PAUL-36\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(a2b) blocked" grep -q " PAUL-36 blocked " "$QH/done.txt"
check "(a2b) reason names the budget" has "budget of 100 USD exhausted before REPORT.md or HANDOFF.md was written" "$out"

# ---------- (a2c) HANDOFF.md then an abort REPORT.md (HANDOFF left behind) -> blocked, no restart loop ----------
fresh_home a2c
export FAKE_SCENARIO=handoff-then-abort
printf '%s PAUL-35\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(a2c) claude called exactly twice" [ "$(count_lines "$REC/claude.args")" = 2 ]
check "(a2c) blocked with the report's reason" grep -q " PAUL-35 blocked " "$QH/done.txt"
check "(a2c) reason from the newer REPORT.md" has "blocked: gate needs a database" "$out"
check "(a2c) log says the report decided" grep -q "REPORT.md is newer than HANDOFF.md" "$QH"/logs/*-PAUL-35.log

# ---------- (a3) REPORT.md without a Status line -> blocked ----------
fresh_home a3
export FAKE_SCENARIO=report-nostatus
printf '%s PAUL-32\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"
check "(a3) status blocked in done.txt" grep -q " PAUL-32 blocked " "$QH/done.txt"
check "(a3) reason names the missing status line" has "report without status line" "$out"

# ---------- (a4) an old unrelated session never makes a new item done ----------
fresh_home a4
export FAKE_SCENARIO=noop
printf '%s PAUL-99\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" list 2>&1)"
check "(a4) list marks the item no plan (OLD-1 does not count)" has "PAUL-99 (no plan)" "$out"
out="$(sh "$TOOL" run 2>&1)"
check "(a4) run does not report done" grep -qv " PAUL-99 done " "$QH/done.txt"
check "(a4) status blocked, no session directory" grep -q " PAUL-99 blocked - no-plan" "$QH/done.txt"
check "(a4) reason names the missing session directory" has "no session directory for this item" "$out"

# ---------- (a2d) clean exit without REPORT.md or HANDOFF.md -> restarted like a hand-off ----------
fresh_home a2d
export FAKE_SCENARIO=early-exit-then-report
printf '%s PAUL-37\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(a2d) claude called twice" [ "$(count_lines "$REC/claude.args")" = 2 ]
check "(a2d) restart announced with the reason" has "ended without REPORT.md or HANDOFF.md, restart 1/5" "$out"
check "(a2d) done with restarts=1" grep -q " PAUL-37 done .* restarts=1" "$QH/done.txt"
fresh_home a2e
export FAKE_SCENARIO=early-exit-always MISSION_CONTROL_MAX_RESTARTS=2
printf '%s PAUL-38\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(a2e) claude called 1 + MAX_RESTARTS times" [ "$(count_lines "$REC/claude.args")" = 3 ]
check "(a2e) handoff-limit with the artifact reason" grep -q " PAUL-38 handoff-limit " "$QH/done.txt"
check "(a2e) reason on stdout" has "no REPORT.md or HANDOFF.md after 2 restarts" "$out"
unset MISSION_CONTROL_MAX_RESTARTS

# ---------- (a5) topic item: session dir found because it was created since the start ----------
fresh_home a5
export FAKE_SCENARIO=report
printf '%s "Move the picker"\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"
check "(a5) topic item done via the directory created by the run" grep -q ' "Move the picker" done ' "$QH/done.txt"

# ---------- (b) HANDOFF.md then REPORT.md -> done with restarts=1 ----------
fresh_home b
export FAKE_SCENARIO=handoff-then-report
printf '%s PAUL-2\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(b) run exits 0" [ "$got" -eq 0 ]
check "(b) claude called twice" [ "$(count_lines "$REC/claude.args")" = 2 ]
check "(b) done with restarts=1" grep -q " PAUL-2 done .* restarts=1" "$QH/done.txt"
check "(b) restart announced" has "hand-off found, restart 1/5" "$out"
check "(b) the restarted run saw the sentinel again" grep -q "attempt 2" "$REC/sentinel.seen"

# ---------- (c) HANDOFF.md every time -> handoff-limit ----------
fresh_home c
export FAKE_SCENARIO=handoff-always MISSION_CONTROL_MAX_RESTARTS=2
printf '%s PAUL-3\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(c) run exits 0" [ "$got" -eq 0 ]
check "(c) claude called 1 + MAX_RESTARTS times" [ "$(count_lines "$REC/claude.args")" = 3 ]
check "(c) status handoff-limit in done.txt" grep -q " PAUL-3 handoff-limit " "$QH/done.txt"
check "(c) PR labelled autopilot-blocked" has "pr edit 7 --remove-label autopilot-ready --add-label autopilot-blocked" "$(cat "$REC/gh.args")"
check "(c) worktree kept" [ -e "$QH/worktrees/proj-PAUL-3/.git" ]
unset MISSION_CONTROL_MAX_RESTARTS

# ---------- (d) PR items from repos.txt, including a PR whose branch is missing ----------
fresh_home d
export FAKE_SCENARIO=report
printf '11 feat/PAUL-9-thing https://github.com/e/r/pull/11\n12 feat/PAUL-10-noplan https://github.com/e/r/pull/12\n13 feat/PAUL-11-missing https://github.com/e/r/pull/13\n' >"$REC/prs.txt"
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
check "(d) PR 13 (branch missing) blocked in done.txt" grep -q " #13 blocked https://github.com/e/r/pull/13$" "$QH/done.txt"
check "(d) PR 13 labelled autopilot-blocked although no worktree exists" has "pr edit 13 --remove-label autopilot-ready --add-label autopilot-blocked" "$gh_args"
check "(d) PR 13 got a comment" has "pr comment 13 --body-file" "$gh_args"
check "(d) PR 13 was not run" lacks "PAUL-11" "$cl"
check "(d) main checkout still on main, clean" is_main_clean
check "(d) PR 11 log named after the PR number and the resolved session dir" ls "$QH"/logs/*-_11-2026-09-19-PAUL-9-thing.log >/dev/null 2>&1
check "(d) PR 12 log named after the PR number and the ticket key" ls "$QH"/logs/*-_12-PAUL-10.log >/dev/null 2>&1
check "(d) no log left under the pre-resolution name" bash -c '! ls "$1"/logs/*-_11.log >/dev/null 2>&1' _ "$QH"
check "(d) PR 13 (blocked before resolution) keeps the PR-number name" ls "$QH"/logs/*-_13.log >/dev/null 2>&1
check "(d) the renamed log holds the whole run" grep -q "#11: resolving" "$QH"/logs/*-_11-2026-09-19-PAUL-9-thing.log
unset FAKE_GH_PRS

# ---------- (d2) TERM during a PR item kills the claude process ----------
fresh_home d2
export FAKE_SCENARIO=sleep
printf '12 feat/PAUL-10-noplan https://github.com/e/r/pull/12\n' >"$REC/prs.txt"
export FAKE_GH_PRS="$REC/prs.txt"
printf '%s\n' "$proj" >"$QH/repos.txt"
sh "$TOOL" run >"$REC/out" 2>&1 &
runpid=$!
for _ in $(seq 1 100); do [ -f "$REC/claude.pid" ] && break; sleep 0.1; done
sleep 0.5
kill -TERM "$runpid"
wait "$runpid" 2>/dev/null; got=$?
cpid="$(cat "$REC/claude.pid" 2>/dev/null || echo 0)"
sleep 0.5
check "(d2) claude pid recorded" [ "$cpid" -gt 0 ]
check "(d2) run exited on TERM with 130" [ "$got" -eq 130 ]
check "(d2) fake claude is gone after TERM to the queue" bash -c '! kill -0 "$1" 2>/dev/null' _ "$cpid"
check "(d2) lock released" [ ! -e "$QH/run.lock" ]
kill -9 "$cpid" 2>/dev/null
unset FAKE_GH_PRS

# ---------- (d3) gh pr list --label failure is reported, the other source still runs ----------
fresh_home d3
export FAKE_SCENARIO=report FAKE_GH_FAIL="pr list --label"
printf '%s PAUL-33\n' "$proj" >"$QH/queue.txt"
printf '%s\n' "$proj" >"$QH/repos.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(d3) run exits 1 when a source failed" [ "$got" -eq 1 ]
check "(d3) FAIL line on stdout" has "FAIL - $proj: gh pr list --label autopilot-ready failed" "$out"
check "(d3) FAIL line in the log" grep -q "gh pr list --label autopilot-ready failed" "$QH/logs/queue.log"
check "(d3) the list item was still processed" grep -q " PAUL-33 done " "$QH/done.txt"
out="$(sh "$TOOL" list 2>&1)"; got=$?
check "(d3) list reports the failure too" has "FAIL - $proj: gh pr list --label autopilot-ready failed" "$out"
check "(d3) list exits 1 when a source failed" [ "$got" -eq 1 ]
unset FAKE_GH_FAIL

# ---------- (d4) gh cannot read its token: one notice, no per-repo FAIL lines ----------
fresh_home d4
export FAKE_SCENARIO=report FAKE_GH_AUTH_FAIL=1
fakehome="$tmp/fakehome-d4"; mkdir -p "$fakehome"
printf '%s\n%s\n' "$proj" "$proj" >"$QH/repos.txt"
ssh_notice="gh: token not readable in this SSH session (macOS Keychain); labelled PRs unknown here, the scheduled run in the GUI session sees them"
login_notice='gh: not authenticated (run "gh auth login -h github.com -w"); labelled PRs unknown'
unknown_line="labelled PRs: unknown (gh not authenticated in this session)"
ssh_env="SSH_CONNECTION=10.0.0.2 51234 10.0.0.1 22"
# over SSH: the token sits in the Keychain of the GUI session
out="$(env "$ssh_env" HOME="$fakehome" sh "$TOOL" status 2>&1)"; got=$?
check "(d4) status over SSH exits 0" [ "$got" -eq 0 ]
check "(d4) status over SSH prints the Keychain notice exactly once" [ "$(printf '%s\n' "$out" | grep -cF "$ssh_notice")" = 1 ]
check "(d4) status over SSH prints no per-repo FAIL line" lacks "FAIL -" "$out"
check "(d4) status over SSH says the labelled PRs are unknown" has "$unknown_line" "$out"
check "(d4) status over SSH prints no PR count" lacks "labelled PRs: 0" "$out"
check "(d4) status over SSH did not poll the repos" lacks "pr list --label" "$(cat "$REC/gh.args")"
out="$(env SSH_TTY=/dev/ttys003 HOME="$fakehome" sh "$TOOL" status 2>&1)"
check "(d4) SSH_TTY alone counts as an SSH session" has "$ssh_notice" "$out"
out="$(env "$ssh_env" sh "$TOOL" list 2>&1)"; got=$?
check "(d4) list over SSH exits 0" [ "$got" -eq 0 ]
check "(d4) list over SSH prints the Keychain notice exactly once" [ "$(printf '%s\n' "$out" | grep -cF "$ssh_notice")" = 1 ]
check "(d4) list over SSH prints no per-repo FAIL line" lacks "FAIL -" "$out"
printf '%s PAUL-90\n' "$proj" >"$QH/queue.txt"
out="$(env "$ssh_env" sh "$TOOL" run 2>&1)"; got=$?
check "(d4) run over SSH exits 0" [ "$got" -eq 0 ]
check "(d4) run over SSH prints the Keychain notice exactly once" [ "$(printf '%s\n' "$out" | grep -cF "$ssh_notice")" = 1 ]
check "(d4) run over SSH prints no per-repo FAIL line" lacks "FAIL -" "$out"
check "(d4) run over SSH still processed the queue item" grep -q " PAUL-90 done " "$QH/done.txt"
check "(d4) run over SSH logged the notice" grep -qF "$ssh_notice" "$QH/logs/queue.log"
check "(d4) run over SSH does not say a source failed" lacks "one source failed" "$out"
# not over SSH: a real login problem
out="$(env -u SSH_CONNECTION -u SSH_TTY HOME="$fakehome" sh "$TOOL" status 2>&1)"; got=$?
check "(d4) status without SSH exits 0" [ "$got" -eq 0 ]
check "(d4) status without SSH says to log in" has "$login_notice" "$out"
check "(d4) status without SSH does not mention the Keychain" lacks "Keychain" "$out"
check "(d4) status without SSH says the labelled PRs are unknown" has "$unknown_line" "$out"
out="$(env -u SSH_CONNECTION -u SSH_TTY sh "$TOOL" list 2>&1)"; got=$?
check "(d4) list without SSH exits 1" [ "$got" -eq 1 ]
check "(d4) list without SSH prints the login notice exactly once" [ "$(printf '%s\n' "$out" | grep -cF "$login_notice")" = 1 ]
check "(d4) list without SSH prints no per-repo FAIL line" lacks "FAIL -" "$out"
printf '%s PAUL-91\n' "$proj" >"$QH/queue.txt"
out="$(env -u SSH_CONNECTION -u SSH_TTY sh "$TOOL" run 2>&1)"; got=$?
check "(d4) run without SSH exits 1 (a real auth problem)" [ "$got" -eq 1 ]
check "(d4) run without SSH prints the login notice exactly once" [ "$(printf '%s\n' "$out" | grep -cF "$login_notice")" = 1 ]
check "(d4) run without SSH still processed the queue item" grep -q " PAUL-91 done " "$QH/done.txt"
# no repos: gh is not asked at all
: >"$QH/repos.txt"
out="$(env "$ssh_env" sh "$TOOL" list 2>&1)"; got=$?
check "(d4) list without repos exits 0" [ "$got" -eq 0 ]
check "(d4) list without repos prints no notice" lacks "gh:" "$out"
unset FAKE_GH_AUTH_FAIL

# ---------- (e) list prints both sources without running ----------
fresh_home e
printf '%s PAUL-4\n%s "Move the picker"\n%s PAUL-20\n%s docs/autopilot/sessions/2026-09-18-PAUL-21-branchy feat/PAUL-21-branchy\n' "$proj" "$proj" "$proj" "$proj" >"$QH/queue.txt"
printf '%s\n' "$proj" >"$QH/repos.txt"
printf '11 feat/PAUL-9-thing https://github.com/e/r/pull/11\n' >"$REC/prs.txt"
export FAKE_GH_PRS="$REC/prs.txt"
out="$(sh "$TOOL" list 2>&1)"; got=$?
check "(e) list exits 0" [ "$got" -eq 0 ]
check "(e) list shows the ticket item" has "queue  $proj  PAUL-4 (no plan)" "$out"
check "(e) list shows the quoted topic" has "queue  $proj  \"Move the picker\" (no plan)" "$out"
check "(e) list finds the plan by ticket key" has "queue  $proj  PAUL-20"$'\n' "$out"
check "(e) list finds the plan on the recorded branch" has "queue  $proj  docs/autopilot/sessions/2026-09-18-PAUL-21-branchy feat/PAUL-21-branchy"$'\n' "$out"
check "(e) list shows the labelled PR" has "pr     $proj  #11 feat/PAUL-9-thing https://github.com/e/r/pull/11" "$out"
check "(e) list did not start claude" [ ! -e "$REC/claude.args" ]
check "(e) list left queue.txt alone" [ "$(live_lines "$QH/queue.txt")" = 4 ]
unset FAKE_GH_PRS

# ---------- (f) add: quoting and branch detection ----------
fresh_home f
sh "$TOOL" add "$proj" PAUL-5 >/dev/null
sh "$TOOL" add "$proj" Move the picker into the composer >/dev/null
check "(f) add writes a plain item unquoted" grep -qxF "$proj PAUL-5" "$QH/queue.txt"
check "(f) add quotes an item with spaces" grep -qxF "$proj \"Move the picker into the composer\"" "$QH/queue.txt"
out="$(sh "$TOOL" add "$tmp/nowhere" X 2>&1)"; got=$?
check "(f) add refuses a non-repo (exit 1)" [ "$got" -eq 1 ]
check "(f) add names the reason" has "not a git repository" "$out"
out="$(sh "$TOOL" add "$proj" docs/autopilot/sessions/2026-09-18-PAUL-21-branchy 2>&1)"
check "(f) add finds the branch holding a session dir absent from the checkout" grep -qxF "$proj docs/autopilot/sessions/2026-09-18-PAUL-21-branchy feat/PAUL-21-branchy" "$QH/queue.txt"
check "(f) add prints the branch" has "feat/PAUL-21-branchy" "$out"
sh "$TOOL" add "$proj" docs/autopilot/sessions/2026-09-18-PAUL-20-effort/ >/dev/null
check "(f) add records the current branch for a session dir in the checkout" grep -qxF "$proj docs/autopilot/sessions/2026-09-18-PAUL-20-effort main" "$QH/queue.txt"
sh "$TOOL" add "$proj" docs/autopilot/sessions/2026-09-18-PAUL-21-branchy feat/given >/dev/null
check "(f) add takes an explicit branch" grep -qxF "$proj docs/autopilot/sessions/2026-09-18-PAUL-21-branchy feat/given" "$QH/queue.txt"

# ---------- (f2) a list item on a feature branch runs on that branch with its plan ----------
fresh_home f2
export FAKE_SCENARIO=report
sh "$TOOL" add "$proj" docs/autopilot/sessions/2026-09-18-PAUL-21-branchy >/dev/null
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(f2) run exits 0" [ "$got" -eq 0 ]
check "(f2) done without no-plan" grep -q " docs/autopilot/sessions/2026-09-18-PAUL-21-branchy done https://github.com/e/r/pull/7$" "$QH/done.txt"
check "(f2) model opus and effort low taken from the plan on the branch" has "--model opus --effort low " "$(cat "$REC/claude.args")"
check "(f2) the run saw the branch history" grep -q "plan on branch" "$REC/claude.gitlog.1"
check "(f2) the run was on feat/PAUL-21-branchy" grep -q "PAUL-21-branchy" "$QH/done.txt"

# ---------- (g) doctor and labels ----------
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
check "(g) doctor checked the labels" has "label autopilot-blocked exists in proj" "$out"
check "(g) doctor lists the repos" has "repos in the queue: 1" "$out"
export FAKE_GH_LABELS=autopilot-ready
out="$(cd "$proj" && sh "$TOOL" labels 2>&1)"; got=$?
check "(g) labels exits 0" [ "$got" -eq 0 ]
check "(g) labels keeps an existing label" has "label autopilot-ready exists in proj" "$out"
check "(g) labels creates the missing ones" has "label autopilot-done created in proj" "$out"
check "(g) labels uses the agreed colours" has "label create autopilot-blocked --color B60205" "$(cat "$REC/gh.args")"
check "(g) labels uses the agreed colours (done)" has "label create autopilot-done --color 1D76DB" "$(cat "$REC/gh.args")"
export FAKE_GH_FAIL="label create"
out="$(sh "$TOOL" labels "$proj" 2>&1)"; got=$?
check "(g) labels exits 1 when a label cannot be created" [ "$got" -eq 1 ]
check "(g) labels names the failure" has "FAIL - label autopilot-done missing in proj" "$out"
unset FAKE_GH_FAIL FAKE_GH_LABELS

# ---------- (h0) machine without a queue: queue commands refuse with exit 3 ----------
fresh_home h0
rm -rf "$QH"
for c in status list run add stop log kickstart; do
  out="$(sh "$TOOL" $c "$proj" X 2>&1)"; got=$?
  check "(h0) $c refuses on a machine without the queue home (exit 3)" [ "$got" -eq 3 ]
  check "(h0) $c names the office Mini and /autopilot-plan" has "office Mini" "$out"
done
check "(h0) no queue.txt was created by add" [ ! -e "$QH/queue.txt" ]
out="$(sh "$TOOL" retry "$proj" 7 2>&1)"; got=$?
check "(h0) retry refuses too (exit 3)" [ "$got" -eq 3 ]
mkdir -p "$QH"
out="$(sh "$TOOL" status 2>&1)"; got=$?
check "(h0) status works once the queue home exists" [ "$got" -eq 0 ]

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

# ---------- (i) no secret printed, curl failure logged with its exit code ----------
fresh_home i
export FAKE_SCENARIO=report
unset MISSION_CONTROL_NO_NOTIFY
secret="https://hooks.slack.com/services/T000/B000/SECRETXYZ"
printf 'SLACK_WEBHOOK_URL=%s\n' "$secret" >"$QH/env"; chmod 600 "$QH/env"
printf '%s PAUL-7\n' "$proj" >"$QH/queue.txt"
out="$(PATH="$tmp/fakes:$PATH" sh "$TOOL" run 2>&1)"; got=$?
check "(i) run exits 0 with notifications on" [ "$got" -eq 0 ]
check "(i) Slack webhook was called" has "SECRETXYZ" "$(cat "$REC/curl.args" 2>/dev/null)"
check "(i) macOS notification was sent" has "PAUL-7: done" "$(cat "$REC/osascript.args" 2>/dev/null)"
check "(i) done notification plays Glass" has 'sound name "Glass"' "$(cat "$REC/osascript.args" 2>/dev/null)"
printf '%s PAUL-7b\n' "$proj" >"$QH/queue.txt"
out="$(FAKE_SCENARIO=report-blocked PATH="$tmp/fakes:$PATH" sh "$TOOL" run 2>&1)"
check "(i) blocked notification carries the reason and plays Sosumi" has "PAUL-7b: blocked: cannot reach the API" "$(grep Sosumi "$REC/osascript.args" 2>/dev/null)"
check "(i) stdout never contains the webhook URL" lacks "SECRETXYZ" "$out"
check "(i) logs never contain the webhook URL" lacks "SECRETXYZ" "$(cat "$QH"/logs/*.log)"
printf '%s PAUL-8\n' "$proj" >"$QH/queue.txt"
out="$(FAKE_CURL_EXIT=22 PATH="$tmp/fakes:$PATH" sh "$TOOL" run 2>&1)"
check "(i) curl failure logged with its exit code" grep -q "Slack webhook failed (curl exit 22)" "$QH"/logs/*-PAUL-8.log
export MISSION_CONTROL_NO_NOTIFY=1

# ---------- (j) reused worktree: fetch and fast-forward before the retry ----------
fresh_home j
export FAKE_SCENARIO=report-blocked
sh "$TOOL" add "$proj" docs/autopilot/sessions/2026-09-19-PAUL-9-thing feat/PAUL-9-thing >/dev/null
out="$(sh "$TOOL" run 2>&1)"
wt="$QH/worktrees/proj-2026-09-19-PAUL-9-thing"
check "(j) first run blocked, worktree kept" [ -e "$wt/.git" ]
git -C "$proj" push -q origin feat/PAUL-9-thing   # the run's commit, as the real run would push it
git clone -q "$tmp/origin.git" "$tmp/devclone"
git -C "$tmp/devclone" checkout -q feat/PAUL-9-thing
commit "$tmp/devclone" --allow-empty -m "developer fix"
git -C "$tmp/devclone" push -q origin feat/PAUL-9-thing
sh "$TOOL" add "$proj" docs/autopilot/sessions/2026-09-19-PAUL-9-thing feat/PAUL-9-thing >/dev/null
out="$(sh "$TOOL" run 2>&1)"
git -C "$wt" log --oneline -5 >"$REC/wt.gitlog"
check "(j) retry fast-forwarded the reused worktree to the developer's push" grep -q "developer fix" "$REC/wt.gitlog"
check "(j) the run saw the developer fix" grep -q "developer fix" "$REC/claude.gitlog.2"
check "(j) no fast-forward complaint" lacks "not fast-forwardable" "$out"
commit "$wt" --allow-empty -m "local divergence"
commit "$tmp/devclone" --allow-empty -m "another fix"
git -C "$tmp/devclone" push -q origin feat/PAUL-9-thing
sh "$TOOL" add "$proj" docs/autopilot/sessions/2026-09-19-PAUL-9-thing feat/PAUL-9-thing >/dev/null
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(j) diverged worktree: said, run continues" has "feat/PAUL-9-thing is not fast-forwardable to origin/feat/PAUL-9-thing, continuing on the local state" "$out"
check "(j) diverged worktree: item still processed" [ "$(grep -c "PAUL-9-thing blocked" "$QH/done.txt")" = 3 ]

# ---------- (j2) the plan branch is checked out in the user's main checkout ----------
fresh_home j2
export FAKE_SCENARIO=report-blocked
git -C "$proj" checkout -q --ignore-other-worktrees feat/PAUL-9-thing
sh "$TOOL" add "$proj" docs/autopilot/sessions/2026-09-19-PAUL-9-thing feat/PAUL-9-thing >/dev/null
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(j2) run exits 0" [ "$got" -eq 0 ]
check "(j2) says where else the branch is checked out" has "branch feat/PAUL-9-thing is also checked out in " "$out"
check "(j2) names the other checkout and the rule" has "/proj; the run works on feat/PAUL-9-thing here, do not commit there until it is done" "$out"
check "(j2) the worktree is on the branch, not detached" [ "$(git -C "$QH/worktrees/proj-2026-09-19-PAUL-9-thing" symbolic-ref --short HEAD)" = feat/PAUL-9-thing ]
check "(j2) blocked as the fake run reports" grep -q " docs/autopilot/sessions/2026-09-19-PAUL-9-thing blocked " "$QH/done.txt"
git -C "$proj" checkout -q main

# ---------- (j3) jira: start before the first attempt, comment at the end, failures said ----------
fresh_home j3
export FAKE_SCENARIO=report
mkdir -p "$tmp/jirahome"; printf 'JIRA_SITE=x\nJIRA_EMAIL=y\nJIRA_TOKEN=z\n' >"$tmp/jirahome/env"
sh "$TOOL" add "$proj" docs/autopilot/sessions/2026-09-19-PAUL-9-thing feat/PAUL-9-thing >/dev/null
out="$(JIRA_BIN="$tmp/fakes/jira" JIRA_HOME="$tmp/jirahome" sh "$TOOL" run 2>&1)"; got=$?
check "(j3) jira start called with the plan's ticket before the run" [ "$(sed -n 1p "$REC/jira.args")" = "start PAUL-9" ]
check "(j3) jira start happened before claude" grep -qx "start PAUL-9" "$REC/jira-at-claude-start.1"
check "(j3) jira comment called at the end" [ "$(sed -n 2p "$REC/jira.args")" = "comment PAUL-9 -" ]
check "(j3) comment body: status, PR and the report head" bash -c 'grep -q "^Autopilot: done" "$1" && grep -q "^PR: https://github.com/e/r/pull/7" "$1" && grep -q "shipped" "$1"' _ "$REC/jira-comment.1"
check "(j3) comment body has no Markdown headings" bash -c '! grep -q "^#" "$1"' _ "$REC/jira-comment.1"
check "(j3) done.txt has no jira-failed" bash -c '! grep -q "jira-failed" "$1"' _ "$QH/done.txt"
fresh_home j3b
sh "$TOOL" add "$proj" docs/autopilot/sessions/2026-09-19-PAUL-9-thing feat/PAUL-9-thing >/dev/null
out="$(FAKE_JIRA_FAIL=1 JIRA_BIN="$tmp/fakes/jira" JIRA_HOME="$tmp/jirahome" sh "$TOOL" run 2>&1)"; got=$?
check "(j3b) jira failure is said with jira's last line" has "jira start PAUL-9 failed: jira: HTTP 401" "$out"
check "(j3b) the run still happened" [ "$(count_lines "$REC/claude.args")" = 1 ]
check "(j3b) done.txt marks jira-failed" grep -q " jira-failed" "$QH/done.txt"
fresh_home j3c
sh "$TOOL" add "$proj" docs/autopilot/sessions/2026-09-19-PAUL-9-thing feat/PAUL-9-thing >/dev/null
out="$(JIRA_BIN="$tmp/fakes/jira" JIRA_HOME="$tmp/nojira" sh "$TOOL" run 2>&1)"; got=$?
check "(j3c) without a credentials file jira is not called" [ ! -e "$REC/jira.args" ]
check "(j3c) the log says why" grep -q "PAUL-9 not updated (no jira script or no" "$QH"/logs/*-2026-09-19-PAUL-9-thing.log
fresh_home j3d
export FAKE_SCENARIO=report-blocked
sh "$TOOL" add "$proj" docs/autopilot/sessions/2026-09-19-PAUL-9-thing feat/PAUL-9-thing >/dev/null
out="$(JIRA_BIN="$tmp/fakes/jira" JIRA_HOME="$tmp/jirahome" sh "$TOOL" run 2>&1)"; got=$?
check "(j3d) blocked: comment carries the status and the report head" bash -c 'grep -q "^Autopilot: blocked" "$1" && grep -q "cannot reach the API" "$1"' _ "$REC/jira-comment.1"

# ---------- (j4) review-bot comments counted in done.txt when the repo has the review workflow ----------
fresh_home j4
export FAKE_SCENARIO=report
mkdir -p "$proj/.github/workflows"; echo "name: review" >"$proj/.github/workflows/claude-code-review.yml"
git -C "$proj" add -A && commit "$proj" -m "review workflow"
git -C "$proj" push -q origin main 2>/dev/null || true
printf '%s PAUL-70\n' "$proj" >"$QH/queue.txt"
out="$(FAKE_REVIEW_INLINE="claude[bot] claude[bot]" FAKE_REVIEW_TOP="andreas github-actions[bot]" sh "$TOOL" run 2>&1)"; got=$?
check "(j4) done.txt counts the comments not by the PR author" grep -q " PAUL-70 done .* review-comments=3" "$QH/done.txt"
check "(j4) both bot threads unanswered" grep -q " PAUL-70 done .* unanswered-review-comments=2" "$QH/done.txt"
check "(j4) unanswered comments are said" has "PAUL-70: 2 review-bot comment(s) on the PR have no reply from the run" "$out"
printf '%s PAUL-72\n' "$proj" >"$QH/queue.txt"
out="$(FAKE_REVIEW_INLINE="claude[bot]:1 claude[bot]:2 andreas>1 claude[bot]>1" FAKE_REVIEW_TOP="" sh "$TOOL" run 2>&1)"; got=$?
check "(j4) a thread with an author reply counts as answered; a bot follow-up does not" grep -q " PAUL-72 done .* review-comments=3 unanswered-review-comments=1" "$QH/done.txt"
printf '%s PAUL-73\n' "$proj" >"$QH/queue.txt"
out="$(FAKE_REVIEW_INLINE="claude[bot]:1 andreas>1" FAKE_REVIEW_TOP="" sh "$TOOL" run 2>&1)"; got=$?
check "(j4) all answered: no unanswered field" grep -q " PAUL-73 done .* review-comments=1$" "$QH/done.txt"
check "(j4) all answered: nothing said" lacks "PAUL-73: " "$(printf '%s' "$out" | grep 'no reply')"
printf '%s PAUL-71\n' "$proj" >"$QH/queue.txt"
out="$(FAKE_REVIEW_INLINE="" FAKE_REVIEW_TOP="andreas" sh "$TOOL" run 2>&1)"; got=$?
check "(j4) zero bot comments: said on stdout" has "PAUL-71: no review-bot comment on the PR yet, check it" "$out"
check "(j4) zero bot comments: recorded" grep -q " PAUL-71 done .* review-comments=0" "$QH/done.txt"
git -C "$proj" rm -q -r .github && commit "$proj" -m "remove review workflow" && git -C "$proj" push -q origin main 2>/dev/null || true

# ---------- (k) timeout kills the run ----------
fresh_home k
export FAKE_SCENARIO=sleep MISSION_CONTROL_TIMEOUT_MIN=0.02
printf '%s PAUL-34\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
cpid="$(cat "$REC/claude.pid" 2>/dev/null || echo 0)"
check "(k) run exits 0" [ "$got" -eq 0 ]
check "(k) status timeout in done.txt" grep -q " PAUL-34 timeout " "$QH/done.txt"
check "(k) reason names the wall-clock timeout" has "wall-clock timeout of 0.02 min" "$out"
check "(k) fake claude killed" bash -c '! kill -0 "$1" 2>/dev/null' _ "$cpid"
kill -9 "$cpid" 2>/dev/null
export MISSION_CONTROL_TIMEOUT_MIN=5

# ---------- (l) env precedence: environment over env file over default; effort from the plan ----------
fresh_home l
export FAKE_SCENARIO=report
printf 'MISSION_CONTROL_MODEL=haiku\nMISSION_CONTROL_EFFORT=xhigh\nMISSION_CONTROL_FALLBACK_MODEL=sonnet\n' >"$QH/env"; chmod 600 "$QH/env"
printf '%s PAUL-35\n' "$proj" >"$QH/queue.txt"
sh "$TOOL" run >/dev/null 2>&1
check "(l) env file beats the default (model haiku, effort xhigh, fallback sonnet)" has "--model haiku --effort xhigh --advisor fable --fallback-model sonnet" "$(tail -n 1 "$REC/claude.args")"
printf '%s PAUL-35\n' "$proj" >"$QH/queue.txt"
MISSION_CONTROL_MODEL=opus MISSION_CONTROL_EFFORT=low sh "$TOOL" run >/dev/null 2>&1
check "(l) environment beats the env file" has "--model opus --effort low " "$(tail -n 1 "$REC/claude.args")"
printf '%s PAUL-20\n' "$proj" >"$QH/queue.txt"
sh "$TOOL" run >/dev/null 2>&1
check "(l) Effort: high from PLAN.md beats the env file" has "--effort high " "$(tail -n 1 "$REC/claude.args")"
printf '%s PAUL-20\n' "$proj" >"$QH/queue.txt"
MISSION_CONTROL_EFFORT=low sh "$TOOL" run >/dev/null 2>&1
check "(l) explicit environment effort beats PLAN.md" has "--effort low " "$(tail -n 1 "$REC/claude.args")"
rm -f "$QH/env"
printf '%s PAUL-36\n' "$proj" >"$QH/queue.txt"
sh "$TOOL" run >/dev/null 2>&1
check "(l) defaults without env file (sonnet at xhigh)" has "--model sonnet --effort xhigh --advisor fable --fallback-model opus --permission-mode auto --max-budget-usd 100 " "$(tail -n 1 "$REC/claude.args")"

# ---------- (l2) model from the plan header, sonnet effort floor, fallback and budget ----------
fresh_home l2
export FAKE_SCENARIO=report
printf '%s PAUL-160\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"
check "(l2) Model: opus from PLAN.md, its effort kept, no fallback, budget 120" has "--model opus --effort medium --advisor fable --permission-mode auto --max-budget-usd 120 " "$(tail -n 1 "$REC/claude.args")"
check "(l2) the run line names the model" has "run (attempt 1, model opus, effort medium)" "$out"
printf '%s PAUL-161\n' "$proj" >"$QH/queue.txt"
sh "$TOOL" run >/dev/null 2>&1
check "(l2) Model: sonnet with Effort: medium runs at xhigh, fallback opus, budget 100" has "--model sonnet --effort xhigh --advisor fable --fallback-model opus --permission-mode auto --max-budget-usd 100 " "$(tail -n 1 "$REC/claude.args")"
check "(l2) the raise is logged" grep -q "effort medium raised to xhigh" "$(ls "$QH"/logs/*-PAUL-161.log)"
printf '%s PAUL-162\n' "$proj" >"$QH/queue.txt"
sh "$TOOL" run >/dev/null 2>&1
check "(l2) Model: Sonnet with Effort: max keeps max" has "--model sonnet --effort max " "$(tail -n 1 "$REC/claude.args")"
printf '%s PAUL-160\n' "$proj" >"$QH/queue.txt"
MISSION_CONTROL_MODEL=sonnet sh "$TOOL" run >/dev/null 2>&1
check "(l2) environment model beats the plan, the floor still applies" has "--model sonnet --effort xhigh " "$(tail -n 1 "$REC/claude.args")"
printf '%s PAUL-160\n' "$proj" >"$QH/queue.txt"
MISSION_CONTROL_BUDGET_USD=30 sh "$TOOL" run >/dev/null 2>&1
check "(l2) an explicit budget beats the per-model default" has "--model opus --effort medium --advisor fable --permission-mode auto --max-budget-usd 30 " "$(tail -n 1 "$REC/claude.args")"
printf 'MISSION_CONTROL_FALLBACK_MODEL=fable\n' >"$QH/env"; chmod 600 "$QH/env"
printf '%s PAUL-160\n' "$proj" >"$QH/queue.txt"
sh "$TOOL" run >/dev/null 2>&1
check "(l2) a fallback of another family is kept for an opus run" has "--model opus --effort medium --advisor fable --fallback-model fable " "$(tail -n 1 "$REC/claude.args")"
rm -f "$QH/env"
fresh_home l3
printf '14 feat/PAUL-163-bogus https://github.com/e/r/pull/14\n' >"$REC/prs.txt"
export FAKE_GH_PRS="$REC/prs.txt"
printf '%s\n' "$proj" >"$QH/repos.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(l3) an unknown Model: in the plan: run exits 0" [ "$got" -eq 0 ]
check "(l3) claude not started" [ ! -e "$REC/claude.args" ]
check "(l3) done.txt says blocked" grep -q " docs/autopilot/sessions/2026-09-25-PAUL-163-bogus blocked https://github.com/e/r/pull/14$" "$QH/done.txt"
check "(l3) the reason names the header line" has "PLAN.md header 'Model: gpt-5' is not sonnet or opus" "$out"
check "(l3) the PR comment carries the reason" has "'Model: gpt-5' is not sonnet or opus" "$(cat "$REC/comment.1")"
check "(l3) the PR is labelled blocked" has "pr edit 14 --remove-label autopilot-ready --add-label autopilot-blocked" "$(cat "$REC/gh.args")"
unset FAKE_GH_PRS

# ---------- (m) no PR found after the run ----------
fresh_home m
export FAKE_SCENARIO=report FAKE_GH_NO_PR=1
printf '%s PAUL-37\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(m) run exits 0" [ "$got" -eq 0 ]
check "(m) done with - as the PR url" grep -q " PAUL-37 done - no-plan$" "$QH/done.txt"
check "(m) no label or comment call without a PR" lacks "pr edit" "$(cat "$REC/gh.args")"
check "(m) stdout says done (PR -)" has "PAUL-37: done (PR -" "$out"
unset FAKE_GH_NO_PR

# ---------- (n) unparsable queue lines are removed and named ----------
fresh_home n
export FAKE_SCENARIO=report
printf '%s\n%s PAUL-38\n' "$proj" "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(n) run exits 0" [ "$got" -eq 0 ]
check "(n) the unparsable line is named" has "removed unparsable line from queue.txt: $proj" "$out"
check "(n) the good line was processed" grep -q " PAUL-38 done " "$QH/done.txt"
check "(n) queue.txt emptied" [ "$(live_lines "$QH/queue.txt")" = 0 ]

# ---------- (o) env file mode warning on run and list ----------
fresh_home o
export FAKE_SCENARIO=report
printf 'MISSION_CONTROL_BUDGET_USD=5\n' >"$QH/env"; chmod 644 "$QH/env"
printf '%s PAUL-39\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" list 2>&1)"; got=$?
check "(o) list warns once about the env mode" [ "$(printf '%s\n' "$out" | grep -c "has mode 644, want 600")" = 1 ]
check "(o) list still exits 0" [ "$got" -eq 0 ]
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(o) run warns about the env mode and continues" has "has mode 644, want 600" "$out"
check "(o) run still used the env file" has "--max-budget-usd 5 " "$(cat "$REC/claude.args")"
check "(o) run exits 0" [ "$got" -eq 0 ]

# ---------- (p) gh label or comment failure after the run -> labels-failed ----------
fresh_home p
export FAKE_SCENARIO=report FAKE_GH_FAIL="pr edit"
printf '%s PAUL-40\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(p) run exits 0" [ "$got" -eq 0 ]
check "(p) done.txt records done with labels-failed" grep -q " PAUL-40 done https://github.com/e/r/pull/7 no-plan labels-failed$" "$QH/done.txt"
check "(p) the failure is said" has "PAUL-40: gh pr edit (labels) failed" "$out"
check "(p) the final line shows done labels-failed" has "PAUL-40: done labels-failed (PR" "$out"
check "(p) the comment was still attempted" has "pr comment 7 --body-file" "$(cat "$REC/gh.args")"
unset FAKE_GH_FAIL

# ---------- (q) status while a run is active, then stop ----------
fresh_home q
export FAKE_SCENARIO=sleep
fakehome="$tmp/fakehome-q"; mkdir -p "$fakehome"
printf '%s PAUL-50\n%s PAUL-51\n%s PAUL-52\n%s PAUL-53\n' "$proj" "$proj" "$proj" "$proj" >"$QH/queue.txt"
printf '%s\n' "$proj" >"$QH/repos.txt"
printf '11 feat/PAUL-9-thing https://github.com/e/r/pull/11\n' >"$REC/prs.txt"
export FAKE_GH_PRS="$REC/prs.txt"
printf '2026-09-19T20:00:00Z %s PAUL-40 done https://github.com/e/r/pull/40\n' "$proj" >"$QH/done.txt"
sh "$TOOL" run >"$REC/out" 2>&1 &
runpid=$!
for _ in $(seq 1 100); do [ -f "$REC/claude.pid" ] && break; sleep 0.1; done
sleep 0.5
out="$(HOME="$fakehome" sh "$TOOL" status 2>&1)"; got=$?
check "(q) status exits 0" [ "$got" -eq 0 ]
check "(q) status shows the running item with attempt and phase" has "running: proj PAUL-50 (attempt 1, since " "$out"
check "(q) status phase is the run line from the item log" has ", phase: run (attempt 1, model sonnet, effort xhigh)" "$out"
check "(q) status: no package line for a ticket item" has "  package: none marked [~]" "$out"
check "(q) status: run line before the hook wrote one" has "  run: no status line yet" "$out"
check "(q) status: diff line" has "  diff since base: " "$out"
qwt="$QH/worktrees/proj-PAUL-50"
mkdir -p "$qwt/.claude" "$qwt/docs/autopilot/sessions/2026-09-20-PAUL-50-x"
echo "2026-09-20T22:00:00Z ctx=123456 tool=Edit" >"$qwt/.claude/.autopilot-status"
printf '# PLAN\n### P1 [x] done thing\n### P2 [~] the current package\n### P3 [ ] later\n' >"$qwt/docs/autopilot/sessions/2026-09-20-PAUL-50-x/PLAN.md"
echo new >"$qwt/new-file.txt"
printf '%s\n%s\n%s\n%s\n%s\n%s\n' proj docs/autopilot/sessions/2026-09-20-PAUL-50-x 1 "$(date +%s)" "$QH/logs/x.log" "$qwt" >"$QH/run.lock/current"
out="$(HOME="$fakehome" sh "$TOOL" status 2>&1)"
check "(q) status: current package from PLAN.md" has "  package: P2 [~] the current package" "$out"
check "(q) status: run line from the hook's status file" has "  run: 2026-09-20T22:00:00Z ctx=123456 tool=Edit" "$out"
printf '%s\n%s\n%s\n%s\n%s\n%s\n' proj PAUL-50 1 "$(date +%s)" "$QH/logs/x.log" "$qwt" >"$QH/run.lock/current"
check "(q) status counts the queue" has "queue: 4 items" "$out"
check "(q) status lists the next three lines only" [ "$(printf '%s\n' "$out" | grep -c "^  $proj PAUL-5")" = 3 ]
check "(q) status counts the labelled PRs per repo" has "labelled PRs: 1 (proj 1)" "$out"
check "(q) status shows the last done lines" has "  2026-09-19T20:00:00Z $proj PAUL-40 done" "$out"
check "(q) status says no schedule" has "schedule: not installed" "$out"
check "(q) status names the lock holder" has "lock: held by pid $runpid" "$out"
check "(q) status never prints the webhook variable" lacks "SLACK_WEBHOOK_URL" "$out"
write_plist "$fakehome" 22 5
out="$(HOME="$fakehome" sh "$TOOL" status 2>&1)"
check "(q) status reads the schedule time from the plist" has "schedule: installed at 22:05, active" "$out"
out="$(sh "$TOOL" stop 2>&1)"; got=$?
cpid="$(cat "$REC/claude.pid" 2>/dev/null || echo 0)"
wait "$runpid" 2>/dev/null
check "(q) stop exits 0" [ "$got" -eq 0 ]
check "(q) stop reports stopped with repo and item" has "stopped proj PAUL-50" "$out"
check "(q) stop killed the fake claude" bash -c '! kill -0 "$1" 2>/dev/null' _ "$cpid"
check "(q) lock released after stop" [ ! -e "$QH/run.lock" ]
kill -9 "$cpid" 2>/dev/null
out="$(HOME="$fakehome" sh "$TOOL" status 2>&1)"
check "(q) status after stop: running none" has "running: none" "$out"
check "(q) status after stop: lock free" has "lock: free" "$out"
check "(q) the stopped item is still first in queue.txt" [ "$(sh "$TOOL" list 2>/dev/null | head -n 1 | grep -c "PAUL-50")" = 1 ]
mkdir -p "$QH/run.lock"; echo 999999 >"$QH/run.lock/pid"
out="$(HOME="$fakehome" sh "$TOOL" status 2>&1)"; got=$?
check "(q) status with a stale lock exits 0" [ "$got" -eq 0 ]
check "(q) status with a stale lock: running none" has "running: none" "$out"
check "(q) status names the stale lock" has "lock: stale (pid 999999 is dead" "$out"
rm -rf "$QH/run.lock"
out="$(sh "$TOOL" stop 2>&1)"; got=$?
check "(q) stop without a run says so" has "nothing running" "$out"
check "(q) stop without a run exits 0" [ "$got" -eq 0 ]
export FAKE_GH_FAIL="pr list --label"
out="$(HOME="$fakehome" sh "$TOOL" status 2>&1)"; got=$?
check "(q) status tolerates a gh failure with a FAIL line" has "FAIL - $proj: gh pr list --label autopilot-ready failed" "$out"
check "(q) status still exits 0 on a gh failure" [ "$got" -eq 0 ]
unset FAKE_GH_FAIL FAKE_GH_PRS

# ---------- (q2) stop returns within seconds although the run loop sleeps 30 s ----------
fresh_home q2
export FAKE_SCENARIO=sleep MISSION_CONTROL_WATCH_MIN=0.5
printf '%s PAUL-54\n' "$proj" >"$QH/queue.txt"
sh "$TOOL" run >"$REC/out" 2>&1 &
runpid=$!
for _ in $(seq 1 100); do [ -f "$REC/claude.pid" ] && break; sleep 0.1; done
sleep 0.5
if [ "$(uname)" = Darwin ]; then
  fakehome="$tmp/fakehome-q2"; mkdir -p "$fakehome"
  out="$(HOME="$fakehome" sh "$TOOL" kickstart 2>&1)"; got=$?
  check "(q2) kickstart refuses while a run is active" [ "$got" -eq 1 ]
  check "(q2) kickstart names the run" has "a run is active (pid $runpid, PAUL-54), stop it first" "$out"
fi
t0="$(date +%s)"
out="$(sh "$TOOL" stop 2>&1)"; got=$?
t1="$(date +%s)"
cpid="$(cat "$REC/claude.pid" 2>/dev/null || echo 0)"
wait "$runpid" 2>/dev/null
check "(q2) stop exits 0" [ "$got" -eq 0 ]
check "(q2) stop reports stopped with the item" has "stopped proj PAUL-54" "$out"
check "(q2) stop returned within 5 s (sleep interrupted)" [ $((t1 - t0)) -le 5 ]
check "(q2) fake claude gone" bash -c '! kill -0 "$1" 2>/dev/null' _ "$cpid"
check "(q2) item still queued after stop" grep -q "PAUL-54" "$QH/queue.txt"
out="$(sh "$TOOL" log PAUL-54 2>&1)"; got=$?
check "(q2) log still finds the stopped item's log" [ "$got" -eq 0 ]
kill -9 "$cpid" 2>/dev/null
export MISSION_CONTROL_WATCH_MIN=0

# ---------- (r) retry: a PR gets its label back, an item is queued again ----------
fresh_home r
export FAKE_SCENARIO=report-blocked
out="$(sh "$TOOL" retry "$proj" '#41' 2>&1)"; got=$?
check "(r) retry #pr exits 0" [ "$got" -eq 0 ]
check "(r) retry #pr swaps blocked for ready" has "pr edit 41 --remove-label autopilot-blocked --add-label autopilot-ready" "$(cat "$REC/gh.args")"
check "(r) retry #pr says so" has "retry: PR #41 in proj labelled autopilot-ready again" "$out"
out="$(sh "$TOOL" retry "$proj" 42 2>&1)"
check "(r) retry accepts a bare number" has "pr edit 42 --remove-label autopilot-blocked" "$(cat "$REC/gh.args")"
export FAKE_GH_FAIL="pr edit"
out="$(sh "$TOOL" retry "$proj" '#43' 2>&1)"; got=$?
check "(r) retry #pr exits 1 when gh fails" [ "$got" -eq 1 ]
check "(r) retry #pr names the failure with gh's first stderr line" has "gh pr edit 43 failed in proj: fake gh: failing on purpose" "$out"
unset FAKE_GH_FAIL
out="$(sh "$TOOL" retry "$proj" 12abc 2>&1)"
check "(r) retry treats a mixed argument as an item, not a PR" grep -qxF "$proj 12abc" "$QH/queue.txt"
check "(r) retry did not label a PR for the mixed argument" lacks "pr edit 12abc" "$(cat "$REC/gh.args")"
sh "$TOOL" add "$proj" docs/autopilot/sessions/2026-09-19-PAUL-9-thing feat/PAUL-9-thing >/dev/null
sh "$TOOL" run >/dev/null 2>&1
check "(r) blocked run left its worktree" [ -e "$QH/worktrees/proj-2026-09-19-PAUL-9-thing/.git" ]
check "(r) queue empty before retry" [ "$(live_lines "$QH/queue.txt")" = 0 ]
# the branch the kept worktree is on (detached at its tip when (j) still holds the branch,
# then the fake run created its own); retry must record exactly that one
wt_branch="$(git -C "$QH/worktrees/proj-2026-09-19-PAUL-9-thing" symbolic-ref --short HEAD)"
check "(r) the worktree is on a branch" [ -n "$wt_branch" ]
out="$(sh "$TOOL" retry "$proj" docs/autopilot/sessions/2026-09-19-PAUL-9-thing 2>&1)"; got=$?
check "(r) retry item exits 0" [ "$got" -eq 0 ]
check "(r) retry item queues it with the worktree's branch" grep -qxF "$proj docs/autopilot/sessions/2026-09-19-PAUL-9-thing $wt_branch" "$QH/queue.txt"
check "(r) retry item says added" has "added: $proj docs/autopilot/sessions/2026-09-19-PAUL-9-thing $wt_branch" "$out"
out="$(sh "$TOOL" retry "$proj" PAUL-31 2>&1)"
check "(r) retry ticket key queues it" grep -qxF "$proj PAUL-31" "$QH/queue.txt"
out="$(sh "$TOOL" retry "$tmp/nowhere" '#1' 2>&1)"; got=$?
check "(r) retry refuses a non-repo" [ "$got" -eq 1 ]
out="$(HOME="$tmp" sh "$TOOL" retry '~/proj' PAUL-44 2>&1)"
check "(r) retry expands ~ in the repo path" grep -qxF "$proj PAUL-44" "$QH/queue.txt"
out="$(HOME="$tmp" sh "$TOOL" add '~/proj' PAUL-45 2>&1)"
check "(r) add expands ~ in the repo path" grep -qxF "$proj PAUL-45" "$QH/queue.txt"
out="$(MISSION_CONTROL_PROJECTS="$tmp" sh "$TOOL" add proj PAUL-46 2>&1)"; got=$?
check "(r) add resolves a bare project name under the projects directory" grep -qxF "$proj PAUL-46" "$QH/queue.txt"
out="$(MISSION_CONTROL_PROJECTS="$tmp" sh "$TOOL" add nosuchproj PAUL-47 2>&1)"; got=$?
check "(r) a bare name that resolves to nothing is refused" [ "$got" -eq 1 ]
check "(r) refusal names the argument" has "nosuchproj is not a git repository" "$out"
out="$(HOME="$tmp" sh "$TOOL" labels '~/proj' 2>&1)"; got=$?
check "(r) labels expands ~ in the repo path" [ "$got" -eq 0 ]

# ---------- (s) log: newest item log, or by substring ----------
fresh_home s
export FAKE_SCENARIO=report
printf '%s PAUL-60\n' "$proj" >"$QH/queue.txt"
sh "$TOOL" run >/dev/null 2>&1
sleep 1
printf '%s PAUL-61\n' "$proj" >"$QH/queue.txt"
sh "$TOOL" run >/dev/null 2>&1
out="$(sh "$TOOL" log 2>&1)"; got=$?
check "(s) log exits 0" [ "$got" -eq 0 ]
check "(s) log names the newest item log" has "log: $QH/logs/" "$out"
check "(s) log picks the newest item" has "PAUL-61.log" "$(printf '%s\n' "$out" | head -n 1)"
check "(s) log shows the log content" has "PAUL-61: done (PR" "$out"
out="$(sh "$TOOL" log PAUL-60 2>&1)"; got=$?
check "(s) log <substring> exits 0" [ "$got" -eq 0 ]
check "(s) log <substring> names that file" has "PAUL-60.log" "$(printf '%s\n' "$out" | head -n 1)"
check "(s) log <substring> shows that run" has "PAUL-60: done (PR" "$out"
check "(s) log output is at most 41 lines" [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -le 41 ]
out="$(sh "$TOOL" log NOPE 2>&1)"; got=$?
check "(s) log with no match exits 1" [ "$got" -eq 1 ]
check "(s) log with no match says so" has "no item log with 'NOPE'" "$out"
# hand-made logs: the timestamp part must never match, the item part matches after safe_name
fresh_home s2
mkdir -p "$QH/logs"
printf '2026-12-12T12:12:12Z proj PAUL-70: done\n' >"$QH/logs/20261212-121212-PAUL-70.log"
sleep 1
printf '2026-12-12T12:12:13Z proj #34: resolving\n' >"$QH/logs/20261212-121213-_34-2026-09-19-PAUL-2801-export.log"
out="$(sh "$TOOL" log '#34' 2>&1)"; got=$?
check "(s2) log '#34' finds the PR item's log" has "_34-2026-09-19-PAUL-2801-export.log" "$(printf '%s\n' "$out" | head -n 1)"
out="$(sh "$TOOL" log PAUL-2801 2>&1)"; got=$?
check "(s2) log <ticket key> finds the run whose session dir contains the key" has "_34-2026-09-19-PAUL-2801-export.log" "$(printf '%s\n' "$out" | head -n 1)"
out="$(sh "$TOOL" log docs/autopilot/sessions/2026-09-19-PAUL-2801-export 2>&1)"; got=$?
check "(s2) log <session dir> finds it too" [ "$got" -eq 0 ]
out="$(sh "$TOOL" log 12 2>&1)"; got=$?
check "(s2) log 12 does not match the timestamp" [ "$got" -eq 1 ]
out="$(sh "$TOOL" log PAUL-70 2>&1)"
check "(s2) log PAUL-70 finds the older log" has "20261212-121212-PAUL-70.log" "$(printf '%s\n' "$out" | head -n 1)"
out="$(sh "$TOOL" bogus 2>&1)"
check "(s) unknown command lists the new commands" has "status | stop | retry | log" "$out"
out="$(sh "$TOOL" help 2>&1)"
check "(s) usage mentions start" has "mission-control start" "$out"

# ---------- (t) pause: scheduled runs skip, manual runs go on ----------
today="$(date +%Y-%m-%d)"
yesterday="$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d yesterday +%Y-%m-%d)"
in3days="$(date -v+3d +%Y-%m-%d 2>/dev/null || date -d "+3 days" +%Y-%m-%d)"
fresh_home t
export FAKE_SCENARIO=report
fakehome="$tmp/fakehome-t"; write_plist "$fakehome" 22 0
out="$(HOME="$fakehome" sh "$TOOL" status 2>&1)"
check "(t) status: schedule active without a pause file" has "schedule: installed at 22:00, active" "$out"
out="$(HOME="$fakehome" sh "$TOOL" pause 2>&1)"; got=$?
check "(t) pause exits 0" [ "$got" -eq 0 ]
check "(t) pause says paused until today" [ "$out" = "paused until $today" ]
check "(t) pause file holds today's date" [ "$(cat "$QH/paused")" = "$today" ]
out="$(HOME="$fakehome" sh "$TOOL" status 2>&1)"
check "(t) status: schedule paused until today, nothing after the date" bash -c 'printf "%s\n" "$1" | grep -qx "schedule: installed at 22:00, paused until $2"' _ "$out" "$today"
check "(t) status: the date appears once on the schedule line" [ "$(printf '%s\n' "$out" | grep -c "$today$today")" = 0 ]
printf '%s PAUL-80\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run --scheduled 2>&1)"; got=$?
check "(t) scheduled run exits 0 while paused" [ "$got" -eq 0 ]
check "(t) scheduled run says it skipped" has "paused until $today: scheduled run skipped (manual runs still work)" "$out"
check "(t) scheduled run logged the skip" grep -q "paused until $today: scheduled run skipped" "$QH/logs/queue.log"
check "(t) scheduled run left the queue alone" [ "$(live_lines "$QH/queue.txt")" = 1 ]
check "(t) scheduled run did not start claude" [ ! -e "$REC/claude.args" ]
check "(t) scheduled run did not take the lock" [ ! -e "$QH/run.lock" ]
out="$(sh "$TOOL" run 2>&1)"; got=$?
check "(t) manual run exits 0 while paused" [ "$got" -eq 0 ]
check "(t) manual run processed the item" grep -q " PAUL-80 done " "$QH/done.txt"
check "(t) manual run kept the pause" [ "$(cat "$QH/paused")" = "$today" ]
out="$(HOME="$fakehome" sh "$TOOL" resume 2>&1)"; got=$?
check "(t) resume exits 0" [ "$got" -eq 0 ]
check "(t) resume says resumed" [ "$out" = "resumed" ]
check "(t) resume removed the file" [ ! -e "$QH/paused" ]
out="$(HOME="$fakehome" sh "$TOOL" resume 2>&1)"; got=$?
check "(t) resume without a pause exits 0" [ "$got" -eq 0 ]
check "(t) resume without a pause says not paused" [ "$out" = "not paused" ]
# expired pause: removed, run proceeds
printf '%s\n' "$yesterday" >"$QH/paused"
printf '%s PAUL-81\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run --scheduled 2>&1)"; got=$?
check "(t) expired pause: scheduled run exits 0" [ "$got" -eq 0 ]
check "(t) expired pause: item processed" grep -q " PAUL-81 done " "$QH/done.txt"
check "(t) expired pause: file removed" [ ! -e "$QH/paused" ]
check "(t) expired pause: logged" grep -q "pause expired ($yesterday), file removed" "$QH/logs/queue.log"
out="$(HOME="$fakehome" sh "$TOOL" status 2>&1)"
check "(t) status: active again after the expired pause" has "schedule: installed at 22:00, active" "$out"
# unreadable pause file (empty, garbage): removed and said, run proceeds
for junk in "" garbage; do
  printf '%s' "$junk" >"$QH/paused"
  printf '%s PAUL-81\n' "$proj" >"$QH/queue.txt"
  out="$(sh "$TOOL" run --scheduled 2>&1)"; got=$?
  shown="${junk:-empty}"
  check "(t) unreadable pause '$shown': scheduled run exits 0" [ "$got" -eq 0 ]
  check "(t) unreadable pause '$shown': said on stdout" has "[mission-control] pause file unreadable ($shown), removed, run goes ahead" "$out"
  check "(t) unreadable pause '$shown': logged" grep -q "pause file unreadable ($shown), removed, run goes ahead" "$QH/logs/queue.log"
  check "(t) unreadable pause '$shown': not called expired" lacks "expired ($shown)" "$out"
  check "(t) unreadable pause '$shown': file removed" [ ! -e "$QH/paused" ]
  check "(t) unreadable pause '$shown': item processed" grep -q " PAUL-81 done " "$QH/done.txt"
done
check "(t) unreadable pause: run went ahead both times" [ "$(grep -c " PAUL-81 done " "$QH/done.txt")" = 3 ]
# pause until <date>, pause <N>d, invalid dates, a date in the past
out="$(HOME="$fakehome" sh "$TOOL" pause until 2099-12-31 2>&1)"; got=$?
check "(t) pause until exits 0" [ "$got" -eq 0 ]
check "(t) pause until says the date" [ "$out" = "paused until 2099-12-31" ]
check "(t) pause until writes the date" [ "$(cat "$QH/paused")" = "2099-12-31" ]
out="$(HOME="$fakehome" sh "$TOOL" pause until "$today" 2>&1)"; got=$?
check "(t) pause until today is allowed" [ "$got" -eq 0 ]
out="$(HOME="$fakehome" sh "$TOOL" pause 3d 2>&1)"; got=$?
check "(t) pause 3d exits 0" [ "$got" -eq 0 ]
check "(t) pause 3d says the date three days ahead" [ "$out" = "paused until $in3days" ]
check "(t) pause 3d writes that date" [ "$(cat "$QH/paused")" = "$in3days" ]
out="$(HOME="$fakehome" sh "$TOOL" pause until "$yesterday" 2>&1)"; got=$?
check "(t) pause until <yesterday> exits 2" [ "$got" -eq 2 ]
check "(t) pause until <yesterday> says the date is in the past" [ "$out" = "mission-control: date is in the past: $yesterday" ]
check "(t) pause until <yesterday> left the previous pause untouched" [ "$(cat "$QH/paused")" = "$in3days" ]
pause_usage="usage: mission-control pause [until <YYYY-MM-DD> | <N>d]"
for case in \
  "until 2026-02-30|not a date: '2026-02-30' (want YYYY-MM-DD" \
  "until 31.12.2026|not a date: '31.12.2026' (want YYYY-MM-DD" \
  "until yesterday|not a date: 'yesterday' (want YYYY-MM-DD" \
  "until|$pause_usage (got: until)" \
  "3|$pause_usage (got: 3)" \
  "x3d|$pause_usage (got: x3d)" \
  "3d extra|$pause_usage"; do
  bad="${case%%|*}"; want="${case#*|}"
  # shellcheck disable=SC2086
  out="$(HOME="$fakehome" sh "$TOOL" pause $bad 2>&1)"; got=$?
  check "(t) pause $bad exits 2" [ "$got" -eq 2 ]
  check "(t) pause $bad names the problem" has "mission-control: $want" "$out"
done
check "(t) an invalid pause left the previous pause untouched" [ "$(cat "$QH/paused")" = "$in3days" ]
# force-once: consumed by the scheduled run, overrides the pause once
: >"$QH/force-once"
printf '%s PAUL-82\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run --scheduled 2>&1)"; got=$?
check "(t) force-once: scheduled run exits 0" [ "$got" -eq 0 ]
check "(t) force-once: item processed despite the pause" grep -q " PAUL-82 done " "$QH/done.txt"
check "(t) force-once: file consumed" [ ! -e "$QH/force-once" ]
check "(t) force-once: pause still in place" [ "$(cat "$QH/paused")" = "$in3days" ]
printf '%s PAUL-83\n' "$proj" >"$QH/queue.txt"
out="$(sh "$TOOL" run --scheduled 2>&1)"
check "(t) the next scheduled run is paused again" has "paused until $in3days: scheduled run skipped" "$out"
check "(t) the next scheduled run left the item queued" [ "$(live_lines "$QH/queue.txt")" = 1 ]
out="$(sh "$TOOL" run --bogus 2>&1)"; got=$?
check "(t) run rejects an unknown flag with exit 2" [ "$got" -eq 2 ]
out="$(sh "$TOOL" bogus 2>&1)"
check "(t) unknown command lists pause and resume" has "pause | resume" "$out"
out="$(sh "$TOOL" help 2>&1)"
check "(t) usage mentions pause" has "pause" "$out"

# ---------- (t2) install-schedule writes run --scheduled; kickstart writes force-once ----------
if [ "$(uname)" = Darwin ]; then
  cat >"$tmp/fakes/launchctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_RECORD/launchctl.args"
exit 0
EOF
  chmod +x "$tmp/fakes/launchctl"
  fresh_home t2
  fakehome="$tmp/fakehome-t2"; mkdir -p "$fakehome"
  plist="$fakehome/Library/LaunchAgents/de.evelan.mission-control.plist"
  out="$(HOME="$fakehome" PATH="$tmp/fakes:$PATH" sh "$TOOL" install-schedule 22:00 2>&1)"; got=$?
  check "(t2) install-schedule exits 0" [ "$got" -eq 0 ]
  check "(t2) plist written under the temporary HOME" [ -f "$plist" ]
  check "(t2) plist runs mission-control run --scheduled" grep -q '<string>run</string><string>--scheduled</string>' "$plist"
  check "(t2) plist carries the time" grep -q '<key>Hour</key><integer>22</integer><key>Minute</key><integer>0</integer>' "$plist"
  la="$(cat "$REC/launchctl.args")"
  check "(t2) install-schedule boots out, then bootstraps" [ "$(printf '%s\n' "$la" | grep -c .)" = 2 ]
  check "(t2) bootout first" has "bootout gui/" "$(printf '%s\n' "$la" | sed -n 1p)"
  check "(t2) bootstrap second" has "bootstrap gui/" "$(printf '%s\n' "$la" | sed -n 2p)"
  check "(t2) only the fake launchctl was called (no real launchd)" lacks "kickstart" "$la"
  out="$(HOME="$fakehome" PATH="$tmp/fakes:$PATH" sh "$TOOL" install-schedule 23:30 2>&1)"
  check "(t2) re-running install-schedule replaces the plist" grep -q '<key>Hour</key><integer>23</integer><key>Minute</key><integer>30</integer>' "$plist"
  check "(t2) re-run booted out and bootstrapped again" [ "$(grep -c . "$REC/launchctl.args")" = 4 ]
  sh "$TOOL" pause >/dev/null
  out="$(HOME="$fakehome" PATH="$tmp/fakes:$PATH" sh "$TOOL" kickstart 2>&1)"; got=$?
  check "(t2) kickstart exits 0 during a pause" [ "$got" -eq 0 ]
  check "(t2) kickstart called launchctl kickstart" has "kickstart gui/" "$(tail -n 1 "$REC/launchctl.args")"
  check "(t2) kickstart wrote force-once" [ -e "$QH/force-once" ]
  check "(t2) kickstart says the pause is overridden once" has "the pause until $today is overridden for this run only" "$out"
  export FAKE_SCENARIO=report
  printf '%s PAUL-84\n' "$proj" >"$QH/queue.txt"
  out="$(sh "$TOOL" run --scheduled 2>&1)"
  check "(t2) the kickstarted scheduled run processed the item" grep -q " PAUL-84 done " "$QH/done.txt"
  check "(t2) force-once consumed by that run" [ ! -e "$QH/force-once" ]
  rm -f "$plist"; : >"$REC/launchctl.args"
  out="$(HOME="$fakehome" PATH="$tmp/fakes:$PATH" sh "$TOOL" start 2>&1)"; got=$?
  check "(t2) start without a schedule exits 0" [ "$got" -eq 0 ]
  check "(t2) start installed the LaunchAgent on demand" [ -f "$plist" ]
  check "(t2) on-demand plist has no StartCalendarInterval" bash -c '! grep -q StartCalendarInterval "$1"' _ "$plist"
  check "(t2) on-demand plist still runs run --scheduled" grep -q '<string>run</string><string>--scheduled</string>' "$plist"
  check "(t2) start booted out, bootstrapped, then kickstarted" [ "$(sed -n '1p;2p;3p' "$REC/launchctl.args" | cut -d' ' -f1 | tr '\n' ' ')" = "bootout bootstrap kickstart " ]
  check "(t2) start wrote force-once" [ -e "$QH/force-once" ]
  check "(t2) start says where the output goes" has 'started: de.evelan.mission-control runs now in the GUI session' "$out"
  out="$(HOME="$fakehome" PATH="$tmp/fakes:$PATH" sh "$TOOL" status 2>&1)"
  check "(t2) status shows the on-demand schedule" has 'schedule: on demand only ("mission-control start"), no nightly run' "$out"
  rm -f "$QH/force-once"
  mkdir -p "$QH/run.lock"; echo "$$" >"$QH/run.lock/pid"
  out="$(HOME="$fakehome" PATH="$tmp/fakes:$PATH" sh "$TOOL" start 2>&1)"; got=$?
  check "(t2) start during a run exits 1" [ "$got" -eq 1 ]
  check "(t2) refused start (active run) wrote no force-once" [ ! -e "$QH/force-once" ]
  out="$(HOME="$fakehome" PATH="$tmp/fakes:$PATH" sh "$TOOL" kickstart 2>&1)"; got=$?
  check "(t2) kickstart is an alias of start (refused the same way)" [ "$got" -eq 1 ]
  rm -rf "$QH/run.lock"
fi

# ---------- (t3) legacy plist (no --scheduled): pause, resume and status warn ----------
fresh_home t3
fakehome="$tmp/fakehome-t3"; write_plist "$fakehome" 21 15 legacy
legacy_warn='schedule installed without --scheduled: run "mission-control install-schedule 21:15" again, otherwise the nightly job ignores the pause'
out="$(HOME="$fakehome" sh "$TOOL" status 2>&1)"; got=$?
check "(t3) status exits 0 with a legacy plist" [ "$got" -eq 0 ]
check "(t3) status shows the legacy schedule line" has "schedule: installed at 21:15 (legacy, ignores pause)" "$out"
check "(t3) status prints the warning with the plist time" has "$legacy_warn" "$out"
out="$(HOME="$fakehome" sh "$TOOL" pause 2>&1)"; got=$?
check "(t3) pause exits 0 with a legacy plist" [ "$got" -eq 0 ]
check "(t3) pause still writes the file" [ "$(cat "$QH/paused")" = "$today" ]
check "(t3) pause says paused" has "paused until $today" "$out"
check "(t3) pause prints the warning" has "$legacy_warn" "$out"
out="$(HOME="$fakehome" sh "$TOOL" status 2>&1)"
check "(t3) status with a legacy plist and a pause still says legacy" has "schedule: installed at 21:15 (legacy, ignores pause)" "$out"
check "(t3) status with a legacy plist never says paused until" lacks "paused until" "$out"
out="$(HOME="$fakehome" sh "$TOOL" resume 2>&1)"; got=$?
check "(t3) resume exits 0 with a legacy plist" [ "$got" -eq 0 ]
check "(t3) resume says resumed" has "resumed" "$out"
check "(t3) resume prints the warning" has "$legacy_warn" "$out"
write_plist "$fakehome" 21 15
out="$(HOME="$fakehome" sh "$TOOL" pause 2>&1)"
check "(t3) a plist with --scheduled gets no warning from pause" [ "$out" = "paused until $today" ]
out="$(HOME="$fakehome" sh "$TOOL" status 2>&1)"
check "(t3) a plist with --scheduled gets no warning from status" lacks "without --scheduled" "$out"
rm -f "$fakehome/Library/LaunchAgents/de.evelan.mission-control.plist"
out="$(HOME="$fakehome" sh "$TOOL" resume 2>&1)"
check "(t3) no plist: no warning from resume" [ "$out" = "resumed" ]

# ---------- (v) PR items resolve their plan against the PR's target branch ----------
fresh_home v
export FAKE_SCENARIO=report
printf '16 feat/default-org-redirect https://github.com/e/r/pull/16 preview\n17 feat/borrowed-plan https://github.com/e/r/pull/17 preview\n18 feat/big https://github.com/e/r/pull/18 preview\n' >"$REC/prs.txt"
export FAKE_GH_PRS="$REC/prs.txt"
printf '%s\n' "$proj" >"$QH/repos.txt"
out="$(sh "$TOOL" run 2>&1)"
cl="$(cat "$REC/claude.args" 2>/dev/null)"
check "(v) PR 16 runs its own plan" has "/autopilot docs/autopilot/sessions/2026-09-23-default-org-redirect " "$cl"
check "(v) the finished session on preview is never run" lacks "2026-09-23-two-factor-auth" "$cl"
check "(v) PR 16 done with its own session dir" grep -q " docs/autopilot/sessions/2026-09-23-default-org-redirect done https://github.com/e/r/pull/16$" "$QH/done.txt"
check "(v) PR 17 (its plan names another branch) not run" lacks "2026-09-24-borrowed" "$cl"
check "(v) PR 17 blocked" grep -q " docs/autopilot/sessions/2026-09-24-borrowed blocked https://github.com/e/r/pull/17$" "$QH/done.txt"
check "(v) the reason names both branches" has "belongs to branch feat/somewhere-else, not to the PR branch feat/borrowed-plan" "$out"
check "(v) PR 17 labelled blocked" has "pr edit 17 --remove-label autopilot-ready --add-label autopilot-blocked" "$(cat "$REC/gh.args")"
check "(v) PR 18 (a feature-branch session on its feature branch) runs" has "/autopilot docs/autopilot/sessions/2026-09-24-big-s2 " "$cl"
unset FAKE_GH_PRS

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
