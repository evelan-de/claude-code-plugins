#!/usr/bin/env bash
# Tests for bin/codex-image-copy (Python). Run: bash bin/codex-image-copy.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
PY=python3; python3 -c pass >/dev/null 2>&1 || PY=python
"$PY" codex-image-copy_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (codex-image-copy_test.py)" || echo "FAIL (codex-image-copy_test.py, exit $rc)"
exit "$rc"
