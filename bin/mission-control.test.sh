#!/usr/bin/env bash
# Tests for bin/mission-control (Python). Run: bash bin/mission-control.test.sh
# MC_TEST_VERBOSE=1 prints one line per check.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
python3 mission-control_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (mission-control_test.py)" || echo "FAIL (mission-control_test.py, exit $rc)"
exit "$rc"
