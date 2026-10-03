#!/usr/bin/env bash
# Tests for bin/jira (Python). Run: bash bin/jira.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
PY=python3; python3 -c pass >/dev/null 2>&1 || PY=python
"$PY" jira_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (jira_test.py)" || echo "FAIL (jira_test.py, exit $rc)"
exit "$rc"
