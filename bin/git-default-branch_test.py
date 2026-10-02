#!/usr/bin/env python3
"""Tests for bin/git-default-branch. Run: bash bin/git-default-branch.test.sh"""
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "git-default-branch")


def git(*args):
    subprocess.run(["git", *args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class GitDefaultBranch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.p = os.path.realpath(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def new_repo(self, name, branch):
        """A repo with one commit on a branch of the given name."""
        path = os.path.join(self.p, name)
        git("init", "-q", "-b", branch, path)
        git("-C", path, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
        return path

    def run_tool(self, cwd, argv=None):
        """Exit code, stdout and stderr of the tool started in cwd."""
        p = subprocess.run(argv or [sys.executable, TOOL], cwd=cwd, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, universal_newlines=True)
        return p.returncode, p.stdout, p.stderr

    def test_outside_a_repo_exits_1(self):
        rc, out, err = self.run_tool(self.p)
        self.assertEqual((rc, out), (1, ""))
        self.assertEqual(err, "git-default-branch: not inside a git repository.\n")

    def test_local_main(self):
        self.assertEqual(self.run_tool(self.new_repo("local-main", "main")), (0, "main\n", ""))

    def test_local_master(self):
        self.assertEqual(self.run_tool(self.new_repo("local-master", "master")), (0, "master\n", ""))

    def test_neither_main_nor_master_exits_1(self):
        rc, out, err = self.run_tool(self.new_repo("odd", "trunk"))
        self.assertEqual((rc, out), (1, ""))
        self.assertEqual(err, "git-default-branch: no default branch found (no origin/HEAD, main or master).\n")

    def test_origin_head_wins_over_a_local_main_and_loses_the_prefix(self):
        remote = self.new_repo("remote", "develop")
        clone = self.new_repo("clone", "main")
        git("-C", clone, "remote", "add", "origin", remote)
        git("-C", clone, "fetch", "-q", "origin")
        git("-C", clone, "remote", "set-head", "origin", "develop")
        self.assertEqual(self.run_tool(clone), (0, "develop\n", ""))

    def test_remote_tracking_main_without_origin_head(self):
        remote = self.new_repo("remote2", "main")
        clone = self.new_repo("clone2", "trunk")
        git("-C", clone, "remote", "add", "origin", remote)
        git("-C", clone, "fetch", "-q", "origin")
        self.assertEqual(self.run_tool(clone), (0, "main\n", ""))

    def test_main_wins_over_master(self):
        repo = self.new_repo("both", "master")
        git("-C", repo, "branch", "main")
        self.assertEqual(self.run_tool(repo), (0, "main\n", ""))

    def test_runs_as_an_executable(self):
        self.assertTrue(os.access(TOOL, os.X_OK))
        with open(TOOL, encoding="utf-8") as f:
            self.assertEqual(f.readline(), "#!/usr/bin/env python3\n")
        self.assertEqual(self.run_tool(self.new_repo("direct", "main"), [TOOL]), (0, "main\n", ""))


if __name__ == "__main__":
    unittest.main()
