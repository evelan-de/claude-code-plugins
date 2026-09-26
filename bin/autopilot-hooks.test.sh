#!/usr/bin/env bash
# Tests for bin/autopilot-hooks (Python). Run: bash bin/autopilot-hooks.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
python3 autopilot-hooks_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (autopilot-hooks_test.py)" || echo "FAIL (autopilot-hooks_test.py, exit $rc)"
exit "$rc"
