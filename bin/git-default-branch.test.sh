#!/usr/bin/env bash
# Tests for bin/git-default-branch (Python). Run: bash bin/git-default-branch.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
PY=python3; python3 -c pass >/dev/null 2>&1 || PY=python
"$PY" git-default-branch_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (git-default-branch_test.py)" || echo "FAIL (git-default-branch_test.py, exit $rc)"
exit "$rc"
