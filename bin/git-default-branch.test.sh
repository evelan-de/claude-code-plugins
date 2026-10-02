#!/usr/bin/env bash
# Tests for bin/git-default-branch (Python). Run: bash bin/git-default-branch.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
python3 git-default-branch_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (git-default-branch_test.py)" || echo "FAIL (git-default-branch_test.py, exit $rc)"
exit "$rc"
