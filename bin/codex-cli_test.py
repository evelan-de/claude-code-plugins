#!/usr/bin/env python3
"""Tests for bin/codex-cli. Run: bash bin/codex-cli.test.sh

The wrapper replaces its own process with the binary it finds, so the tests start it as a
subprocess. Every `codex` here is a small script in a temporary directory; a real Codex CLI
is never started.
"""
import contextlib
import importlib.machinery
import importlib.util
import io
import os
import shutil
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
WRAPPER = os.path.join(HERE, "codex-cli")


def script_launcher():
    """How a test starts a helper by its launcher lines: directly on POSIX; on Windows through
    Git Bash, found next to git (System32 holds WSL's bash.exe, which is not it)."""
    if os.name != "nt":
        return []
    bash = os.environ.get("CLAUDE_CODE_GIT_BASH_PATH")
    if not bash:
        git = shutil.which("git") or ""
        bash = os.path.join(os.path.dirname(os.path.dirname(git)), "bin", "bash.exe")
    return [bash]
loader = importlib.machinery.SourceFileLoader("codex_cli", WRAPPER)
spec = importlib.util.spec_from_loader("codex_cli", loader)
codex_cli = importlib.util.module_from_spec(spec)
loader.exec_module(codex_cli)

SYSTEM_PATH = ["/usr/bin", "/bin"]  # no codex in there
INSTALL_HINT = ("Install it with 'npm install -g @openai/codex' or 'brew install codex',\n"
                "or install the ChatGPT desktop app, then retry.\n")


def write_script(path, body):
    with open(path, "w") as f:
        f.write(body)
    os.chmod(path, 0o755)


def fake(path, marker):
    """A codex that prints its marker and then every argument on its own line."""
    write_script(path, f'#!/bin/sh\necho "{marker}"\nfor a in "$@"; do echo "arg:$a"; done\n')


class CodexCli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.t = os.path.realpath(self.tmp.name)
        for d in ("pathbin", "appbin", "app dir with spaces", "home/.local/bin", "emptyhome"):
            os.makedirs(self.path(d))
        fake(self.path("pathbin/codex"), "FROM_PATH")
        fake(self.path("appbin/codex"), "FROM_APP")
        fake(self.path("app dir with spaces/codex"), "FROM_SPACED_APP")
        fake(self.path("home/.local/bin/codex"), "FROM_HOME")

    def tearDown(self):
        self.tmp.cleanup()

    def path(self, relative):
        return os.path.join(self.t, relative)

    def env(self, path_dirs, home, app_bin):
        env = dict(os.environ)
        env["PATH"] = os.pathsep.join([self.path(d) for d in path_dirs] + SYSTEM_PATH)
        env["HOME"] = self.path(home)
        env.pop("CODEX_CLI_APP_BIN", None)
        if app_bin is not None:
            env["CODEX_CLI_APP_BIN"] = app_bin
        return env

    def run_wrapper(self, *args, path_dirs=(), home="home", app_bin=None, stdin=None, command=None):
        """Start the wrapper with a controlled PATH, HOME and app bin; (exit code, stdout, stderr)."""
        p = subprocess.run((command or [sys.executable, WRAPPER]) + list(args), env=self.env(path_dirs, home, app_bin),
                           input=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
        return p.returncode, p.stdout, p.stderr

    def test_codex_on_path_wins(self):
        rc, out, err = self.run_wrapper("exec", "hello", path_dirs=("pathbin",), app_bin=self.path("appbin/codex"))
        self.assertEqual((rc, out, err), (0, "FROM_PATH\narg:exec\narg:hello\n", ""))

    def test_app_bin_is_second(self):
        rc, out, err = self.run_wrapper("exec", "hello", app_bin=self.path("appbin/codex"))
        self.assertEqual((rc, out, err), (0, "FROM_APP\narg:exec\narg:hello\n", ""))

    def test_app_bin_path_with_spaces_resolves(self):
        rc, out, _ = self.run_wrapper("exec", "hello", app_bin=self.path("app dir with spaces/codex"))
        self.assertEqual(rc, 0)
        self.assertIn("FROM_SPACED_APP", out)

    def test_home_local_bin_is_third(self):
        rc, out, _ = self.run_wrapper("exec", "hello", app_bin=self.path("nonexistent"))
        self.assertEqual(rc, 0)
        self.assertIn("FROM_HOME", out)

    def test_args_forwarded_verbatim(self):
        rc, out, _ = self.run_wrapper("review", "--base", "main", "two words", "", "-x", "*", path_dirs=("pathbin",),
                                      home="emptyhome", app_bin=self.path("nonexistent"))
        self.assertEqual(rc, 0)
        self.assertEqual(out, "FROM_PATH\narg:review\narg:--base\narg:main\narg:two words\narg:\narg:-x\narg:*\n")

    def test_not_found_exits_127_with_a_clear_message(self):
        rc, out, err = self.run_wrapper("--version", home="emptyhome", app_bin=self.path("nonexistent"))
        self.assertEqual(rc, 127)
        self.assertIn("Codex CLI not found", err)
        self.assertEqual(out, "")

    def test_not_found_names_every_probed_location_and_an_install_hint(self):
        rc, _, err = self.run_wrapper("--version", home="emptyhome", app_bin=self.path("nonexistent"))
        self.assertEqual(rc, 127)
        self.assertIn("codex on PATH", err)
        self.assertIn(self.path("nonexistent"), err)
        self.assertIn(self.path("emptyhome/.local/bin/codex"), err)
        self.assertIn("npm install -g @openai/codex", err)
        self.assertEqual(err, "codex-cli: Codex CLI not found. Looked for:\n"
                              "  codex on PATH\n"
                              f"  {self.path('nonexistent')}\n"
                              f"  {self.path('emptyhome/.local/bin/codex')}\n" + INSTALL_HINT)

    def test_default_probes_both_app_bundles(self):
        installed = [p for p in codex_cli.APP_BINS if os.access(p, os.X_OK)]
        if installed:
            self.skipTest(f"a real Codex is installed at {installed[0]}")
        rc, _, err = self.run_wrapper("--version", home="emptyhome")
        self.assertEqual(rc, 127)
        self.assertIn("/Applications/ChatGPT.app/Contents/Resources/codex", err)
        self.assertIn("/Applications/Codex.app/Contents/Resources/codex", err)

    def test_default_probes_both_app_bundles_when_neither_is_runnable(self):
        err = io.StringIO()
        with mock.patch.dict(os.environ, self.env((), "emptyhome", None), clear=True), \
                mock.patch.object(codex_cli, "runnable", return_value=False), contextlib.redirect_stderr(err):
            rc = codex_cli.main(["--version"])
        self.assertEqual(rc, 127)
        self.assertEqual(err.getvalue(), "codex-cli: Codex CLI not found. Looked for:\n"
                                         "  codex on PATH\n"
                                         "  /Applications/ChatGPT.app/Contents/Resources/codex\n"
                                         "  /Applications/Codex.app/Contents/Resources/codex\n"
                                         f"  {self.path('emptyhome/.local/bin/codex')}\n" + INSTALL_HINT)

    def test_app_bin_override_takes_one_path_per_line(self):
        rc, out, _ = self.run_wrapper("x", home="emptyhome", app_bin=self.path("nope") + "\n" + self.path("appbin/codex"))
        self.assertEqual((rc, out), (0, "FROM_APP\narg:x\n"))
        rc, _, err = self.run_wrapper("x", home="emptyhome", app_bin=self.path("no one") + "\n\n" + self.path("no two"))
        self.assertEqual(rc, 127)
        self.assertIn(f"  {self.path('no one')}\n  {self.path('no two')}\n", err)

    def test_exit_code_stdin_stdout_and_stderr_are_the_binarys_own(self):
        write_script(self.path("appbin/codex"), "#!/bin/sh\necho out\necho err >&2\ncat\nexit 7\n")
        rc, out, err = self.run_wrapper("x", home="emptyhome", app_bin=self.path("appbin/codex"), stdin="from stdin\n")
        self.assertEqual((rc, out, err), (7, "out\nfrom stdin\n", "err\n"))

    def test_binary_gets_the_default_sigpipe_handling(self):
        # With SIGPIPE ignored, `yes` reports a write error; with the default it ends silently.
        write_script(self.path("appbin/codex"), '#!/bin/sh\nyes 2>"$0.err" | head -n 1\n')
        rc, out, _ = self.run_wrapper(home="emptyhome", app_bin=self.path("appbin/codex"))
        self.assertEqual((rc, out), (0, "y\n"))
        with open(self.path("appbin/codex.err")) as f:
            self.assertEqual(f.read(), "")

    def test_wrapper_never_resolves_to_itself(self):
        os.makedirs(self.path("selfbin"))
        os.symlink(WRAPPER, self.path("selfbin/codex"))
        rc, out, _ = self.run_wrapper("exec", "hello", path_dirs=("selfbin", "pathbin"), home="emptyhome",
                                      app_bin=self.path("nonexistent"))
        self.assertEqual((rc, out), (0, "FROM_PATH\narg:exec\narg:hello\n"))
        rc, _, err = self.run_wrapper("--version", path_dirs=("selfbin",), home="emptyhome",
                                      app_bin=self.path("selfbin/codex"))
        self.assertEqual(rc, 127)
        self.assertIn(f"  codex on PATH\n  {self.path('selfbin/codex')}\n", err)

    def test_binary_that_cannot_be_started_exits_126(self):
        rc, out, err = self.run_wrapper("x", home="emptyhome", app_bin=self.path("appbin"))
        self.assertEqual((rc, out), (126, ""))
        self.assertIn(f"codex-cli: cannot run {self.path('appbin')}: ", err)

    def test_runs_by_its_shebang(self):
        with open(WRAPPER) as f:
            self.assertEqual(f.readline(), "#!/bin/sh\n")
        os.makedirs(self.path("pybin"))
        write_script(self.path("pybin/python3"), f'#!/bin/sh\nexec {shlex.quote(sys.executable)} "$@"\n')
        rc, out, err = self.run_wrapper("exec", "hello", path_dirs=("pybin", "pathbin"),
                                        command=script_launcher() + [WRAPPER])
        self.assertEqual((rc, out, err), (0, "FROM_PATH\narg:exec\narg:hello\n", ""))


if __name__ == "__main__":
    unittest.main()
