#!/usr/bin/env bash
# Tests for bin/git-default-branch. Run: bash bin/git-default-branch.test.sh
set -uo pipefail

TOOL="$(cd "$(dirname "$0")" && pwd)/git-default-branch"
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

# A repo with one commit on a branch of the given name.
new_repo() { # $1 dir  $2 initial branch
  git init -q -b "$2" "$1"
  git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}

# 1. outside a repo -> exit 1
out="$(cd "$tmp" && sh "$TOOL" 2>&1)"; got=$?
check "outside a repo -> exit 1" 1 "not inside a git repository" "$got" "$out"

# 2. no remote, local main -> main
new_repo "$tmp/local-main" main
out="$(cd "$tmp/local-main" && sh "$TOOL" 2>&1)"; got=$?
check "local main" 0 "main" "$got" "$out"

# 3. no remote, local master -> master
new_repo "$tmp/local-master" master
out="$(cd "$tmp/local-master" && sh "$TOOL" 2>&1)"; got=$?
check "local master" 0 "master" "$got" "$out"

# 4. neither main nor master -> exit 1
new_repo "$tmp/odd" trunk
out="$(cd "$tmp/odd" && sh "$TOOL" 2>&1)"; got=$?
check "no main/master -> exit 1" 1 "no default branch found" "$got" "$out"

# 5. origin/HEAD wins over a local main
new_repo "$tmp/remote" develop
new_repo "$tmp/clone" main
git -C "$tmp/clone" remote add origin "$tmp/remote"
git -C "$tmp/clone" fetch -q origin
git -C "$tmp/clone" remote set-head origin develop
out="$(cd "$tmp/clone" && sh "$TOOL" 2>&1)"; got=$?
check "origin/HEAD wins" 0 "develop" "$got" "$out"
if [ "$out" = "develop" ]; then
  echo "ok   - origin/HEAD printed without the origin/ prefix"; PASS=$((PASS+1))
else
  echo "FAIL - origin/HEAD printed without the origin/ prefix (got: $out)"; FAIL=$((FAIL+1))
fi

# 6. remote-tracking main without origin/HEAD -> main
new_repo "$tmp/remote2" main
new_repo "$tmp/clone2" trunk
git -C "$tmp/clone2" remote add origin "$tmp/remote2"
git -C "$tmp/clone2" fetch -q origin
out="$(cd "$tmp/clone2" && sh "$TOOL" 2>&1)"; got=$?
check "remote-tracking main" 0 "main" "$got" "$out"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
