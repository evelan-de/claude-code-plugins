#!/usr/bin/env bash
# Tests for bin/autopilot-watchdog (Python). Run: bash bin/autopilot-watchdog.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
PY=python3; python3 -c pass >/dev/null 2>&1 || PY=python
"$PY" autopilot-watchdog_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (autopilot-watchdog_test.py)" || echo "FAIL (autopilot-watchdog_test.py, exit $rc)"
exit "$rc"
