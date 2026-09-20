#!/usr/bin/env bash
# Tests for bin/codex-image-copy. Run: bash bin/codex-image-copy.test.sh
set -uo pipefail

TOOL="$(cd "$(dirname "$0")" && pwd)/codex-image-copy"
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

images="$tmp/images"

# 1. usage error without a destination
out="$(CODEX_IMAGES_DIR="$images" sh "$TOOL" 2>&1)"; got=$?
check "no destination -> exit 64" 64 "usage" "$got" "$out"

# 2. missing images directory -> exit 1
out="$(CODEX_IMAGES_DIR="$images" sh "$TOOL" "$tmp/out/a.png" 2>&1)"; got=$?
check "missing images dir -> exit 1" 1 "no generated images directory" "$got" "$out"

# 3. no session directory -> exit 1
mkdir -p "$images"
printf 'sample\n' > "$images/sample.png"
out="$(CODEX_IMAGES_DIR="$images" sh "$TOOL" "$tmp/out/a.png" 2>&1)"; got=$?
check "no session dir -> exit 1" 1 "no session directory" "$got" "$out"

# 4. newest session wins, ig_* preferred, destination folder created
mkdir -p "$images/old-session" "$images/new-session"
printf 'old\n' > "$images/old-session/ig_old.png"
touch -t 202001010000 "$images/old-session/ig_old.png" "$images/old-session"
printf 'sample-in-session\n' > "$images/new-session/sample.png"
printf 'the-one\n' > "$images/new-session/ig_new.png"
touch -t 202101010000 "$images/new-session/sample.png"
touch -t 202201010000 "$images/new-session/ig_new.png" "$images/new-session"
out="$(CODEX_IMAGES_DIR="$images" sh "$TOOL" "$tmp/out/a.png" 2>&1)"; got=$?
check "copies newest ig_ image of newest session" 0 "ig_new.png" "$got" "$out"
if [ "$(cat "$tmp/out/a.png")" = "the-one" ]; then
  echo "ok   - destination holds the right content"; PASS=$((PASS+1))
else
  echo "FAIL - destination content: $(cat "$tmp/out/a.png" 2>&1)"; FAIL=$((FAIL+1))
fi

# 5. falls back to any png when the session has no ig_* file
mkdir -p "$images/newest-session"
printf 'plain\n' > "$images/newest-session/render.png"
touch -t 202301010000 "$images/newest-session/render.png" "$images/newest-session"
out="$(CODEX_IMAGES_DIR="$images" sh "$TOOL" "$tmp/out/b.png" 2>&1)"; got=$?
check "falls back to any png in the newest session" 0 "render.png" "$got" "$out"

# 6. newest session without any png -> exit 1, never an older session's file
mkdir -p "$images/empty-session"
touch -t 202401010000 "$images/empty-session"
out="$(CODEX_IMAGES_DIR="$images" sh "$TOOL" "$tmp/out/c.png" 2>&1)"; got=$?
check "empty newest session -> exit 1" 1 "no png in newest session" "$got" "$out"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
