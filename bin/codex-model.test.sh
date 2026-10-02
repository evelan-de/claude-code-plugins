#!/usr/bin/env bash
# Tests for bin/codex-model (Python). Run: bash bin/codex-model.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
python3 codex-model_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (codex-model_test.py)" || echo "FAIL (codex-model_test.py, exit $rc)"
exit "$rc"
