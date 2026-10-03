#!/usr/bin/env bash
# Tests for bin/autopilot-hooks (Python). Run: bash bin/autopilot-hooks.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
PY=python3; python3 -c pass >/dev/null 2>&1 || PY=python
"$PY" autopilot-hooks_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (autopilot-hooks_test.py)" || echo "FAIL (autopilot-hooks_test.py, exit $rc)"
exit "$rc"
