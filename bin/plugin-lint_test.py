#!/usr/bin/env python3
"""Tests for bin/plugin-lint. Run: bash bin/plugin-lint.test.sh"""
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from testlib import script_launcher  # noqa: E402
TOOL = os.path.join(HERE, "plugin-lint")

EM_DASH = chr(0x2014)  # never written literally: bin/ itself is scanned for it
OK = "plugin-lint: OK (2 skills, 1 agents)\n"
NOT_QUOTED = "but is not quoted (invalid YAML, wrap the value in double quotes)"

ALPHA = """\
---
name: alpha
description: The alpha skill. Triggers on "alpha".
---

Read `references/notes.md` first, then call evelan:beta.
"""
BETA = """\
---
name: beta
description: >-
  The beta skill, folded over
  two lines.
---

Shared rules: `${CLAUDE_PLUGIN_ROOT}/skills/alpha/references/shared.md`.
Reviewer: evelan:helper.
"""
HELPER = """\
---
name: helper
description: A helper agent used by evelan:alpha.
---
"""
PLUGIN_JSON = """\
{
  "name": "evelan",
  "version": "1.0.0",
  "skills": "./skills/",
  "agents": [
    "./agents/helper.md"
  ]
}
"""
README = """\
# Fake plugin

Skills: alpha, beta. Agents: evelan:helper.
"""


class PluginLint(unittest.TestCase):
    """Each test starts from a clean fake plugin root: two skills (alpha with two references
    files, beta with a folded description that borrows alpha's shared.md), one agent, a
    plugin.json listing that agent, and a README naming both skills."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.p = os.path.join(os.path.realpath(self.tmp.name), "p")
        self.write("skills/alpha/SKILL.md", ALPHA)
        self.write("skills/alpha/references/notes.md", "notes\n")
        self.write("skills/alpha/references/shared.md", "shared\n")
        self.write("skills/beta/SKILL.md", BETA)
        self.write("agents/helper.md", HELPER)
        self.write(".claude-plugin/plugin.json", PLUGIN_JSON)
        self.write("README.md", README)

    def tearDown(self):
        self.tmp.cleanup()

    def path(self, rel):
        return os.path.join(self.p, rel)

    def write(self, rel, text, mode="w"):
        os.makedirs(os.path.dirname(self.path(rel)), exist_ok=True)
        with open(self.path(rel), mode, encoding="utf-8") as f:   # UTF-8 on every platform, as the repo's files are
            f.write(text)

    def append(self, rel, text):
        self.write(rel, text, mode="a")

    def sub(self, rel, pattern, replacement):
        """Replace a pattern (matched per line) in a file of the root."""
        with open(self.path(rel), encoding="utf-8") as f:
            text = f.read()
        changed = re.sub(pattern, lambda m: replacement, text, flags=re.M)
        self.assertNotEqual(changed, text)
        self.write(rel, changed)

    def run_tool(self, *args, cwd=None, tool=None):
        """Exit code, stdout and stderr of plugin-lint started outside any repository (or in cwd)."""
        p = subprocess.run((tool or [sys.executable, TOOL]) + list(args), cwd=cwd or self.tmp.name,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        return p.returncode, p.stdout, p.stderr

    def lint(self):
        """plugin-lint on the fake root."""
        return self.run_tool(self.p)

    def assert_problems(self, *wanted, others=0):
        """Exit 1, the wanted problem lines on stdout (exactly those unless others are expected),
        the count on stderr."""
        rc, out, err = self.lint()
        self.assertEqual(rc, 1, out + err)
        lines = out.splitlines()
        if others:
            for line in wanted:
                self.assertIn(line, lines)
        else:
            self.assertEqual(lines, list(wanted))
        self.assertEqual(err, f"plugin-lint: {len(wanted) + others} problem(s) found.\n")

    def test_clean_root_prints_the_ok_line(self):
        self.assertEqual(self.lint(), (0, OK, ""))

    def test_default_root_is_the_git_top_level_of_the_cwd(self):
        subprocess.run(["git", "init", "-q", self.p], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.assertEqual(self.run_tool(cwd=self.path("skills")), (0, OK, ""))
        self.assertEqual(self.run_tool("", cwd=self.path("skills")), (0, OK, ""))

    def test_name_mismatch(self):
        self.sub("skills/alpha/SKILL.md", r"^name: alpha$", "name: alfa")
        self.assert_problems("skills/alpha/SKILL.md: name: is 'alfa' but the folder is 'alpha'")

    def test_missing_description(self):
        self.sub("skills/alpha/SKILL.md", r"^description:.*\n", "")
        self.assert_problems("skills/alpha/SKILL.md: frontmatter has no description:")

    def test_empty_description(self):
        self.sub("skills/alpha/SKILL.md", r"^description:.*", "description:")
        self.assert_problems("skills/alpha/SKILL.md: description: is empty")

    def test_empty_description_block(self):
        self.sub("skills/beta/SKILL.md", r"^  The beta skill, folded over\n  two lines.\n", "")
        self.assert_problems("skills/beta/SKILL.md: description: block is empty")

    def test_missing_frontmatter(self):
        self.write("skills/alpha/SKILL.md", "no frontmatter\n")
        self.assert_problems("skills/alpha/SKILL.md: frontmatter missing (first line is not ---)", others=1)

    def test_missing_referenced_references_file(self):
        os.remove(self.path("skills/alpha/references/notes.md"))
        self.assert_problems("skills/alpha/SKILL.md: references/notes.md does not exist under skills/alpha/")

    def test_missing_cross_skill_references_file(self):
        os.remove(self.path("skills/alpha/references/shared.md"))
        self.assert_problems("skills/beta/SKILL.md: skills/alpha/references/shared.md does not exist")

    def test_unreferenced_references_file(self):
        self.write("skills/alpha/references/orphan.md", "orphan\n")
        self.assert_problems("skills/alpha/references/orphan.md: not mentioned in skills/alpha/SKILL.md or via "
                             "${CLAUDE_PLUGIN_ROOT}/skills/alpha/references/orphan.md in another SKILL.md")

    def test_references_file_mentioned_by_another_references_file(self):
        self.write("skills/alpha/references/more.md", "more\n")
        self.append("skills/alpha/references/notes.md", "Details: references/more.md.\n")
        self.assertEqual(self.lint(), (0, OK, ""))

    def test_unresolved_evelan_reference(self):
        self.append("skills/beta/SKILL.md", "See evelan:gamma.\n")
        self.assert_problems("skills/beta/SKILL.md: line 10: evelan:gamma resolves to neither skills/gamma/ "
                             "nor agents/gamma.md")

    def test_plugin_json_lists_a_missing_agent(self):
        self.sub(".claude-plugin/plugin.json", r'"\./agents/helper\.md"', '"./agents/helper.md", "./agents/ghost.md"')
        self.assert_problems(".claude-plugin/plugin.json: agents lists ghost.md but agents/ghost.md does not exist")

    def test_plugin_json_misses_an_agent(self):
        self.write("agents/extra.md", "---\nname: extra\n---\n")
        self.assert_problems(".claude-plugin/plugin.json: agents does not list agents/extra.md")

    def test_missing_plugin_json(self):
        os.remove(self.path(".claude-plugin/plugin.json"))
        self.assert_problems(".claude-plugin/plugin.json: missing")

    def test_em_dash_reported_with_file_and_line(self):
        self.append("agents/helper.md", f"A line with a {EM_DASH} dash.\n")
        self.assert_problems("agents/helper.md: line 5: em dash (U+2014)")

    def test_em_dash_is_found_in_every_scanned_place(self):
        dash = f"x\ntwo {EM_DASH} on one line {EM_DASH}\n"
        for rel in ("skills/alpha/assets/deep/x.txt", "bin/notes.txt", "CLAUDE.md", ".claude-plugin/marketplace.json"):
            self.write(rel, dash)
        self.append("README.md", dash)
        self.assert_problems("skills/alpha/assets/deep/x.txt: line 2: em dash (U+2014)",
                             "bin/notes.txt: line 2: em dash (U+2014)",
                             "README.md: line 5: em dash (U+2014)",
                             "CLAUDE.md: line 2: em dash (U+2014)",
                             ".claude-plugin/marketplace.json: line 2: em dash (U+2014)")

    def test_skill_missing_from_readme(self):
        self.write("README.md", "# Fake plugin\n\nSkills: alpha.\n")
        self.assert_problems("README.md: does not mention skill 'beta'")

    def test_missing_readme(self):
        os.remove(self.path("README.md"))
        self.assert_problems("README.md: missing")

    def test_removed_concept(self):
        self.append("README.md", "Old flow: autopilot-lead decides.\n")
        self.assert_problems('README.md: line 4: removed concept "autopilot-lead"')

    def test_excluded_files_are_not_scanned_for_references_and_removed_concepts(self):
        self.write("skills/THIRD-PARTY-NOTICES.md", "evelan:nothing and DIGEST.md\n")
        self.write("skills/alpha/x.test.sh", "evelan:nothing and wayfinder\n")
        self.assertEqual(self.lint(), (0, OK, ""))

    def test_binary_files_are_skipped(self):
        self.write("skills/alpha/image.png", f"evelan:nothing wayfinder {EM_DASH} \0 tail\n")
        self.write("bin/__pycache__/tool.pyc", f"{EM_DASH} \0\n")
        self.assertEqual(self.lint(), (0, OK, ""))

    def test_symlinks_are_not_followed(self):
        self.write("outside/notes.md", f"evelan:nothing wayfinder {EM_DASH}\n")
        try:
            os.symlink(self.path("outside/notes.md"), self.path("skills/alpha/link.md"))
            os.symlink(self.path("outside"), self.path("skills/alpha/linkdir"))
        except OSError as e:   # Windows without developer mode
            self.skipTest(f"cannot create symlinks here: {e}")
        self.assertEqual(self.lint(), (0, OK, ""))

    def test_unquoted_description_with_colon_space(self):
        self.sub("skills/alpha/SKILL.md", r"^description:.*",
                 'description: Queue control: status, add, stop. Triggers on "queue".')
        self.assert_problems(f"skills/alpha/SKILL.md: description: contains ': ' {NOT_QUOTED}")

    def test_unquoted_description_starting_with_a_yaml_indicator(self):
        self.sub("skills/alpha/SKILL.md", r"^description:.*", "description: [status | add] control the queue")
        self.assert_problems(f"skills/alpha/SKILL.md: description: starts with '[' {NOT_QUOTED}")

    def test_unquoted_argument_hint_with_colon_space(self):
        self.sub("skills/alpha/SKILL.md", r"^name: alpha$", "name: alpha\nargument-hint: <repo> <item>: the thing")
        self.assert_problems(f"skills/alpha/SKILL.md: argument-hint: contains ': ' {NOT_QUOTED}")

    def test_quoted_and_block_scalar_values_pass(self):
        self.sub("skills/alpha/SKILL.md", r"^description:.*",
                 'description: "Queue control: status, add. Triggers on \\"queue\\"."')
        self.sub("skills/alpha/SKILL.md", r"^name: alpha$",
                 "name: alpha\nargument-hint: '[status | add <repo>: item]'")
        self.sub("skills/beta/SKILL.md", r"^  The beta skill, folded over$", "  The beta skill: folded over")
        self.assertEqual(self.lint(), (0, OK, ""))

    def test_no_root_exits_2(self):
        message = "plugin-lint: no plugin root (pass a directory or run inside a git repository).\n"
        self.assertEqual(self.run_tool(), (2, "", message))
        self.assertEqual(self.run_tool(self.path("README.md")), (2, "", message))
        self.assertEqual(self.run_tool(self.path("nope")), (2, "", message))

    def test_skills_are_checked_in_byte_order_of_their_path(self):
        self.write("skills/alpha-x/SKILL.md", "---\nname: alpha-x\ndescription:\n---\n")
        self.sub("skills/alpha/SKILL.md", r"^description:.*", "description:")
        self.append("README.md", "And alpha-x.\n")
        self.assert_problems("skills/alpha-x/SKILL.md: description: is empty",
                             "skills/alpha/SKILL.md: description: is empty")

    def test_problems_come_in_the_order_of_the_checks(self):
        self.write("skills/gamma/SKILL.md", "---\nname: other\ndescription: The gamma skill.\n---\n")
        self.write("skills/alpha/references/orphan.md", "orphan\n")
        self.append("skills/alpha/SKILL.md", "See evelan:delta.\n")
        self.sub(".claude-plugin/plugin.json", r'"\./agents/helper\.md"', '"./agents/helper.md", "./agents/ghost.md"')
        self.append("agents/helper.md", f"A line with a {EM_DASH} dash.\n")
        self.append("README.md", "Old flow: autopilot-lead decides.\n")
        self.assert_problems(
            "skills/gamma/SKILL.md: name: is 'other' but the folder is 'gamma'",
            "skills/alpha/references/orphan.md: not mentioned in skills/alpha/SKILL.md or via "
            "${CLAUDE_PLUGIN_ROOT}/skills/alpha/references/orphan.md in another SKILL.md",
            "skills/alpha/SKILL.md: line 7: evelan:delta resolves to neither skills/delta/ nor agents/delta.md",
            ".claude-plugin/plugin.json: agents lists ghost.md but agents/ghost.md does not exist",
            "agents/helper.md: line 5: em dash (U+2014)",
            "README.md: does not mention skill 'gamma'",
            'README.md: line 4: removed concept "autopilot-lead"')

    def test_problem_lines_come_before_the_count_when_the_streams_are_merged(self):
        self.write("README.md", "# Fake plugin\n\nSkills: alpha.\n")
        p = subprocess.run([sys.executable, TOOL, self.p], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           universal_newlines=True)
        self.assertEqual(p.returncode, 1)
        self.assertEqual(p.stdout, "README.md: does not mention skill 'beta'\nplugin-lint: 1 problem(s) found.\n")

    def test_runs_as_an_executable(self):
        self.assertTrue(os.access(TOOL, os.X_OK))
        with open(TOOL, encoding="utf-8") as f:
            self.assertEqual(f.readline(), "#!/bin/sh\n")
        self.assertEqual(self.run_tool(self.p, tool=script_launcher() + [TOOL]), (0, OK, ""))

    def test_helpers_carry_the_launcher_header_and_compile(self):
        with open(TOOL, encoding="utf-8") as f:
            header = "".join(f.readline() for _ in range(4))
        self.write("bin/good", header + '__doc__ = """good"""\nprint(1)\n')
        self.assertEqual(self.run_tool(self.p), (0, OK, ""))
        self.write("bin/shebang", '#!/usr/bin/env python3\n"""old"""\nprint(1)\n')
        self.write("bin/broken", header + 'def (\n')
        self.write("bin/notes.txt", "not a helper\n")
        rc, out, _ = self.run_tool(self.p)
        self.assertEqual(rc, 1)
        self.assertIn("bin/broken: does not compile: ", out)
        self.assertIn("bin/shebang: does not start with the four launcher lines", out)
        self.assertNotIn("notes.txt", out)


if __name__ == "__main__":
    unittest.main()
