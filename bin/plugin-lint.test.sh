#!/usr/bin/env bash
# Tests for bin/plugin-lint (Python). Run: bash bin/plugin-lint.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
PY=python3; python3 -c pass >/dev/null 2>&1 || PY=python
"$PY" plugin-lint_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (plugin-lint_test.py)" || echo "FAIL (plugin-lint_test.py, exit $rc)"
exit "$rc"
