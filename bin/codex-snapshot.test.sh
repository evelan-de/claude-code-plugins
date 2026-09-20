#!/usr/bin/env bash
# Tests for bin/codex-snapshot. Run: bash bin/codex-snapshot.test.sh
set -uo pipefail

TOOL="$(cd "$(dirname "$0")" && pwd)/codex-snapshot"
PASS=0; FAIL=0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check() { # $1 desc  $2 want_exit  $3 want_substring  $4 got_exit  $5 got_output
  if [ "$4" -eq "$2" ] && printf '%s' "$5" | grep -qF "$3"; then
    echo "ok   - $1 (exit $4)"; PASS=$((PASS+1))
  else
    echo "FAIL - $1 (want exit $2 + '$3'; got exit $4, output: $5)"; FAIL=$((FAIL+1))
  fi
}

absent() { # $1 desc  $2 unwanted_substring  $3 output
  if printf '%s' "$3" | grep -qF "$2"; then
    echo "FAIL - $1 (did not expect '$2' in: $3)"; FAIL=$((FAIL+1))
  else
    echo "ok   - $1"; PASS=$((PASS+1))
  fi
}

repo="$tmp/repo"
git init -q -b main "$repo"
gitc() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
printf 'one\n' > "$repo/a.txt"
printf 'ignored\n' > "$repo/.gitignore"
printf 'build/\n' > "$repo/.gitignore"
gitc add -A
gitc commit -q -m init

# 1. outside a repo -> exit 1
out="$(cd "$tmp" && sh "$TOOL" save 2>&1)"; got=$?
check "outside a repo -> exit 1" 1 "not inside a git repository" "$got" "$out"

# 2. usage errors
out="$(cd "$repo" && sh "$TOOL" 2>&1)"; got=$?
check "no subcommand -> exit 64" 64 "usage" "$got" "$out"
out="$(cd "$repo" && sh "$TOOL" diff 2>&1)"; got=$?
check "diff without id -> exit 64" 64 "usage" "$got" "$out"
out="$(cd "$repo" && sh "$TOOL" diff nonsense 2>&1)"; got=$?
check "diff with a bad id -> exit 1" 1 "bad id" "$got" "$out"

# 3. save prints <head>:<tree> and leaves index and worktree untouched
printf 'pre-existing edit\n' >> "$repo/a.txt"
printf 'untracked before\n' > "$repo/u.txt"
before_status="$(gitc status --porcelain)"
id="$(cd "$repo" && sh "$TOOL" save 2>&1)"; got=$?
head="$(gitc rev-parse HEAD)"
check "save prints the HEAD sha" 0 "$head:" "$got" "$id"
after_status="$(gitc status --porcelain)"
if [ "$before_status" = "$after_status" ]; then
  echo "ok   - save leaves git status unchanged"; PASS=$((PASS+1))
else
  echo "FAIL - save changed git status: $after_status"; FAIL=$((FAIL+1))
fi

# 4. no change -> empty diff, no commits line
out="$(cd "$repo" && sh "$TOOL" diff "$id" 2>&1)"; got=$?
if [ "$got" -eq 0 ] && [ -z "$out" ]; then
  echo "ok   - unchanged tree -> empty diff"; PASS=$((PASS+1))
else
  echo "FAIL - unchanged tree -> empty diff (exit $got, output: $out)"; FAIL=$((FAIL+1))
fi

# 5. changes after the snapshot show up; pre-existing dirt does not
printf 'codex wrote this\n' > "$repo/new.txt"
printf 'codex edited this\n' >> "$repo/u.txt"
rm "$repo/.gitignore"
mkdir -p "$repo/build"
printf 'ignored output\n' > "$repo/build/out.txt"
out="$(cd "$repo" && sh "$TOOL" diff "$id" 2>&1)"; got=$?
check "new untracked file is listed" 0 "A	new.txt" "$got" "$out"
check "edit to a pre-existing untracked file is listed" 0 "M	u.txt" "$got" "$out"
check "deletion is listed" 0 "D	.gitignore" "$got" "$out"
absent "pre-existing edit to a.txt is not listed" "a.txt" "$out"
absent "commits line absent while HEAD unchanged" "commits since" "$out"

# 6. patch shows content
out="$(cd "$repo" && sh "$TOOL" patch "$id" 2>&1)"; got=$?
check "patch shows the added content" 0 "+codex wrote this" "$got" "$out"

# 7. a commit made after the snapshot is reported, and the diff still isolates it
gitc add new.txt
gitc commit -q -m "codex commit"
out="$(cd "$repo" && sh "$TOOL" diff "$id" 2>&1)"; got=$?
check "commit since snapshot is listed" 0 "codex commit" "$got" "$out"
check "committed file still shows in the tree diff" 0 "A	new.txt" "$got" "$out"

# 8. save works in a repository without any commit yet
empty="$tmp/empty"
git init -q -b main "$empty"
printf 'x\n' > "$empty/x.txt"
id2="$(cd "$empty" && sh "$TOOL" save 2>&1)"; got=$?
check "save in a repo without commits" 0 "none:" "$got" "$id2"
printf 'y\n' > "$empty/y.txt"
out="$(cd "$empty" && sh "$TOOL" diff "$id2" 2>&1)"; got=$?
check "diff in a repo without commits" 0 "A	y.txt" "$got" "$out"

# 9. mktemp failure -> exit 1, nothing on stdout, message on stderr
errf="$tmp/stderr.txt"
out="$(cd "$repo" && TMPDIR=/nonexistent sh "$TOOL" save 2>"$errf")"; got=$?
err="$(cat "$errf")"
if [ "$got" -eq 1 ] && [ -z "$out" ]; then
  echo "ok   - unusable TMPDIR -> exit 1 with empty stdout"; PASS=$((PASS+1))
else
  echo "FAIL - unusable TMPDIR (exit $got, stdout: $out)"; FAIL=$((FAIL+1))
fi
check "unusable TMPDIR -> message on stderr" 1 "codex-snapshot:" "$got" "$err"

# 10. save leaves no temp directory behind, on success and when a git step fails
snapdir="$tmp/snaptmp"
mkdir -p "$snapdir"
out="$(cd "$repo" && TMPDIR="$snapdir" sh "$TOOL" save 2>&1)"; got=$?
check "save with a custom TMPDIR works" 0 "$(gitc rev-parse HEAD):" "$got" "$out"
leftover="$(find "$snapdir" -maxdepth 1 -name 'codex-snapshot-*' | wc -l | tr -d ' ')"
if [ "$leftover" = "0" ]; then
  echo "ok   - no codex-snapshot-* directory left behind after save"; PASS=$((PASS+1))
else
  echo "FAIL - $leftover codex-snapshot-* directories left in $snapdir"; FAIL=$((FAIL+1))
fi
printf 'secret\n' > "$repo/unreadable.txt"
chmod 000 "$repo/unreadable.txt"
out="$(cd "$repo" && TMPDIR="$snapdir" sh "$TOOL" save 2>/dev/null)"; got=$?
chmod 644 "$repo/unreadable.txt"; rm -f "$repo/unreadable.txt"
if [ "$got" -eq 1 ] && [ -z "$out" ]; then
  echo "ok   - failing git add -> exit 1 with empty stdout"; PASS=$((PASS+1))
else
  echo "FAIL - failing git add (exit $got, stdout: $out)"; FAIL=$((FAIL+1))
fi
leftover="$(find "$snapdir" -maxdepth 1 -name 'codex-snapshot-*' | wc -l | tr -d ' ')"
if [ "$leftover" = "0" ]; then
  echo "ok   - no codex-snapshot-* directory left behind after a failed save"; PASS=$((PASS+1))
else
  echo "FAIL - $leftover codex-snapshot-* directories left after a failed save"; FAIL=$((FAIL+1))
fi

# 11. tree id that is not 40 hex chars -> exit 1
out="$(cd "$repo" && sh "$TOOL" diff "$(gitc rev-parse HEAD):HEAD" 2>&1)"; got=$?
check "non-hex tree id -> exit 1" 1 "bad id" "$got" "$out"
out="$(cd "$repo" && sh "$TOOL" diff "$(gitc rev-parse HEAD):abc123" 2>&1)"; got=$?
check "short tree id -> exit 1" 1 "bad id" "$got" "$out"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
