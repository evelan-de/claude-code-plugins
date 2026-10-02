#!/usr/bin/env bash
# Tests for bin/codex-cli (Python). Run: bash bin/codex-cli.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
python3 codex-cli_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (codex-cli_test.py)" || echo "FAIL (codex-cli_test.py, exit $rc)"
exit "$rc"
