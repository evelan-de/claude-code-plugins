#!/usr/bin/env bash
# Tests for bin/codex-model. Run: bash bin/codex-model.test.sh
set -uo pipefail

BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVER="$BIN_DIR/codex-model"
PASS=0; FAIL=0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/appbin" "$tmp/emptyhome"

# A fake `codex` that answers `debug models` with a catalog and nothing else.
# $1 target file, $2 comma-separated slugs
fake_codex() {
  target="$1"; slugs="$2"
  cat > "$target" <<EOF
#!/bin/sh
if [ "\$1" = "debug" ] && [ "\$2" = "models" ]; then
  json='{"models":['
  first=1
  for s in $(echo "$slugs" | tr ',' ' '); do
    [ \$first -eq 1 ] || json="\$json,"
    first=0
    json="\$json{\"slug\":\"\$s\",\"display_name\":\"\$s\"}"
  done
  json="\$json]}"
  printf '%s\n' "\$json"
  exit 0
fi
echo "fake codex: unexpected args: \$*" >&2
exit 1
EOF
  chmod +x "$target"
}

# Run the resolver with a controlled environment: no `codex` on PATH, the app
# bin pointed at our fake, so bin/codex-cli resolves to the fake.
run() { # $@ resolver args -> sets OUT / GOT
  OUT="$(PATH="/usr/bin:/bin" HOME="$tmp/emptyhome" \
    CODEX_CLI_APP_BIN="$tmp/appbin/codex" sh "$RESOLVER" "$@" 2>&1)"
  GOT=$?
}

check() { # $1 desc  $2 want_exit  $3 want_substring
  if [ "$GOT" -eq "$2" ] && printf '%s' "$OUT" | grep -qF "$3"; then
    echo "ok   - $1 (exit $GOT)"; PASS=$((PASS+1))
  else
    echo "FAIL - $1 (want exit $2 + '$3'; got exit $GOT, output: $OUT)"; FAIL=$((FAIL+1))
  fi
}

CATALOG="gpt-5.6-sol,gpt-5.6-terra,gpt-5.6-luna,gpt-5.5,gpt-5.4-mini,codex-auto-review"
fake_codex "$tmp/appbin/codex" "$CATALOG"

# 1. list prints the selectable slugs
run list
check "list prints catalog slugs" 0 "gpt-5.6-luna"

# 2. internal models are not offered
if [ "$GOT" -eq 0 ] && ! printf '%s' "$OUT" | grep -qF "codex-auto-review"; then
  echo "ok   - list hides internal slugs (exit $GOT)"; PASS=$((PASS+1))
else
  echo "FAIL - list hides internal slugs (got: $OUT)"; FAIL=$((FAIL+1))
fi

# 3. friendly name resolves to the full slug
run resolve luna
check "resolve luna -> gpt-5.6-luna" 0 "gpt-5.6-luna"

# 4. resolution is case-insensitive (dictated names arrive capitalised)
run resolve Luna
check "resolve is case-insensitive" 0 "gpt-5.6-luna"

# 5. an exact slug passes through untouched
run resolve gpt-5.6-sol
check "exact slug passes through" 0 "gpt-5.6-sol"

# 6. a version-only name resolves via the same suffix rule
run resolve 5.5
check "resolve 5.5 -> gpt-5.5" 0 "gpt-5.5"

# 7. unknown name fails early and shows what IS available
run resolve nonsense
check "unknown name -> exit 2" 2 "nonsense"
run resolve nonsense
check "unknown name lists alternatives" 2 "gpt-5.6-sol"

# 8. internal slugs are not resolvable either
run resolve codex-auto-review
check "internal slug is not selectable" 2 "codex-auto-review"

# 9. an ambiguous short name is reported, never guessed
fake_codex "$tmp/appbin/codex" "gpt-5.6-luna,gpt-5.7-luna"
run resolve luna
check "ambiguous name -> exit 3" 3 "ambiguous"

# 10. unreadable catalog must not block a plausible slug (best-effort validation)
cat > "$tmp/appbin/codex" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$tmp/appbin/codex"
run resolve gpt-5.6-luna
check "catalog unavailable -> pass through" 0 "gpt-5.6-luna"
run resolve gpt-5.6-luna
check "catalog unavailable -> warns on stderr" 0 "could not read"

# 11. usage error when no name is given
fake_codex "$tmp/appbin/codex" "$CATALOG"
run resolve
check "missing argument -> exit 64" 64 "usage"

# 12. unknown subcommand is a usage error, not a silent no-op
run frobnicate
check "unknown subcommand -> exit 64" 64 "usage"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
