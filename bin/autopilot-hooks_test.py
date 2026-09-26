#!/usr/bin/env python3
"""Tests for bin/autopilot-hooks. Run: bash bin/autopilot-hooks.test.sh"""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("autopilot_hooks", os.path.join(HERE, "autopilot-hooks"))
spec = importlib.util.spec_from_loader("autopilot_hooks", loader)
hooks = importlib.util.module_from_spec(spec)
loader.exec_module(hooks)


class AutopilotHooks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.p = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = hooks.main(list(argv))
        return rc, out.getvalue(), err.getvalue()

    def test_empty_project_is_not_current(self):
        rc, out, _ = self.run_cli("check", str(self.p))
        self.assertEqual(rc, 1)
        self.assertIn("missing .claude/hooks/autopilot-gate.sh", out)
        self.assertIn("not registered autopilot-context-budget.sh (PostToolUse)", out)
        self.assertIn("not gitignored .claude/.autopilot-active", out)

    def test_install_makes_it_current_and_is_idempotent(self):
        rc, out, _ = self.run_cli("install", str(self.p))
        self.assertEqual(rc, 0)
        self.assertIn("added .claude/hooks/autopilot-gate.sh", out)
        self.assertIn("registered autopilot-gate-filter.sh (PreToolUse)", out)
        self.assertTrue(os.access(self.p / ".claude/hooks/autopilot-gate.sh", os.X_OK))
        self.assertEqual(self.run_cli("check", str(self.p))[:2], (0, "current\n"))
        rc, out, _ = self.run_cli("install", str(self.p))
        self.assertEqual((rc, out), (0, "nothing to do\n"))

    def test_install_keeps_other_settings_and_hooks(self):
        (self.p / ".claude").mkdir()
        mine = {"hooks": {"PreToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": "my-lint.sh"}]}]},
                "permissions": {"allow": ["Bash(npm test)"]}}
        (self.p / ".claude/settings.json").write_text(json.dumps(mine))
        self.run_cli("install", str(self.p))
        s = json.loads((self.p / ".claude/settings.json").read_text())
        self.assertEqual(s["permissions"], {"allow": ["Bash(npm test)"]})
        commands = [h["command"] for b in s["hooks"]["PreToolUse"] for h in b["hooks"]]
        self.assertEqual(commands, ["my-lint.sh", "$CLAUDE_PROJECT_DIR/.claude/hooks/autopilot-gate-filter.sh"])

    def test_outdated_copy_is_reported_and_replaced(self):
        self.run_cli("install", str(self.p))
        (self.p / ".claude/hooks/autopilot-gate.sh").write_text("#!/bin/sh\n# old version\n")
        rc, out, _ = self.run_cli("check", str(self.p))
        self.assertEqual(rc, 1)
        self.assertIn("outdated .claude/hooks/autopilot-gate.sh", out)
        rc, out, _ = self.run_cli("install", str(self.p))
        self.assertIn("updated .claude/hooks/autopilot-gate.sh", out)
        self.assertEqual((self.p / ".claude/hooks/autopilot-gate.sh").read_bytes(),
                         (hooks.HOOKS_SRC / "autopilot-gate.sh").read_bytes())

    def test_registered_hook_is_not_duplicated(self):
        self.run_cli("install", str(self.p))
        self.run_cli("install", str(self.p))
        s = json.loads((self.p / ".claude/settings.json").read_text())
        self.assertEqual(len(s["hooks"]["Stop"]), 1)

    def test_gitignore_keeps_existing_lines(self):
        (self.p / ".gitignore").write_text("node_modules/\n.claude/autopilot-gate.log")
        self.run_cli("install", str(self.p))
        lines = (self.p / ".gitignore").read_text().splitlines()
        self.assertEqual(lines[0], "node_modules/")
        self.assertEqual(lines.count(".claude/autopilot-gate.log"), 1)
        self.assertIn(".claude/.autopilot-active", lines)

    def test_autopilot_json_untouched(self):
        (self.p / ".claude").mkdir()
        (self.p / ".claude/autopilot.json").write_text('{"gate": "npm test"}')
        self.run_cli("install", str(self.p))
        self.assertEqual((self.p / ".claude/autopilot.json").read_text(), '{"gate": "npm test"}')

    def test_usage(self):
        self.assertEqual(self.run_cli("frobnicate", str(self.p))[0], 2)
        self.assertEqual(self.run_cli("check", str(self.p / "nope"))[0], 2)

    def test_broken_settings_json_fails_cleanly(self):
        (self.p / ".claude").mkdir()
        (self.p / ".claude/settings.json").write_text("{not json")
        rc, _, err = self.run_cli("install", str(self.p))
        self.assertEqual(rc, 1)
        self.assertIn("autopilot-hooks:", err)


if __name__ == "__main__":
    unittest.main()
