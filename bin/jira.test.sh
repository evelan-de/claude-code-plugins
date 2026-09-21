#!/usr/bin/env bash
# Tests for bin/jira with a fake curl. Run: bash bin/jira.test.sh
set -uo pipefail
TOOL="$(cd "$(dirname "$0")" && pwd)/jira"
PASS=0; FAIL=0
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
ok() { echo "ok   - $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL - $1"; FAIL=$((FAIL+1)); }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else fail "$d"; fi; }
has() { case "$2" in *"$1"*) return 0;; *) return 1;; esac; }
lacks() { ! has "$1" "$2"; }

# The fake curl reads the config file jira writes (-K), records method, url and body, and
# answers from canned responses keyed by method+path.
REC="$tmp/rec"; mkdir -p "$REC"
cat >"$tmp/curl" <<'EOF'
#!/usr/bin/env bash
cfg=""; data=""
while [ $# -gt 0 ]; do
  case "$1" in -K) cfg="$2"; shift ;; --data-binary) data="${2#@}"; shift ;; esac
  shift
done
method="$(sed -n 's/^request = "\(.*\)"$/\1/p' "$cfg")"
url="$(sed -n 's/^url = "\(.*\)"$/\1/p' "$cfg")"
user="$(sed -n 's/^user = "\(.*\)"$/\1/p' "$cfg")"
path="${url#https://jira.test}"
body=""; [ -n "$data" ] && body="$(cat "$data")"
printf '%s %s %s\n' "$method" "$path" "$body" >>"$FAKE_RECORD/curl.log"
printf '%s\n' "$user" >>"$FAKE_RECORD/users.log"
[ -n "${FAKE_CURL_DIE:-}" ] && { echo "curl: (6) Could not resolve host: jira.test" >&2; exit 6; }
case "$method $path" in
  "GET /rest/api/2/myself") printf '{"accountId":"acc-1","displayName":"Andreas Straub"}\n200' ;;
  "GET /rest/api/2/issue/WEB-1?fields=status") printf '{"fields":{"status":{"name":"%s"}}}\n200' "${FAKE_STATUS:-To Do}" ;;
  "GET /rest/api/2/issue/WEB-1?fields=summary,status,assignee") printf '{"fields":{"summary":"Do the thing","status":{"name":"%s"},"assignee":{"displayName":"Andreas Straub","accountId":"%s"}}}\n200' "${FAKE_STATUS_AFTER:-In Arbeit}" "${FAKE_ASSIGNEE_AFTER:-acc-1}" ;;
  "GET /rest/api/2/issue/WEB-1/comment/9001") if [ -n "${FAKE_COMMENT_EMPTY:-}" ]; then printf '{"id":"9001","body":""}\n200'; else printf '{"id":"9001","body":"Status: done"}\n200'; fi ;;
  "GET /rest/api/2/issue/WEB-1?fields=summary,status,assignee,description") printf '{"fields":{"summary":"Do the thing","status":{"name":"To Do"},"assignee":null,"description":"Body text"}}\n200' ;;
  "GET /rest/api/2/issue/WEB-1/transitions") printf '{"transitions":[{"id":"11","name":"Start work","to":{"name":"In Arbeit"}},{"id":"31","name":"Done","to":{"name":"Fertig"}}]}\n200' ;;
  "POST /rest/api/2/issue/WEB-1/transitions") printf '\n204' ;;
  "PUT /rest/api/2/issue/WEB-1/assignee") [ -n "${FAKE_ASSIGN_FAIL:-}" ] && printf '{"errorMessages":["User cannot be assigned issues."]}\n400' || printf '\n204' ;;
  "POST /rest/api/2/issue/WEB-1/comment") printf '{"id":"9001"}\n201' ;;
  "GET /rest/api/2/issue/WEB-404?fields=summary,status,assignee,description") printf '{"errorMessages":["Issue does not exist or you do not have permission to see it."],"errors":{}}\n404' ;;
  *) printf '{"errorMessages":["unexpected %s %s"]}\n500' "$method" "$path" ;;
esac
EOF
chmod +x "$tmp/curl"
export CURL_BIN="$tmp/curl" FAKE_RECORD="$REC"

# ---------- no env file ----------
export JIRA_HOME="$tmp/nohome"
out="$(sh "$TOOL" view WEB-1 2>&1)"; got=$?
check "no env: exit 1" [ "$got" -eq 1 ]
check "no env: names the file and the variables" has "JIRA_SITE, JIRA_EMAIL and JIRA_TOKEN into $tmp/nohome/env" "$out"
out="$(sh "$TOOL" doctor 2>&1)"; got=$?
check "doctor without env exits 1" [ "$got" -eq 1 ]
check "doctor names the missing file" has "FAIL - $tmp/nohome/env missing" "$out"

# ---------- env file ----------
export JIRA_HOME="$tmp/home"; mkdir -p "$JIRA_HOME"
printf 'JIRA_SITE=https://jira.test/\nJIRA_EMAIL=a@b.c\nJIRA_TOKEN=SECRET-TOKEN-XYZ\n' >"$JIRA_HOME/env"; chmod 600 "$JIRA_HOME/env"

out="$(sh "$TOOL" doctor 2>&1)"; got=$?
check "doctor exits 0" [ "$got" -eq 0 ]
check "doctor reports the login" has "ok   - login: Andreas Straub (acc-1)" "$out"
check "doctor never prints the token" lacks "SECRET-TOKEN-XYZ" "$out"
chmod 644 "$JIRA_HOME/env"
out="$(sh "$TOOL" doctor 2>&1)"; got=$?
check "doctor fails on a readable env file" [ "$got" -eq 1 ]
check "doctor names the mode" has "has mode 644, expected 600" "$out"
chmod 600 "$JIRA_HOME/env"

# ---------- view ----------
out="$(sh "$TOOL" view WEB-1 2>&1)"; got=$?
check "view exits 0" [ "$got" -eq 0 ]
check "view first line: key, status, assignee, summary" [ "$(printf '%s\n' "$out" | sed -n 1p)" = "WEB-1  To Do  unassigned  Do the thing" ]
check "view prints the description" has "Body text" "$out"
check "trailing slash stripped from the site" grep -q "GET /rest/api/2/issue/WEB-1?fields=summary,status,assignee,description" "$REC/curl.log"
check "credentials went through the config file" grep -q "^a@b.c:SECRET-TOKEN-XYZ$" "$REC/users.log"
out="$(sh "$TOOL" view WEB-404 2>&1)"; got=$?
check "view of a missing issue exits 1" [ "$got" -eq 1 ]
check "view error names the HTTP status and Jira's message" has "HTTP 404 on GET /rest/api/2/issue/WEB-404" "$out"
out="$(sh "$TOOL" view web-1 2>&1)"; got=$?
check "lowercase key refused" [ "$got" -eq 1 ]

# ---------- start ----------
: >"$REC/curl.log"
out="$(sh "$TOOL" start WEB-1 2>&1)"; got=$?
check "start exits 0" [ "$got" -eq 0 ]
check "start transitions via the id whose target is In Arbeit" grep -q 'POST /rest/api/2/issue/WEB-1/transitions {"transition":{"id":"11"}}' "$REC/curl.log"
check "start assigns to the token owner" grep -q 'PUT /rest/api/2/issue/WEB-1/assignee {"accountId":"acc-1"}' "$REC/curl.log"
check "start reads the issue back" has "started: WEB-1  In Arbeit  Andreas Straub  Do the thing" "$out"
: >"$REC/curl.log"
out="$(FAKE_STATUS="In Arbeit" sh "$TOOL" start WEB-1 2>&1)"; got=$?
check "start on an issue already in progress skips the transition" bash -c '! grep -q "POST /rest/api/2/issue/WEB-1/transitions" "$1"' _ "$REC/curl.log"
check "start says it was already in that status" has "(was already in that status)" "$out"
out="$(JIRA_START_STATUS="Doing" sh "$TOOL" start WEB-1 2>&1)"; got=$?
check "start with an unknown target exits 1" [ "$got" -eq 1 ]
check "start lists the available targets" has "available targets: In Arbeit, Fertig" "$out"

# ---------- transition, assign ----------
out="$(sh "$TOOL" transition WEB-1 "in arbeit" 2>&1)"; got=$?
check "transition matches the target case-insensitively" [ "$got" -eq 0 ]
check "transition prints the read-back line" has "transitioned: WEB-1  In Arbeit" "$out"
out="$(sh "$TOOL" transition WEB-1 "Nope" 2>&1)"; got=$?
check "transition to an unknown status exits 1" [ "$got" -eq 1 ]
: >"$REC/curl.log"
out="$(FAKE_ASSIGNEE_AFTER=acc-2 sh "$TOOL" assign WEB-1 acc-2 2>&1)"; got=$?
check "assign by accountId" grep -q 'PUT /rest/api/2/issue/WEB-1/assignee {"accountId":"acc-2"}' "$REC/curl.log"
check "assign prints the read-back line" has "assigned: WEB-1" "$out"
out="$(FAKE_ASSIGNEE_AFTER=acc-1 sh "$TOOL" assign WEB-1 acc-2 2>&1)"; got=$?
check "assign: read-back assignee differs -> exit 1" [ "$got" -eq 1 ]
check "assign: mismatch message names both" has "read-back assignee is 'acc-1', expected 'acc-2'" "$out"
out="$(FAKE_ASSIGN_FAIL=1 sh "$TOOL" assign WEB-1 acc-2 2>&1)"; got=$?
check "assign: non-2xx on the write -> exit 1" [ "$got" -eq 1 ]
check "assign: Jira's error message relayed" has "HTTP 400 on PUT /rest/api/2/issue/WEB-1/assignee: User cannot be assigned issues." "$out"
out="$(FAKE_STATUS_AFTER="To Do" sh "$TOOL" transition WEB-1 "In Arbeit" 2>&1)"; got=$?
check "transition: read-back status differs -> exit 1" [ "$got" -eq 1 ]
check "transition: mismatch message" has "read-back status is 'To Do', expected 'In Arbeit'" "$out"
out="$(FAKE_STATUS_AFTER="To Do" sh "$TOOL" start WEB-1 2>&1)"; got=$?
check "start: read-back status differs -> exit 1" [ "$got" -eq 1 ]
out="$(JIRA_SITE=https://jira.test JIRA_HOME="$tmp/nohome" sh "$TOOL" view WEB-1 2>&1)"; got=$?
check "env vars alone (no file) are not enough without email and token" [ "$got" -eq 1 ]
out="$(JIRA_TOKEN=OTHER sh "$TOOL" view WEB-1 2>&1)"; got=$?
check "env var overrides the file" grep -q "^a@b.c:OTHER$" "$REC/users.log"

# ---------- comment ----------
: >"$REC/curl.log"
out="$(sh "$TOOL" comment WEB-1 'Status: done. PR https://github.com/e/r/pull/1' 2>&1)"; got=$?
check "comment exits 0" [ "$got" -eq 0 ]
check "comment posts the plain-text body" grep -q 'POST /rest/api/2/issue/WEB-1/comment {"body":"Status: done. PR https://github.com/e/r/pull/1"}' "$REC/curl.log"
check "comment reads the comment back" grep -q 'GET /rest/api/2/issue/WEB-1/comment/9001' "$REC/curl.log"
check "comment prints the id and the read-back length" has "commented: WEB-1 comment 9001 (12 chars read back)" "$out"
out="$(FAKE_COMMENT_EMPTY=1 sh "$TOOL" comment WEB-1 'x' 2>&1)"; got=$?
check "comment read back empty -> exit 1" [ "$got" -eq 1 ]
check "comment read back empty: message" has "comment 9001 read back empty" "$out"
out="$(printf 'line one\nline "two"\n' | sh "$TOOL" comment WEB-1 - 2>&1)"; got=$?
check "comment from stdin exits 0" [ "$got" -eq 0 ]
check "comment from stdin keeps newlines and quotes (JSON-escaped)" grep -q '{"body":"line one\\nline \\"two\\""}' "$REC/curl.log"
out="$(sh "$TOOL" comment WEB-1 2>&1)"; got=$?
check "comment without text exits 1" [ "$got" -eq 1 ]

# ---------- transport failure, usage ----------
out="$(FAKE_CURL_DIE=1 sh "$TOOL" view WEB-1 2>&1)"; got=$?
check "curl failure exits 1" [ "$got" -eq 1 ]
check "curl failure names the call" has "curl failed (GET /rest/api/2/issue/WEB-1" "$out"
check "curl failure never prints the token" lacks "SECRET-TOKEN-XYZ" "$out"
out="$(sh "$TOOL" 2>&1)"; got=$?
check "no command: usage, exit 2" [ "$got" -eq 2 ]
check "usage lists the commands" has "jira comment <KEY>" "$out"
out="$(sh "$TOOL" bogus 2>&1)"; got=$?
check "unknown command: exit 2" [ "$got" -eq 2 ]
check "no temp config left behind" bash -c '! ls "${TMPDIR:-/tmp}"/jira.?????? >/dev/null 2>&1'
# a curl that hangs, killed by TERM: the config file with the token must be gone
cat >"$tmp/curl-hang" <<'EOF2'
#!/usr/bin/env bash
sleep 30
EOF2
chmod +x "$tmp/curl-hang"
CURL_BIN="$tmp/curl-hang" sh "$TOOL" view WEB-1 >/dev/null 2>&1 &
hp=$!; sleep 0.5
check "temp config exists while curl runs" bash -c 'ls "${TMPDIR:-/tmp}"/jira.?????? >/dev/null 2>&1'
kill -TERM "$hp" 2>/dev/null; wait "$hp" 2>/dev/null
pkill -f "$tmp/curl-hang" 2>/dev/null; sleep 0.2
check "temp config removed after TERM" bash -c '! ls "${TMPDIR:-/tmp}"/jira.?????? >/dev/null 2>&1'

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
