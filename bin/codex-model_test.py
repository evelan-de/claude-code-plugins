#!/usr/bin/env python3
"""Tests for bin/codex-model. Run: bash bin/codex-model.test.sh

The resolver reads the catalog through bin/codex-cli, which is pointed at a fake `codex` in a
temporary directory: no `codex` on PATH, the app bin set to the fake. A real Codex CLI is
never started.
"""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
RESOLVER = os.path.join(HERE, "codex-model")
loader = importlib.machinery.SourceFileLoader("codex_model", RESOLVER)
spec = importlib.util.spec_from_loader("codex_model", loader)
codex_model = importlib.util.module_from_spec(spec)
loader.exec_module(codex_model)

USAGE = "usage: codex-model list\n       codex-model resolve <name>\n"
CATALOG = ("gpt-6-astra:list,gpt-reserve:hide,gpt-5.6-sol:list,gpt-5.6-terra:list,gpt-5.6-luna:list,"
           "gpt-5.5:list,gpt-5.4-mini,codex-auto-review:hide")
SELECTABLE = ["gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5", "gpt-5.4-mini"]


def models(entries):
    """Catalog model objects for comma-separated entries: `slug` or `slug:visibility`.

    An entry without `:visibility` gets no visibility key at all, which is how older catalogs
    looked. Every model also carries a nested object and a prose field with escaped quotes, so
    the parser is proven against both.
    """
    out = []
    for entry in entries.split(","):
        slug, _, visibility = entry.partition(":")
        model = {"slug": slug, "display_name": slug,
                 "supported_reasoning_levels": [{"effort": "low", "description": "x"}]}
        if visibility:
            model["visibility"] = visibility
        model["base_instructions"] = 'Say "slug" and "visibility": "hide" in prose.'
        out.append(model)
    return out


def catalog(entries):
    """The catalog document on one line, the way `codex debug models` prints it."""
    return json.dumps({"models": models(entries)}, separators=(",", ":")) + "\n"


def write_script(path, body):
    with open(path, "w") as f:
        f.write(body)
    os.chmod(path, 0o755)


class CodexModel(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.t = os.path.realpath(self.tmp.name)
        for d in ("appbin", "emptyhome", "pybin"):
            os.makedirs(os.path.join(self.t, d))
        self.codex = os.path.join(self.t, "appbin", "codex")
        # bin/codex-cli starts through its shebang: give it the interpreter that runs this suite.
        write_script(os.path.join(self.t, "pybin", "python3"), f'#!/bin/sh\nexec {shlex.quote(sys.executable)} "$@"\n')
        self.env = {"PATH": os.pathsep.join([os.path.join(self.t, "pybin"), "/usr/bin", "/bin"]),
                    "HOME": os.path.join(self.t, "emptyhome"), "CODEX_CLI_APP_BIN": self.codex}
        self.fake_codex(catalog(CATALOG))

    def tearDown(self):
        self.tmp.cleanup()

    def fake_codex(self, text, exit_code=0):
        """A fake `codex` that answers `debug models` with the text and nothing else."""
        with open(os.path.join(self.t, "catalog"), "w") as f:
            f.write(text)
        write_script(self.codex, '#!/bin/sh\n'
                                 'if [ "$1" = "debug" ] && [ "$2" = "models" ]; then\n'
                                 f'  cat {shlex.quote(os.path.join(self.t, "catalog"))}\n'
                                 '  echo "catalog noise on stderr" >&2\n'
                                 f'  exit {exit_code}\n'
                                 'fi\n'
                                 'echo "fake codex: unexpected args: $*" >&2\n'
                                 'exit 1\n')

    def run_cli(self, *argv):
        """main() in the controlled environment; (exit code, stdout, stderr)."""
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, self.env), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = codex_model.main(list(argv))
        return rc, out.getvalue(), err.getvalue()

    def test_list_prints_the_selectable_slugs(self):
        rc, out, err = self.run_cli("list")
        self.assertEqual(rc, 0)
        self.assertIn("gpt-5.6-luna", out)
        self.assertEqual((out, err), ("\n".join(SELECTABLE) + "\n", ""))

    def test_list_hides_entries_marked_visibility_hide(self):
        rc, out, _ = self.run_cli("list")
        self.assertEqual(rc, 0)
        self.assertNotIn("codex-auto-review", out)
        self.assertNotIn("gpt-reserve", out)

    def test_list_keeps_entries_without_a_visibility_key(self):
        rc, out, _ = self.run_cli("list")
        self.assertEqual(rc, 0)
        self.assertIn("gpt-5.4-mini", out)

    def test_friendly_name_resolves_to_the_full_slug(self):
        self.assertEqual(self.run_cli("resolve", "luna"), (0, "gpt-5.6-luna\n", ""))
        self.assertEqual(self.run_cli("resolve", "astra"), (0, "gpt-6-astra\n", ""))

    def test_resolve_is_case_insensitive(self):
        self.assertEqual(self.run_cli("resolve", "Luna"), (0, "gpt-5.6-luna\n", ""))

    def test_exact_slug_passes_through(self):
        self.assertEqual(self.run_cli("resolve", "gpt-5.6-sol"), (0, "gpt-5.6-sol\n", ""))

    def test_version_only_name_resolves_by_the_suffix_rule(self):
        self.assertEqual(self.run_cli("resolve", "5.5"), (0, "gpt-5.5\n", ""))

    def test_unknown_name_fails_and_lists_the_alternatives(self):
        rc, out, err = self.run_cli("resolve", "nonsense")
        self.assertEqual(rc, 2)
        self.assertIn("nonsense", err)
        self.assertIn("gpt-5.6-sol", err)
        self.assertEqual(out, "")
        self.assertEqual(err, "codex-model: unknown model 'nonsense'. Available:\n"
                              + "".join(f"  {slug}\n" for slug in SELECTABLE))

    def test_hidden_slugs_are_not_resolvable_exactly_or_by_suffix(self):
        rc, _, err = self.run_cli("resolve", "codex-auto-review")
        self.assertEqual(rc, 2)
        self.assertIn("codex-auto-review", err)
        rc, _, err = self.run_cli("resolve", "reserve")
        self.assertEqual(rc, 2)
        self.assertIn("unknown model 'reserve'", err)

    def test_ambiguous_name_is_reported_never_guessed(self):
        self.fake_codex(catalog("gpt-5.6-luna:list,gpt-5.7-luna:list"))
        rc, out, err = self.run_cli("resolve", "luna")
        self.assertEqual(rc, 3)
        self.assertIn("ambiguous", err)
        self.assertEqual((out, err), ("", "codex-model: 'luna' is ambiguous - matches: gpt-5.6-luna gpt-5.7-luna\n"
                                          "Pick the full slug.\n"))

    def test_unreadable_catalog_passes_the_name_through_with_a_warning(self):
        write_script(self.codex, "#!/bin/sh\nexit 1\n")
        rc, out, err = self.run_cli("resolve", "gpt-5.6-luna")
        self.assertEqual(rc, 0)
        self.assertIn("gpt-5.6-luna", out)
        self.assertIn("could not read", err)
        self.assertEqual((out, err), ("gpt-5.6-luna\n", "codex-model: could not read the model catalog - "
                                                        "using 'gpt-5.6-luna' unvalidated.\n"))

    def test_missing_argument_is_a_usage_error(self):
        rc, out, err = self.run_cli("resolve")
        self.assertEqual(rc, 64)
        self.assertIn("usage", err)
        self.assertEqual((out, err), ("", USAGE))
        self.assertEqual(self.run_cli("resolve", ""), (64, "", USAGE))

    def test_unknown_subcommand_is_a_usage_error(self):
        rc, _, err = self.run_cli("frobnicate")
        self.assertEqual(rc, 64)
        self.assertIn("usage", err)
        self.assertEqual(self.run_cli(), (64, "", USAGE))

    def test_list_with_an_unreadable_catalog_exits_2(self):
        write_script(self.codex, "#!/bin/sh\nexit 1\n")
        self.assertEqual(self.run_cli("list"), (2, "", "codex-model: could not read the model catalog.\n"))
        self.env["CODEX_CLI_APP_BIN"] = os.path.join(self.t, "nonexistent")
        self.assertEqual(self.run_cli("list"), (2, "", "codex-model: could not read the model catalog.\n"))

    def test_catalog_counts_whatever_the_exit_code_of_codex(self):
        self.fake_codex(catalog(CATALOG), exit_code=1)
        self.assertEqual(self.run_cli("resolve", "luna"), (0, "gpt-5.6-luna\n", ""))

    def test_pretty_printed_catalog_and_a_plain_list_of_models(self):
        self.fake_codex(json.dumps({"models": models(CATALOG)}, indent=2) + "\n")
        self.assertEqual(self.run_cli("list")[1].split(), SELECTABLE)
        self.fake_codex(json.dumps(models(CATALOG)) + "\n")
        self.assertEqual(self.run_cli("list")[1].split(), SELECTABLE)

    def test_output_that_is_not_one_json_document_is_scanned_for_the_keys(self):
        self.fake_codex("WARN refreshing the model cache\n" + catalog(CATALOG))
        self.assertEqual(self.run_cli("list")[1].split(), SELECTABLE)
        self.assertEqual(self.run_cli("resolve", "reserve")[0], 2)
        self.fake_codex(json.dumps({"models": models(CATALOG)}, indent=2)[:-40])
        self.assertEqual(self.run_cli("list")[1].split(), SELECTABLE)

    def test_scan_pairs_slug_and_visibility_and_skips_escaped_quotes(self):
        text = ('{"slug":"a-one","visibility":"list","base_instructions":"Say \\"slug\\": \\"fake\\" here"}\n'
                '{"slug": "b-two", "visibility": "hide"}\n'
                '{"slug":"c-three"}\n'
                '{"slug":"d-four"}\n')
        self.assertEqual(codex_model.scanned_slugs(text), ["a-one", "c-three", "d-four"])
        self.assertEqual(codex_model.scanned_slugs("error: not logged in\n"), [])
        self.assertEqual(codex_model.scanned_slugs(""), [])

    def test_json_walk_takes_every_object_with_a_slug_in_document_order(self):
        doc = {"models": [{"slug": "a-one", "visibility": "list", "upgrade": {"note": "x"}},
                          {"slug": "b-two", "visibility": "hide"},
                          {"slug": "c-three"},
                          {"slug": "", "visibility": "list"},
                          {"slug": None}]}
        self.assertEqual(codex_model.json_slugs(doc), ["a-one", "c-three"])
        self.assertEqual(codex_model.json_slugs("just a string"), [])

    def test_runs_as_a_program_next_to_codex_cli(self):
        self.assertTrue(os.access(RESOLVER, os.X_OK))
        with open(RESOLVER) as f:
            self.assertEqual(f.readline(), "#!/bin/sh\n")
        self.assertEqual(codex_model.CODEX_CLI, os.path.join(HERE, "codex-cli"))
        env = dict(os.environ, **self.env)
        p = subprocess.run([sys.executable, RESOLVER, "resolve", "Luna"], env=env, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True, timeout=60)
        self.assertEqual((p.returncode, p.stdout, p.stderr), (0, "gpt-5.6-luna\n", ""))
        p = subprocess.run([sys.executable, RESOLVER, "frobnicate"], env=env, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True, timeout=60)
        self.assertEqual((p.returncode, p.stdout, p.stderr), (64, "", USAGE))


if __name__ == "__main__":
    unittest.main()
