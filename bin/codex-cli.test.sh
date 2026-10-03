#!/usr/bin/env bash
# Tests for bin/codex-cli (Python). Run: bash bin/codex-cli.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
PY=python3; python3 -c pass >/dev/null 2>&1 || PY=python
"$PY" codex-cli_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (codex-cli_test.py)" || echo "FAIL (codex-cli_test.py, exit $rc)"
exit "$rc"
