#!/usr/bin/env bash
# Tests for bin/mission-control (Python). Run: bash bin/mission-control.test.sh
# MC_TEST_VERBOSE=1 prints one line per check.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
[ "$(uname -s)" = Darwin ] || { echo "SKIP (mission-control_test.py: the runner is macOS-only)"; exit 0; }
PY=python3; python3 -c pass >/dev/null 2>&1 || PY=python
"$PY" mission-control_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (mission-control_test.py)" || echo "FAIL (mission-control_test.py, exit $rc)"
exit "$rc"
