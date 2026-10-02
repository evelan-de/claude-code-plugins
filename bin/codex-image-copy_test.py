#!/usr/bin/env python3
"""Tests for bin/codex-image-copy. Run: bash bin/codex-image-copy.test.sh"""
import contextlib
import importlib.machinery
import importlib.util
import io
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "codex-image-copy")
loader = importlib.machinery.SourceFileLoader("codex_image_copy", TOOL)
spec = importlib.util.spec_from_loader("codex_image_copy", loader)
image_copy = importlib.util.module_from_spec(spec)
loader.exec_module(image_copy)

Y2020, Y2021, Y2022, Y2023, Y2024 = 1577836800, 1609459200, 1640995200, 1672531200, 1704067200


def touch(path, when):
    os.utime(path, (when, when))


def put(path, text, when=None):
    """Write a file, creating its folder; `when` sets the modification time."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    if when is not None:
        touch(path, when)


def read(path):
    with open(path) as f:
        return f.read()


class CodexImageCopy(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.t = os.path.realpath(self.tmp.name)
        self.images = os.path.join(self.t, "images")

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *argv, images=None, env=None):
        """main() with CODEX_IMAGES_DIR pointing at the test's images folder; (exit code, stdout, stderr)."""
        out, err = io.StringIO(), io.StringIO()
        values = {"CODEX_IMAGES_DIR": images or self.images}
        values.update(env or {})
        with mock.patch.dict(os.environ, values), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = image_copy.main(list(argv))
        return rc, out.getvalue(), err.getvalue()

    def old_and_new_session(self):
        """A bundled sample in the root, an old session and a newer one with a sample and an ig_ image."""
        put(f"{self.images}/sample.png", "sample\n")
        put(f"{self.images}/old-session/ig_old.png", "old\n", Y2020)
        touch(f"{self.images}/old-session", Y2020)
        put(f"{self.images}/new-session/sample.png", "sample-in-session\n", Y2021)
        put(f"{self.images}/new-session/ig_new.png", "the-one\n", Y2022)
        touch(f"{self.images}/new-session", Y2022)

    def test_no_destination_is_a_usage_error(self):
        rc, out, err = self.run_cli()
        self.assertEqual(rc, 64)
        self.assertIn("usage", err)
        self.assertEqual((out, err), ("", "usage: codex-image-copy <destination-file>\n"))
        self.assertEqual(self.run_cli("")[0], 64)

    def test_missing_images_directory(self):
        rc, out, err = self.run_cli(f"{self.t}/out/a.png")
        self.assertEqual(rc, 1)
        self.assertIn("no generated images directory", err)
        self.assertEqual((out, err), ("", f"codex-image-copy: no generated images directory at {self.images}\n"))

    def test_no_session_directory(self):
        put(f"{self.images}/sample.png", "sample\n")
        rc, out, err = self.run_cli(f"{self.t}/out/a.png")
        self.assertEqual(rc, 1)
        self.assertIn("no session directory", err)
        self.assertEqual((out, err), ("", f"codex-image-copy: no session directory under {self.images}\n"))

    def test_copies_newest_ig_image_of_newest_session_and_creates_the_destination_folder(self):
        self.old_and_new_session()
        rc, out, err = self.run_cli(f"{self.t}/out/a.png")
        self.assertEqual(rc, 0)
        self.assertIn("ig_new.png", out)
        self.assertEqual(read(f"{self.t}/out/a.png"), "the-one\n")
        self.assertEqual((out, err), (f"copied {self.images}/new-session/ig_new.png -> {self.t}/out/a.png\n", ""))

    def test_falls_back_to_any_png_when_the_session_has_no_ig_file(self):
        self.old_and_new_session()
        put(f"{self.images}/newest-session/render.png", "plain\n", Y2023)
        touch(f"{self.images}/newest-session", Y2023)
        rc, out, _ = self.run_cli(f"{self.t}/out/b.png")
        self.assertEqual(rc, 0)
        self.assertIn("render.png", out)
        self.assertEqual(read(f"{self.t}/out/b.png"), "plain\n")

    def test_empty_newest_session_never_takes_an_older_sessions_file(self):
        self.old_and_new_session()
        os.makedirs(f"{self.images}/empty-session")
        touch(f"{self.images}/empty-session", Y2024)
        rc, out, err = self.run_cli(f"{self.t}/out/c.png")
        self.assertEqual(rc, 1)
        self.assertIn("no png in newest session", err)
        self.assertEqual((out, err), ("", f"codex-image-copy: no png in newest session {self.images}/empty-session\n"))
        self.assertFalse(os.path.exists(f"{self.t}/out/c.png"))

    def test_spaces_in_the_images_root_and_the_session_name(self):
        spaced = f"{self.t}/img dir"
        put(f"{spaced}/sess one/ig_a.png", "spaced\n")
        rc, out, _ = self.run_cli(f"{self.t}/out/d.png", images=spaced)
        self.assertEqual(rc, 0)
        self.assertIn("ig_a.png", out)
        self.assertEqual(read(f"{self.t}/out/d.png"), "spaced\n")

    def test_ig_image_wins_over_a_newer_plain_png_and_the_newest_ig_wins(self):
        put(f"{self.images}/s/ig_a_new.png", "newest ig\n", Y2022)
        put(f"{self.images}/s/ig_b_old.png", "older ig\n", Y2021)
        put(f"{self.images}/s/render.png", "plain\n", Y2023)
        rc, out, _ = self.run_cli(f"{self.t}/out/e.png")
        self.assertEqual((rc, read(f"{self.t}/out/e.png")), (0, "newest ig\n"))
        touch(f"{self.images}/s/ig_b_old.png", Y2024)
        self.run_cli(f"{self.t}/out/e.png")
        self.assertEqual(read(f"{self.t}/out/e.png"), "older ig\n")

    def test_hidden_entries_and_non_files_are_never_picked(self):
        put(f"{self.images}/s/render.png", "plain\n", Y2020)
        put(f"{self.images}/s/.hidden.png", "hidden\n", Y2023)
        os.makedirs(f"{self.images}/s/ig_dir.png")
        touch(f"{self.images}/s", Y2020)
        os.makedirs(f"{self.images}/.hidden-session")
        touch(f"{self.images}/.hidden-session", Y2024)
        rc, out, _ = self.run_cli(f"{self.t}/out/f.png")
        self.assertEqual((rc, out), (0, f"copied {self.images}/s/render.png -> {self.t}/out/f.png\n"))

    def test_images_directory_defaults_to_the_codex_folder_under_home(self):
        put(f"{self.t}/home/.codex/generated_images/s/ig_h.png", "home\n")
        rc, out, _ = self.run_cli(f"{self.t}/out/g.png", env={"CODEX_IMAGES_DIR": "", "HOME": f"{self.t}/home"})
        self.assertEqual((rc, read(f"{self.t}/out/g.png")), (0, "home\n"))
        self.assertIn(f"{self.t}/home/.codex/generated_images/s/ig_h.png", out)

    def test_destination_that_cannot_be_written_exits_1(self):
        self.old_and_new_session()
        rc, out, err = self.run_cli(f"{self.images}/sample.png/below-a-file/a.png")
        self.assertEqual((rc, out), (1, ""))
        self.assertIn("codex-image-copy: ", err)

    def test_runs_as_a_program(self):
        self.assertTrue(os.access(TOOL, os.X_OK))
        with open(TOOL) as f:
            self.assertEqual(f.readline(), "#!/usr/bin/env python3\n")
        put(f"{self.images}/s/ig_a.png", "image\n")
        env = dict(os.environ, CODEX_IMAGES_DIR=self.images)
        p = subprocess.run([sys.executable, TOOL, f"{self.t}/out/h.png"], env=env, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True, timeout=60)
        self.assertEqual((p.returncode, p.stdout, p.stderr),
                         (0, f"copied {self.images}/s/ig_a.png -> {self.t}/out/h.png\n", ""))
        p = subprocess.run([sys.executable, TOOL], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           text=True, timeout=60)
        self.assertEqual((p.returncode, p.stdout, p.stderr), (64, "", "usage: codex-image-copy <destination-file>\n"))

    def test_parent_dir_matches_dirname(self):
        for path, want in (("a.png", "."), ("out/a.png", "out"), ("/a.png", "/"), ("/x/y/a.png", "/x/y"),
                           ("out/sub/", "out"), ("dir/", "."), ("/", "/"), ("a//b", "a")):
            self.assertEqual(image_copy.parent_dir(path), want, path)


if __name__ == "__main__":
    unittest.main()
