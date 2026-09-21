#!/usr/bin/env python3
"""Tests for bin/jira with a fake HTTP transport. Run: bash bin/jira.test.sh"""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("jira_cli", os.path.join(HERE, "jira"))
spec = importlib.util.spec_from_loader("jira_cli", loader)
jira = importlib.util.module_from_spec(spec)
loader.exec_module(jira)


class FakeTransport:
    """Records every request and answers from canned responses keyed by "METHOD path"."""

    def __init__(self):
        self.calls = []
        self.status_before = "To Do"
        self.status_after = "In Arbeit"
        self.assignee_after = "acc-1"
        self.comment_back = "Status: done"
        self.assign_fail = False
        self.die = False

    def __call__(self, req):
        path = req.full_url.replace("https://jira.test", "")
        body = json.loads(req.data) if req.data else None
        self.calls.append((req.get_method(), path, body))
        assert req.get_header("Authorization", "").startswith("Basic "), "no basic auth header"
        if self.die:
            raise urllib.error.URLError("Could not resolve host: jira.test")
        key = f"{req.get_method()} {path}"
        if key == "GET /rest/api/2/myself":
            return 200, b'{"accountId":"acc-1","displayName":"Andreas Straub"}'
        if key == "GET /rest/api/2/issue/WEB-1?fields=status":
            return 200, json.dumps({"fields": {"status": {"name": self.status_before}}}).encode()
        if key == "GET /rest/api/2/issue/WEB-1?fields=summary,status,assignee":
            return 200, json.dumps({"fields": {"summary": "Do the thing", "status": {"name": self.status_after},
                                               "assignee": {"displayName": "Andreas Straub", "accountId": self.assignee_after}}}).encode()
        if key == "GET /rest/api/2/issue/WEB-1?fields=summary,status,assignee,description":
            return 200, b'{"fields":{"summary":"Do the thing","status":{"name":"To Do"},"assignee":null,"description":"Body text"}}'
        if key == "GET /rest/api/2/issue/WEB-1/transitions":
            return 200, b'{"transitions":[{"id":"11","name":"Start work","to":{"name":"In Arbeit"}},{"id":"31","name":"Done","to":{"name":"Fertig"}}]}'
        if key == "POST /rest/api/2/issue/WEB-1/transitions":
            return 204, b""
        if key == "PUT /rest/api/2/issue/WEB-1/assignee":
            if self.assign_fail:
                raise self._http_error(400, b'{"errorMessages":["User cannot be assigned issues."]}', req)
            return 204, b""
        if key == "POST /rest/api/2/issue/WEB-1/comment":
            return 201, b'{"id":"9001"}'
        if key == "GET /rest/api/2/issue/WEB-1/comment/9001":
            return 200, json.dumps({"id": "9001", "body": self.comment_back}).encode()
        if key == "GET /rest/api/2/issue/WEB-404?fields=summary,status,assignee,description":
            raise self._http_error(404, b'{"errorMessages":["Issue does not exist or you do not have permission to see it."],"errors":{}}', req)
        return 500, json.dumps({"errorMessages": [f"unexpected {key}"]}).encode()

    @staticmethod
    def _http_error(code, body, req):
        return urllib.error.HTTPError(req.full_url, code, "err", {}, io.BytesIO(body))


class JiraCli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = os.path.join(self.tmp.name, "home")
        os.makedirs(self.home)
        with open(os.path.join(self.home, "env"), "w") as f:
            f.write("JIRA_SITE=https://jira.test/\nJIRA_EMAIL=a@b.c\nJIRA_TOKEN=SECRET-TOKEN-XYZ\n")
        os.chmod(os.path.join(self.home, "env"), 0o600)
        os.environ["JIRA_HOME"] = self.home
        for k in jira.VARS:
            os.environ.pop(k, None)
        self.t = FakeTransport()

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *argv, stdin=""):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            sys.stdin = io.StringIO(stdin)
            try:
                rc = jira.main(list(argv), self.t)
            except SystemExit as e:
                rc = e.code
            finally:
                sys.stdin = sys.__stdin__
        return rc, out.getvalue(), err.getvalue()

    # ---- env
    def test_no_env_file(self):
        os.environ["JIRA_HOME"] = os.path.join(self.tmp.name, "nohome")
        rc, out, err = self.run_cli("view", "WEB-1")
        self.assertEqual(rc, 1)
        self.assertIn("JIRA_SITE, JIRA_EMAIL and JIRA_TOKEN into", err)
        self.assertIn("nohome/env", err)

    def test_env_var_overrides_file(self):
        os.environ["JIRA_TOKEN"] = "OTHER"
        rc, _, _ = self.run_cli("view", "WEB-1")
        self.assertEqual(rc, 0)
        cfg = jira.load_env()
        self.assertEqual(cfg["JIRA_TOKEN"], "OTHER")
        self.assertEqual(cfg["JIRA_SITE"], "https://jira.test")

    def test_quoted_values_in_env_file(self):
        with open(os.path.join(self.home, "env"), "w") as f:
            f.write('JIRA_SITE="https://jira.test"\nJIRA_EMAIL=\'a@b.c\'\nJIRA_TOKEN=T\n# comment\nJIRA_START_STATUS="Doing"\n')
        cfg = jira.load_env()
        self.assertEqual(cfg["JIRA_SITE"], "https://jira.test")
        self.assertEqual(cfg["JIRA_EMAIL"], "a@b.c")
        self.assertEqual(cfg["JIRA_START_STATUS"], "Doing")

    # ---- doctor
    def test_doctor_ok(self):
        rc, out, _ = self.run_cli("doctor")
        self.assertEqual(rc, 0)
        self.assertIn("ok   - login: Andreas Straub (acc-1)", out)
        self.assertNotIn("SECRET-TOKEN-XYZ", out)

    def test_doctor_mode(self):
        os.chmod(os.path.join(self.home, "env"), 0o644)
        rc, out, _ = self.run_cli("doctor")
        self.assertEqual(rc, 1)
        self.assertIn("has mode 644, expected 600", out)

    def test_doctor_missing_file(self):
        os.environ["JIRA_HOME"] = os.path.join(self.tmp.name, "nohome")
        rc, out, _ = self.run_cli("doctor")
        self.assertEqual(rc, 1)
        self.assertIn("FAIL - ", out)
        self.assertIn("nohome/env missing", out)

    # ---- view
    def test_view(self):
        rc, out, _ = self.run_cli("view", "WEB-1")
        self.assertEqual(rc, 0)
        self.assertEqual(out.splitlines()[0], "WEB-1  To Do  unassigned  Do the thing")
        self.assertIn("Body text", out)
        self.assertEqual(self.t.calls[0][1], "/rest/api/2/issue/WEB-1?fields=summary,status,assignee,description")

    def test_view_missing_issue(self):
        rc, _, err = self.run_cli("view", "WEB-404")
        self.assertEqual(rc, 1)
        self.assertIn("HTTP 404 on GET /rest/api/2/issue/WEB-404", err)
        self.assertIn("Issue does not exist", err)

    def test_bad_key(self):
        rc, _, err = self.run_cli("view", "web-1")
        self.assertEqual(rc, 1)
        self.assertIn("not a ticket key", err)

    # ---- start
    def test_start(self):
        rc, out, _ = self.run_cli("start", "WEB-1")
        self.assertEqual(rc, 0)
        self.assertIn(("POST", "/rest/api/2/issue/WEB-1/transitions", {"transition": {"id": "11"}}), self.t.calls)
        self.assertIn(("PUT", "/rest/api/2/issue/WEB-1/assignee", {"accountId": "acc-1"}), self.t.calls)
        self.assertIn("started: WEB-1  In Arbeit  Andreas Straub  Do the thing", out)

    def test_start_already_in_progress(self):
        self.t.status_before = "In Arbeit"
        rc, out, _ = self.run_cli("start", "WEB-1")
        self.assertEqual(rc, 0)
        self.assertNotIn("POST", [c[0] for c in self.t.calls])
        self.assertIn("(was already in that status)", out)

    def test_start_unknown_target(self):
        os.environ["JIRA_START_STATUS"] = "Doing"
        rc, _, err = self.run_cli("start", "WEB-1")
        self.assertEqual(rc, 1)
        self.assertIn("available targets: In Arbeit, Fertig", err)

    def test_start_readback_mismatch(self):
        self.t.status_after = "To Do"
        rc, _, err = self.run_cli("start", "WEB-1")
        self.assertEqual(rc, 1)
        self.assertIn("read-back status is 'To Do', expected 'In Arbeit'", err)

    # ---- transition, assign
    def test_transition_case_insensitive(self):
        rc, out, _ = self.run_cli("transition", "WEB-1", "in arbeit")
        self.assertEqual(rc, 0)
        self.assertIn("transitioned: WEB-1  In Arbeit", out)

    def test_transition_unknown(self):
        rc, _, _ = self.run_cli("transition", "WEB-1", "Nope")
        self.assertEqual(rc, 1)

    def test_transition_readback_mismatch(self):
        self.t.status_after = "To Do"
        rc, _, err = self.run_cli("transition", "WEB-1", "In Arbeit")
        self.assertEqual(rc, 1)
        self.assertIn("read-back status is 'To Do'", err)

    def test_assign_by_id(self):
        self.t.assignee_after = "acc-2"
        rc, out, _ = self.run_cli("assign", "WEB-1", "acc-2")
        self.assertEqual(rc, 0)
        self.assertIn(("PUT", "/rest/api/2/issue/WEB-1/assignee", {"accountId": "acc-2"}), self.t.calls)
        self.assertIn("assigned: WEB-1", out)

    def test_assign_default_me(self):
        rc, _, _ = self.run_cli("assign", "WEB-1")
        self.assertEqual(rc, 0)
        self.assertIn(("PUT", "/rest/api/2/issue/WEB-1/assignee", {"accountId": "acc-1"}), self.t.calls)

    def test_assign_readback_mismatch(self):
        rc, _, err = self.run_cli("assign", "WEB-1", "acc-2")
        self.assertEqual(rc, 1)
        self.assertIn("read-back assignee is 'acc-1', expected 'acc-2'", err)

    def test_assign_write_fails(self):
        self.t.assign_fail = True
        rc, _, err = self.run_cli("assign", "WEB-1", "acc-2")
        self.assertEqual(rc, 1)
        self.assertIn("HTTP 400 on PUT /rest/api/2/issue/WEB-1/assignee: User cannot be assigned issues.", err)

    # ---- comment
    def test_comment(self):
        rc, out, _ = self.run_cli("comment", "WEB-1", "Status: done. PR https://github.com/e/r/pull/1")
        self.assertEqual(rc, 0)
        self.assertIn(("POST", "/rest/api/2/issue/WEB-1/comment", {"body": "Status: done. PR https://github.com/e/r/pull/1"}), self.t.calls)
        self.assertIn(("GET", "/rest/api/2/issue/WEB-1/comment/9001", None), self.t.calls)
        self.assertIn("commented: WEB-1 comment 9001 (12 chars read back)", out)

    def test_comment_from_stdin(self):
        rc, _, _ = self.run_cli("comment", "WEB-1", "-", stdin='line one\nline "two"\n')
        self.assertEqual(rc, 0)
        self.assertIn(("POST", "/rest/api/2/issue/WEB-1/comment", {"body": 'line one\nline "two"\n'}), self.t.calls)

    def test_comment_empty(self):
        rc, _, _ = self.run_cli("comment", "WEB-1")
        self.assertEqual(rc, 2)
        rc, _, err = self.run_cli("comment", "WEB-1", "-", stdin="  \n")
        self.assertEqual(rc, 1)
        self.assertIn("empty comment", err)

    def test_comment_readback_empty(self):
        self.t.comment_back = ""
        rc, _, err = self.run_cli("comment", "WEB-1", "x")
        self.assertEqual(rc, 1)
        self.assertIn("comment 9001 read back empty", err)

    # ---- transport, usage
    def test_transport_failure(self):
        self.t.die = True
        rc, _, err = self.run_cli("view", "WEB-1")
        self.assertEqual(rc, 1)
        self.assertIn("request failed (GET /rest/api/2/issue/WEB-1", err)
        self.assertNotIn("SECRET-TOKEN-XYZ", err)

    def test_usage(self):
        rc, out, _ = self.run_cli()
        self.assertEqual(rc, 2)
        self.assertIn("jira comment <KEY>", out)
        rc, _, err = self.run_cli("bogus")
        self.assertEqual(rc, 2)
        self.assertIn("unknown command", err)

    def test_setup_needs_a_tty(self):
        rc, _, err = self.run_cli("setup")
        self.assertEqual(rc, 2)
        self.assertIn("needs a terminal", err)

    def test_setup_writes_env_file_mode_600(self):
        os.environ["JIRA_HOME"] = os.path.join(self.tmp.name, "fresh")
        answers = iter(["https://jira.test/", "a@b.c"])
        orig = (jira.ask, jira.ask_hidden, jira.is_tty)
        jira.ask = lambda _prompt="": next(answers)
        jira.ask_hidden = lambda _prompt="": "TOK-1"
        jira.is_tty = lambda: True
        try:
            rc, out, _ = self.run_cli("setup")
        finally:
            jira.ask, jira.ask_hidden, jira.is_tty = orig
        self.assertEqual(rc, 0, out)
        path = os.path.join(self.tmp.name, "fresh", "env")
        self.assertEqual(oct(os.stat(path).st_mode & 0o777), "0o600")
        with open(path) as f:
            self.assertEqual(f.read(), "JIRA_SITE=https://jira.test\nJIRA_EMAIL=a@b.c\nJIRA_TOKEN=TOK-1\n")
        self.assertIn("written: ", out)
        self.assertIn("ok   - login: Andreas Straub (acc-1)", out)
        self.assertNotIn("TOK-1", out)

    def test_auth_header_is_basic_of_email_and_token(self):
        self.run_cli("view", "WEB-1")
        import base64
        expected = "Basic " + base64.b64encode(b"a@b.c:SECRET-TOKEN-XYZ").decode()
        self.assertEqual(jira.Jira(jira.load_env()).auth, expected)


if __name__ == "__main__":
    unittest.main(verbosity=1)
