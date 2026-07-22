#!/usr/bin/env bash
# Tests for bin/codex-cli. Run: bash bin/codex-cli.test.sh
set -uo pipefail

WRAPPER="$(cd "$(dirname "$0")" && pwd)/codex-cli"
PASS=0; FAIL=0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/pathbin" "$tmp/appbin" "$tmp/home/.local/bin" "$tmp/emptyhome"

fake() { # $1 target file  $2 marker
  cat > "$1" <<EOF
#!/bin/sh
echo "$2"
for a in "\$@"; do echo "arg:\$a"; done
EOF
  chmod +x "$1"
}

check() { # $1 desc  $2 want_exit  $3 want_substring  $4 got_exit  $5 got_output
  if [ "$4" -eq "$2" ] && printf '%s' "$5" | grep -qF "$3"; then
    echo "ok   - $1 (exit $4)"; PASS=$((PASS+1))
  else
    echo "FAIL - $1 (want exit $2 + '$3'; got exit $4, output: $5)"; FAIL=$((FAIL+1))
  fi
}

fake "$tmp/pathbin/codex" "FROM_PATH"
fake "$tmp/appbin/codex" "FROM_APP"
fake "$tmp/home/.local/bin/codex" "FROM_HOME"

# 1. PATH wins over app bin and HOME fallback
out="$(PATH="$tmp/pathbin:/usr/bin:/bin" HOME="$tmp/home" \
  CODEX_CLI_APP_BIN="$tmp/appbin/codex" sh "$WRAPPER" exec hello 2>&1)"; got=$?
check "codex on PATH wins" 0 "FROM_PATH" "$got" "$out"

# 2. App bin wins when PATH has no codex
out="$(PATH="/usr/bin:/bin" HOME="$tmp/home" \
  CODEX_CLI_APP_BIN="$tmp/appbin/codex" sh "$WRAPPER" exec hello 2>&1)"; got=$?
check "app bin is second" 0 "FROM_APP" "$got" "$out"

# 3. ~/.local/bin/codex is the last fallback
out="$(PATH="/usr/bin:/bin" HOME="$tmp/home" \
  CODEX_CLI_APP_BIN="$tmp/nonexistent" sh "$WRAPPER" exec hello 2>&1)"; got=$?
check "HOME local bin is third" 0 "FROM_HOME" "$got" "$out"

# 4. Arguments with spaces are forwarded verbatim as single args
out="$(PATH="$tmp/pathbin:/usr/bin:/bin" HOME="$tmp/emptyhome" \
  CODEX_CLI_APP_BIN="$tmp/nonexistent" sh "$WRAPPER" review --base main "two words" 2>&1)"; got=$?
check "args forwarded verbatim" 0 "arg:two words" "$got" "$out"

# 5. Nothing resolvable -> exit 127 + clear message
out="$(PATH="/usr/bin:/bin" HOME="$tmp/emptyhome" \
  CODEX_CLI_APP_BIN="$tmp/nonexistent" sh "$WRAPPER" --version 2>&1)"; got=$?
check "not found -> exit 127 + message" 127 "Codex CLI not found" "$got" "$out"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
