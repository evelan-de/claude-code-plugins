#!/usr/bin/env bash
# Tests for bin/autopilot-watchdog (Python). Run: bash bin/autopilot-watchdog.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
python3 autopilot-watchdog_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (autopilot-watchdog_test.py)" || echo "FAIL (autopilot-watchdog_test.py, exit $rc)"
exit "$rc"
