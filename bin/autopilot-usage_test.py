#!/usr/bin/env python3
"""Tests for bin/autopilot-usage. Run: bash bin/autopilot-usage.test.sh"""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from testlib import script_launcher  # noqa: E402
TOOL = os.path.join(HERE, "autopilot-usage")

loader = importlib.machinery.SourceFileLoader("autopilot_usage", TOOL)
spec = importlib.util.spec_from_loader("autopilot_usage", loader)
usage = importlib.util.module_from_spec(spec)
loader.exec_module(usage)

TABLE = """\
agent                      type                                      calls  first_ctx  last_ctx   max_ctx  cache_read_M  cache_write_M  output_k
main                       main                                          6     100002    156102    156102           0.7           0.16       3.0
agent-explore              ?                                             2      56002     60002     60002           0.1           0.06      20.0
agent-lead1                evelan:autopilot-lead (lead-P1)               3      50002     80002     80002           0.1           0.08       5.1
agent-wf                   ?                                             1      30002     30002     30002           0.0           0.03       0.1
TOTAL                                                                   12                                          0.8           0.33      28.2
"""


def rec(path, message_id, tokens_in, cache_create, cache_read, tokens_out, repeat=1, content=None):
    """Append one assistant record (repeat times) with the given usage to a transcript."""
    message = {"usage": {"input_tokens": tokens_in, "cache_creation_input_tokens": cache_create,
                         "cache_read_input_tokens": cache_read, "output_tokens": tokens_out}}
    if message_id is not None:
        message["id"] = message_id
    if content is not None:
        message["content"] = content
    with open(path, "a") as f:
        for _ in range(repeat):
            f.write(json.dumps({"type": "assistant", "message": message}) + "\n")


class AutopilotUsage(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.p = self.tmp.name
        self.main = os.path.join(self.p, "sess.jsonl")
        self.sub = os.path.join(self.p, "sess", "subagents")

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = usage.main(list(argv))
        return rc, out.getvalue(), err.getvalue()

    def session(self):
        """Main session with six requests and three subagents (one with meta, one without, one nested)."""
        os.makedirs(os.path.join(self.sub, "workflows", "w1"))
        with open(self.main, "w") as f:
            f.write('{"type":"user","message":{"content":"go"}}\n')
        # three requests (the second written as three lines: thinking, text, tool use), then the
        # dispatch request (two lines: thinking + the Agent tool use), then two more requests
        rec(self.main, "m1", 2, 100000, 0, 500)
        rec(self.main, "m2", 2, 20000, 100000, 700, repeat=3)
        rec(self.main, "m3", 2, 30000, 120000, 900)
        rec(self.main, "m4", 2, 1000, 150000, 300, content=[{"type": "thinking", "thinking": "x"}])
        rec(self.main, "m4", 2, 1000, 150000, 300, content=[{"type": "tool_use", "name": "Agent", "input": {
            "subagent_type": "evelan:autopilot-lead", "prompt": "PACKAGE P1"}}])
        rec(self.main, "m5", 2, 5000, 151000, 400)
        rec(self.main, "m6", 2, 100, 156000, 200)
        # lead subagent with meta (second request written twice), an explore agent without meta, a nested workflow agent
        lead = os.path.join(self.sub, "agent-lead1.jsonl")
        rec(lead, "l1", 2, 50000, 0, 100)
        rec(lead, "l2", 2, 10000, 50000, 2000, repeat=2)
        rec(lead, "l3", 2, 20000, 60000, 3000)
        with open(os.path.join(self.sub, "agent-lead1.meta.json"), "w") as f:
            f.write('{"agentType":"evelan:autopilot-lead","name":"lead-P1"}\n')
        explore = os.path.join(self.sub, "agent-explore.jsonl")
        rec(explore, "e1", 2, 56000, 0, 10)
        rec(explore, "e2", 2, 4000, 56000, 20000)
        rec(os.path.join(self.sub, "workflows", "w1", "agent-wf.jsonl"), "w1", 2, 30000, 0, 50)

    def row(self, out, label):
        """The table row of one agent, split into columns."""
        lines = [line for line in out.splitlines() if line.split()[:1] == [label]]
        self.assertEqual(len(lines), 1, out)
        return lines[0].split()

    def test_table_for_a_session_with_subagents(self):
        self.session()
        rc, out, err = self.run_cli(self.main)
        self.assertEqual((rc, err), (0, ""))
        self.assertEqual(out, TABLE)

    def test_prints_a_header(self):
        self.session()
        self.assertTrue(self.run_cli(self.main)[1].startswith("agent "))

    def test_main_row_collapses_repeated_lines(self):
        self.session()
        self.assertEqual(self.row(self.run_cli(self.main)[1], "main"),
                         ["main", "main", "6", "100002", "156102", "156102", "0.7", "0.16", "3.0"])

    def test_lead_row_takes_the_type_from_meta_json(self):
        self.session()
        self.assertEqual(self.row(self.run_cli(self.main)[1], "agent-lead1"),
                         ["agent-lead1", "evelan:autopilot-lead", "(lead-P1)", "3", "50002", "80002", "80002",
                          "0.1", "0.08", "5.1"])

    def test_agent_without_meta_json_gets_type_question_mark(self):
        self.session()
        self.assertEqual(self.row(self.run_cli(self.main)[1], "agent-explore"),
                         ["agent-explore", "?", "2", "56002", "60002", "60002", "0.1", "0.06", "20.0"])

    def test_nested_workflow_agent_is_included(self):
        self.session()
        self.assertEqual(self.row(self.run_cli(self.main)[1], "agent-wf")[:4], ["agent-wf", "?", "1", "30002"])

    def test_total_requests_across_all_agents(self):
        self.session()
        self.assertEqual(self.row(self.run_cli(self.main)[1], "TOTAL"), ["TOTAL", "12", "0.8", "0.33", "28.2"])

    def test_lines_without_message_id_count_individually(self):
        noid = os.path.join(self.p, "noid.jsonl")
        rec(noid, None, 1, 10, 0, 1)
        rec(noid, None, 1, 10, 11, 1)
        self.assertEqual(self.row(self.run_cli(noid)[1], "main")[:5], ["main", "main", "2", "11", "22"])

    def test_no_planning_line_without_a_lead_dispatch(self):
        plain = os.path.join(self.p, "plain.jsonl")
        rec(plain, "p1", 2, 1000, 0, 10)
        rc, out, _ = self.run_cli(plain)
        self.assertEqual(rc, 0)
        self.assertNotIn("dispatch", out)
        self.assertEqual(len(out.splitlines()), 3)

    def test_no_argument_exits_2(self):
        rc, out, err = self.run_cli()
        self.assertEqual((rc, out), (2, ""))
        self.assertEqual(err, "usage: autopilot-usage <main-session-transcript.jsonl>\n")

    def test_missing_file_exits_2(self):
        rc, out, err = self.run_cli(os.path.join(self.p, "none.jsonl"))
        self.assertEqual((rc, out), (2, ""))
        self.assertEqual(err, "usage: autopilot-usage <main-session-transcript.jsonl>\n")

    def test_broken_and_empty_lines_are_skipped(self):
        broken = os.path.join(self.p, "broken.jsonl")
        rec(broken, "b1", 2, 1000, 0, 10)
        with open(broken, "a") as f:
            f.write('{"type":"assist\n\n   \n[1, 2]\n"text"\n7\nnull\n')
            f.write('{"type":"assistant","message":"no object"}\n')
            f.write('{"type":"assistant","message":{"id":"b9","usage":"no object"}}\n')
            f.write('{"type":"assistant","message":{"id":"b3","usage":{"input_tokens":"x","output_tokens":null}}}\n')
        rec(broken, "b2", 2, 10, 1000, 20)
        rc, out, err = self.run_cli(broken)
        self.assertEqual((rc, err), (0, ""))
        self.assertEqual(self.row(out, "main"), ["main", "main", "3", "1002", "1012", "1012", "0.0", "0.00", "0.0"])

    def test_empty_transcript_prints_zeros(self):
        empty = os.path.join(self.p, "empty.jsonl")
        with open(empty, "w"):
            pass
        rc, out, _ = self.run_cli(empty)
        self.assertEqual(rc, 0)
        self.assertEqual(self.row(out, "main"), ["main", "main", "0", "0", "0", "0", "0.0", "0.00", "0.0"])
        self.assertEqual(self.row(out, "TOTAL"), ["TOTAL", "0", "0.0", "0.00", "0.0"])

    def test_meta_json_variants(self):
        os.makedirs(self.sub)
        rec(self.main, "m1", 1, 1, 1, 1)
        metas = {"agent-a": '{"agentType":"explorer"}', "agent-b": '{"name":"only-name"}', "agent-c": "{not json",
                 "agent-d": '{"agentType":7,"name":"n"}', "agent-e": "", "agent-f": '{"agentType":"' + "x" * 50 + '"}'}
        for label, meta in metas.items():
            rec(os.path.join(self.sub, label + ".jsonl"), "x1", 1, 1, 1, 1)
            with open(os.path.join(self.sub, label + ".meta.json"), "w") as f:
                f.write(meta)
        out = self.run_cli(self.main)[1]
        self.assertEqual(self.row(out, "agent-a")[1:3], ["explorer", "1"])
        self.assertEqual(self.row(out, "agent-b")[1:4], ["?", "(only-name)", "1"])
        for label in ("agent-c", "agent-d", "agent-e"):
            self.assertEqual(self.row(out, label)[1:3], ["?", "1"])
        self.assertEqual(self.row(out, "agent-f")[1:3], ["x" * 40, "1"])

    def test_only_agent_transcripts_below_subagents_count(self):
        os.makedirs(self.sub)
        rec(self.main, "m1", 1, 1, 1, 1)
        rec(os.path.join(self.sub, "notes.jsonl"), "x1", 1, 1, 1, 1)
        rec(os.path.join(self.p, "sess", "agent-outside.jsonl"), "x1", 1, 1, 1, 1)
        self.assertEqual(len(self.run_cli(self.main)[1].splitlines()), 3)

    def test_runs_as_an_executable(self):
        self.assertTrue(os.access(TOOL, os.X_OK))
        with open(TOOL, encoding="utf-8") as f:
            self.assertEqual(f.readline(), "#!/bin/sh\n")
        self.session()
        p = subprocess.run(script_launcher() + [TOOL, self.main], stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        self.assertEqual((p.returncode, p.stdout, p.stderr), (0, TABLE, ""))
        p = subprocess.run([sys.executable, TOOL], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        self.assertEqual((p.returncode, p.stdout), (2, ""))


if __name__ == "__main__":
    unittest.main()
