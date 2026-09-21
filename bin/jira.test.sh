#!/usr/bin/env bash
# Tests for bin/jira (Python). Run: bash bin/jira.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
python3 jira_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (jira_test.py)" || echo "FAIL (jira_test.py, exit $rc)"
exit "$rc"
