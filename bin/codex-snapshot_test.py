#!/usr/bin/env python3
"""Tests for bin/codex-snapshot. Run: bash bin/codex-snapshot.test.sh

The helper works on the repository of its working directory and hands git's output straight
through, so the tests start it as a subprocess inside throwaway repositories.
"""
import glob
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from testlib import script_launcher  # noqa: E402
TOOL = os.path.join(HERE, "codex-snapshot")

USAGE = "usage: codex-snapshot save\n       codex-snapshot diff <id>\n       codex-snapshot patch <id>\n"
GIT_ENV = {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}  # the user's git config stays out


def write(path, text, mode="w"):
    with open(path, mode) as f:
        f.write(text)


class CodexSnapshot(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.t = os.path.realpath(self.tmp.name)
        self.repo = os.path.join(self.t, "repo")
        self.env = {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")}
        self.env.update(GIT_ENV)
        subprocess.run(["git", "init", "-q", "-b", "main", self.repo], check=True, env=self.env)
        write(f"{self.repo}/a.txt", "one\n")
        write(f"{self.repo}/.gitignore", "build/\n")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "init")

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args, repo=None):
        """Run git in the test repository and return its stdout."""
        cmd = ["git", "-C", repo or self.repo, "-c", "user.name=t", "-c", "user.email=t@t"] + list(args)
        return subprocess.run(cmd, check=True, env=self.env, stdout=subprocess.PIPE, text=True).stdout

    def run_tool(self, *args, cwd=None, env=None):
        """Start the helper in the repository; (exit code, stdout, stderr)."""
        p = subprocess.run([sys.executable, TOOL] + list(args), cwd=cwd or self.repo, env=dict(self.env, **(env or {})),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
        return p.returncode, p.stdout, p.stderr

    def dirty_and_save(self):
        """A pre-existing edit and an untracked file, then a snapshot; returns its id."""
        write(f"{self.repo}/a.txt", "pre-existing edit\n", "a")
        write(f"{self.repo}/u.txt", "untracked before\n")
        rc, out, err = self.run_tool("save")
        self.assertEqual((rc, err), (0, ""))
        return out.strip()

    def codex_changes(self):
        """What a Codex run leaves behind: a new file, an edit, a deletion, ignored output."""
        write(f"{self.repo}/new.txt", "codex wrote this\n")
        write(f"{self.repo}/u.txt", "codex edited this\n", "a")
        os.remove(f"{self.repo}/.gitignore")
        os.makedirs(f"{self.repo}/build")
        write(f"{self.repo}/build/out.txt", "ignored output\n")

    def leftovers(self, directory):
        return glob.glob(os.path.join(directory, "codex-snapshot-*"))

    def test_outside_a_repo(self):
        rc, out, err = self.run_tool("save", cwd=self.t)
        self.assertEqual(rc, 1)
        self.assertIn("not inside a git repository", err)
        self.assertEqual((out, err), ("", "codex-snapshot: not inside a git repository.\n"))

    def test_usage_errors(self):
        rc, out, err = self.run_tool()
        self.assertEqual(rc, 64)
        self.assertIn("usage", err)
        self.assertEqual((out, err), ("", USAGE))
        self.assertEqual(self.run_tool("diff"), (64, "", USAGE))
        self.assertEqual(self.run_tool("patch"), (64, "", USAGE))
        self.assertEqual(self.run_tool("frobnicate"), (64, "", USAGE))

    def test_diff_with_a_bad_id(self):
        rc, out, err = self.run_tool("diff", "nonsense")
        self.assertEqual(rc, 1)
        self.assertIn("bad id", err)
        self.assertEqual((out, err), ("", "codex-snapshot: bad id 'nonsense' (expected <head>:<tree>).\n"))

    def test_save_prints_head_and_tree_and_leaves_index_and_worktree_untouched(self):
        write(f"{self.repo}/a.txt", "pre-existing edit\n", "a")
        write(f"{self.repo}/u.txt", "untracked before\n")
        write(f"{self.repo}/staged.txt", "staged before\n")
        self.git("add", "staged.txt")
        before_status = self.git("status", "--porcelain")
        with open(f"{self.repo}/.git/index", "rb") as f:
            before_index = f.read()
        rc, out, err = self.run_tool("save")
        head = self.git("rev-parse", "HEAD").strip()
        self.assertEqual(rc, 0)
        self.assertIn(f"{head}:", out)
        self.assertRegex(out, rf"\A{head}:[0-9a-f]{{40}}\n\Z")
        self.assertEqual(err, "")
        self.assertEqual(self.git("status", "--porcelain"), before_status)
        with open(f"{self.repo}/.git/index", "rb") as f:
            self.assertEqual(f.read(), before_index)

    def test_unchanged_tree_gives_an_empty_diff(self):
        snapshot = self.dirty_and_save()
        self.assertEqual(self.run_tool("diff", snapshot), (0, "", ""))

    def test_changes_after_the_snapshot_show_up_and_earlier_dirt_does_not(self):
        snapshot = self.dirty_and_save()
        self.codex_changes()
        rc, out, _ = self.run_tool("diff", snapshot)
        self.assertEqual(rc, 0)
        self.assertIn("A\tnew.txt", out)
        self.assertIn("M\tu.txt", out)
        self.assertIn("D\t.gitignore", out)
        self.assertNotIn("a.txt", out)
        self.assertNotIn("commits since", out)

    def test_patch_shows_content(self):
        snapshot = self.dirty_and_save()
        self.codex_changes()
        rc, out, _ = self.run_tool("patch", snapshot)
        self.assertEqual(rc, 0)
        self.assertIn("+codex wrote this", out)

    def test_commit_after_the_snapshot_is_reported_below_the_tree_diff(self):
        snapshot = self.dirty_and_save()
        self.codex_changes()
        self.git("add", "new.txt")
        self.git("commit", "-q", "-m", "codex commit")
        rc, out, err = self.run_tool("diff", snapshot)
        self.assertEqual(rc, 0)
        self.assertIn("codex commit", out)
        self.assertIn("A\tnew.txt", out)
        short = self.git("log", "--oneline", "-1").strip()
        self.assertTrue(out.endswith(f"A\tnew.txt\nM\tu.txt\ncommits since snapshot:\n{short}\n"), out)
        self.assertEqual(err, "")

    def test_repo_without_any_commit(self):
        empty = os.path.join(self.t, "empty")
        subprocess.run(["git", "init", "-q", "-b", "main", empty], check=True, env=self.env)
        write(f"{empty}/x.txt", "x\n")
        rc, snapshot, _ = self.run_tool("save", cwd=empty)
        self.assertEqual(rc, 0)
        self.assertIn("none:", snapshot)
        write(f"{empty}/y.txt", "y\n")
        rc, out, _ = self.run_tool("diff", snapshot.strip(), cwd=empty)
        self.assertEqual(rc, 0)
        self.assertIn("A\ty.txt", out)
        self.git("add", "-A", repo=empty)
        self.git("commit", "-q", "-m", "first commit", repo=empty)
        rc, out, _ = self.run_tool("diff", snapshot.strip(), cwd=empty)
        short = self.git("log", "--oneline", "-1", repo=empty).strip()
        self.assertEqual((rc, out), (0, f"A\ty.txt\ncommits since snapshot:\n{short}\n"))

    def test_unusable_tmpdir(self):
        rc, out, err = self.run_tool("save", env={"TMPDIR": "/nonexistent"})
        self.assertEqual((rc, out), (1, ""))
        self.assertIn("codex-snapshot:", err)
        self.assertEqual(err, "codex-snapshot: cannot create a temporary directory under /nonexistent.\n")

    def test_no_temp_directory_left_behind_on_success_or_when_a_git_step_fails(self):
        snapdir = os.path.join(self.t, "snaptmp")
        os.makedirs(snapdir)
        rc, out, _ = self.run_tool("save", env={"TMPDIR": snapdir})
        self.assertEqual(rc, 0)
        self.assertIn(self.git("rev-parse", "HEAD").strip() + ":", out)
        self.assertEqual(self.leftovers(snapdir), [])
        if os.geteuid() == 0:
            self.skipTest("root reads a file without read permission, so git add cannot be made to fail")
        write(f"{self.repo}/unreadable.txt", "secret\n")
        os.chmod(f"{self.repo}/unreadable.txt", 0)
        try:
            rc, out, err = self.run_tool("save", env={"TMPDIR": snapdir})
        finally:
            os.chmod(f"{self.repo}/unreadable.txt", 0o644)
        self.assertEqual((rc, out), (1, ""))
        self.assertTrue(err.endswith("codex-snapshot: git add -A into the temporary index failed.\n"), err)
        self.assertEqual(self.leftovers(snapdir), [])

    def test_tree_id_that_is_not_40_hex_chars(self):
        head = self.git("rev-parse", "HEAD").strip()
        for tree in ("HEAD", "abc123"):
            rc, out, err = self.run_tool("diff", f"{head}:{tree}")
            self.assertEqual(rc, 1)
            self.assertIn("bad id", err)
            self.assertEqual((out, err), ("", f"codex-snapshot: bad id '{head}:{tree}' "
                                              "(tree part must be a 40-char hex id).\n"))

    def test_tree_that_is_not_in_the_repository(self):
        missing = "0123456789" * 4
        self.assertEqual(self.run_tool("patch", f"none:{missing}"),
                         (1, "", f"codex-snapshot: snapshot tree '{missing}' not found in this repository.\n"))

    def test_head_that_is_not_in_the_repository_is_reported_as_moved(self):
        snapshot = self.dirty_and_save()
        head, tree = snapshot.split(":")
        self.assertEqual(self.run_tool("diff", f"deadbeef:{tree}"),
                         (0, f"commits since snapshot: HEAD moved from deadbeef to {head}\n", ""))

    def test_signal_ends_with_exit_1_and_removes_the_temp_directory(self):
        # A git that hangs in `add`, so the signal arrives while the temporary index exists.
        fakebin, snapdir, marker = (os.path.join(self.t, name) for name in ("fakebin", "snaptmp", "git-add-started"))
        os.makedirs(fakebin)
        os.makedirs(snapdir)
        write(f"{fakebin}/git", f'#!/bin/sh\nif [ "$1" = "add" ]; then : > "{marker}"; exec sleep 30; fi\nexit 0\n')
        os.chmod(f"{fakebin}/git", 0o755)
        env = dict(self.env, PATH=fakebin + os.pathsep + self.env["PATH"], TMPDIR=snapdir)
        for name in ("SIGTERM", "SIGINT", "SIGHUP"):
            with self.subTest(signal=name):
                p = subprocess.Popen([sys.executable, TOOL, "save"], cwd=self.repo, env=env,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                try:
                    deadline = time.time() + 30
                    while not os.path.exists(marker) and time.time() < deadline:
                        time.sleep(0.02)
                    self.assertTrue(os.path.exists(marker), "git add never started")
                    self.assertEqual(len(self.leftovers(snapdir)), 1)
                    p.send_signal(getattr(signal, name))
                    out, err = p.communicate(timeout=20)
                finally:
                    if p.poll() is None:
                        p.kill()
                        p.communicate()
                self.assertEqual((p.returncode, out, err), (1, "", ""))
                self.assertEqual(self.leftovers(snapdir), [])
                os.remove(marker)

    def test_runs_by_its_shebang(self):
        self.assertTrue(os.access(TOOL, os.X_OK))
        with open(TOOL) as f:
            self.assertEqual(f.readline(), "#!/bin/sh\n")
        p = subprocess.run(script_launcher() + [TOOL, "save"], cwd=self.repo, env=self.env, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True, timeout=60)
        self.assertEqual(p.returncode, 0)
        self.assertRegex(p.stdout, r"\A[0-9a-f]{40}:[0-9a-f]{40}\n\Z")


if __name__ == "__main__":
    unittest.main()
