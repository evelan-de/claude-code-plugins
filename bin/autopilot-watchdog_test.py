#!/usr/bin/env python3
"""Tests for bin/autopilot-watchdog. Run: bash bin/autopilot-watchdog.test.sh"""
import contextlib
import importlib.machinery
import importlib.util
import io
import os
import re
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "autopilot-watchdog")
loader = importlib.machinery.SourceFileLoader("autopilot_watchdog", TOOL)
spec = importlib.util.spec_from_loader("autopilot_watchdog", loader)
watchdog = importlib.util.module_from_spec(spec)
loader.exec_module(watchdog)

FUTURE = 1893456000  # 2030-01-01T00:00:00Z


def git(repo, *args):
    subprocess.run(["git", "-C", repo, "-c", "user.email=t@t", "-c", "user.name=t", *args],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def new_repo(path):
    """A repo with one commit, checked out on feat/x."""
    os.makedirs(path)
    git(path, "init", "-q")
    git(path, "commit", "-q", "--allow-empty", "-m", "init")
    git(path, "checkout", "-q", "-b", "feat/x")
    return path


class AutopilotWatchdog(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = new_repo(os.path.join(self.tmp.name, "repo"))
        self.state = os.path.join(self.tmp.name, "state")
        self.plan = os.path.join(self.repo, "docs", "autopilot", "sessions", "2026-09-19-x", "PLAN.md")
        os.makedirs(os.path.dirname(self.plan))
        with open(self.plan, "w") as f:
            f.write("# plan\n")

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = watchdog.main(list(argv))
        return rc, out.getvalue(), err.getvalue()

    def tick(self, *extra):
        """One tick on feat/x with the test's state file: the output line."""
        rc, out, _ = self.run_cli(self.repo, "feat/x", self.state, *extra)
        self.assertEqual(rc, 0)
        return out

    def test_first_tick_is_progress_then_stalls_are_counted(self):
        self.assertRegex(self.tick(), r"^PROGRESS .*stalls=0\n$")
        self.assertRegex(self.tick(), r"^STALL .*stalls=1\n$")
        self.assertRegex(self.tick(), r"^STALL .*stalls=2\n$")

    def test_output_line_format(self):
        sha = subprocess.run(["git", "-C", self.repo, "rev-parse", "--short", "feat/x"], stdout=subprocess.PIPE,
                             universal_newlines=True).stdout.strip()
        self.assertRegex(self.tick(), rf"^PROGRESS commit={sha} age=\d+ plan_age=\d+ status_age=-1 stalls=0\n$")

    def test_new_commit_resets_to_progress(self):
        self.tick()
        self.tick()
        git(self.repo, "commit", "-q", "--allow-empty", "-m", "wp1")
        self.assertRegex(self.tick(), r"^PROGRESS .*stalls=0\n$")

    def test_plan_mtime_change_counts_as_progress(self):
        self.tick()
        os.utime(self.plan, (FUTURE, FUTURE))
        self.assertRegex(self.tick(), r"^PROGRESS ")
        self.assertRegex(self.tick(), r"^STALL .*stalls=1\n$")

    def test_no_status_file_reports_status_age_minus_1(self):
        self.tick()
        self.assertRegex(self.tick(), r"^STALL .*status_age=-1 ")

    def test_status_file_at_the_default_path_counts_as_progress(self):
        self.tick()
        status = os.path.join(self.repo, ".claude", ".autopilot-status")
        os.makedirs(os.path.dirname(status))
        with open(status, "w") as f:
            f.write("2026-09-21T10:00:00Z ctx=1000 tool=Bash\n")
        os.utime(status, (FUTURE + 60, FUTURE + 60))
        self.assertRegex(self.tick(), r"^PROGRESS ")
        self.assertRegex(self.tick(), r"^STALL .*stalls=1\n$")

    def test_explicit_status_file_argument_is_honoured(self):
        self.tick()
        self.assertRegex(self.tick(), r"^STALL ")
        other = os.path.join(self.repo, "other-status")
        with open(other, "w"):
            pass
        os.utime(other, (FUTURE + 120, FUTURE + 120))
        self.assertRegex(self.tick(other), r"^PROGRESS ")

    def test_missing_branch_reports_commit_none(self):
        rc, out, _ = self.run_cli(self.repo, "nobranch", self.state + ".2")
        self.assertEqual(rc, 0)
        self.assertRegex(out, r"^PROGRESS commit=none age=-1 ")

    def test_usage_error_exits_2(self):
        for argv in ([], [self.repo], ["", "feat/x"]):
            rc, out, err = self.run_cli(*argv)
            self.assertEqual((rc, out), (2, ""))
            self.assertEqual(err, "usage: autopilot-watchdog <repo-dir> <branch> [state-file] [status-file]\n")

    def test_default_state_file_is_keyed_per_repo(self):
        repo2 = new_repo(os.path.join(self.tmp.name, "repo2"))
        tmpdir = os.path.join(self.tmp.name, "tmp")
        os.makedirs(tmpdir)
        with mock.patch.dict(os.environ, {"TMPDIR": tmpdir}):
            self.assertRegex(self.run_cli(self.repo, "feat/x")[1], r"^PROGRESS ")
            self.assertRegex(self.run_cli(repo2, "feat/x")[1], r"^PROGRESS ")
            self.assertRegex(self.run_cli(self.repo, "feat/x")[1], r"^STALL .*stalls=1\n$")
        names = sorted(os.listdir(tmpdir))
        self.assertEqual(len(names), 2)
        for name in names:
            self.assertRegex(name, r"^autopilot-watchdog-\d+-feat_x\.state$")

    def test_state_file_format(self):
        self.tick()
        sha = subprocess.run(["git", "-C", self.repo, "rev-parse", "--short", "feat/x"], stdout=subprocess.PIPE,
                             universal_newlines=True).stdout.strip()
        plan_ts = int(os.stat(self.plan).st_mtime)
        with open(self.state) as f:
            self.assertEqual(f.read(), f"prev_commit={sha}\nprev_plan={plan_ts}\nprev_status=0\nstalls=0\n")

    def test_existing_state_file_is_continued(self):
        sha = subprocess.run(["git", "-C", self.repo, "rev-parse", "--short", "feat/x"], stdout=subprocess.PIPE,
                             universal_newlines=True).stdout.strip()
        with open(self.state, "w") as f:
            f.write(f"prev_commit={sha}\nprev_plan={FUTURE}\nprev_status=0\nstalls=3\n")
        self.assertRegex(self.tick(), r"^STALL .*stalls=4\n$")

    def test_state_file_is_parsed_not_executed(self):
        marker = os.path.join(self.tmp.name, "executed")
        with open(self.state, "w") as f:
            f.write(f"touch '{marker}'\nprev_commit=$(touch '{marker}')\nstalls=`touch '{marker}'`\nprev_plan=abc\n")
        self.assertRegex(self.tick(), r"^PROGRESS .*stalls=0\n$")
        self.assertFalse(os.path.exists(marker))

    def test_unwritable_state_file_still_prints_the_verdict(self):
        rc, out, err = self.run_cli(self.repo, "feat/x", os.path.join(self.tmp.name, "missing", "state"))
        self.assertEqual(rc, 0)
        self.assertRegex(out, r"^PROGRESS .*stalls=0\n$")
        self.assertIn("autopilot-watchdog: cannot write", err)

    def test_runs_as_an_executable(self):
        self.assertTrue(os.access(TOOL, os.X_OK))
        with open(TOOL, encoding="utf-8") as f:
            self.assertEqual(f.readline(), "#!/usr/bin/env python3\n")
        p = subprocess.run([TOOL, self.repo, "feat/x", self.state], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        self.assertEqual((p.returncode, p.stderr), (0, ""))
        self.assertTrue(re.match(r"^PROGRESS commit=[0-9a-f]+ age=\d+ plan_age=\d+ status_age=-1 stalls=0\n$", p.stdout))
        self.assertEqual(subprocess.run([sys.executable, TOOL], stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL).returncode, 2)


if __name__ == "__main__":
    unittest.main()
