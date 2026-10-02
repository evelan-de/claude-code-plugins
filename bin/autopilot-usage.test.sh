#!/usr/bin/env bash
# Tests for bin/autopilot-usage (Python). Run: bash bin/autopilot-usage.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
python3 autopilot-usage_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (autopilot-usage_test.py)" || echo "FAIL (autopilot-usage_test.py, exit $rc)"
exit "$rc"
