#!/usr/bin/env bash
# Tests for bin/codex-snapshot (Python). Run: bash bin/codex-snapshot.test.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 2
python3 codex-snapshot_test.py 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS (codex-snapshot_test.py)" || echo "FAIL (codex-snapshot_test.py, exit $rc)"
exit "$rc"
