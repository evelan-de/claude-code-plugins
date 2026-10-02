#!/usr/bin/env python3
"""Tests for bin/mission-control. Run: bash bin/mission-control.test.sh

Black box: every check starts the runner as a subprocess against temporary git repositories.
Fake claude, gh, docker, jira, curl, osascript and launchctl scripts record their arguments;
no network, no real runs.

One project repository and its bare origin are built once and collect branches over the
sections, so the test methods run in name order and depend on what earlier ones left behind.
ENV is the environment every started process gets; a section sets and removes variables in
it and they stay that way for the sections after it.

MC_TEST_VERBOSE=1 prints one line per check ("ok   - <label>" or "FAIL - <label>") before
the summary line "PASS=<n> FAIL=<m>".
"""
import atexit
import datetime
import glob
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "mission-control")
DARWIN = platform.system() == "Darwin"
NO_SSH = ("SSH_CONNECTION", "SSH_TTY")
SESSIONS = "docs/autopilot/sessions"
PAUL9 = SESSIONS + "/2026-09-19-PAUL-9-thing"

RESULTS = []   # (label, passed) of every check, in the order they ran
ENV = {}       # the environment of every process the suite starts


class S:
    """Paths of the run: the temp dir, the project, its origin, the current queue home and
    record dir, and the dates section (t) works with."""
    tmp = proj = origin = fakes = qh = rec = host = ""
    today = yesterday = in3days = ""


# ---------- fakes ----------

FAKE_HEAD = r'''#!/usr/bin/env python3
import os
import sys

ARGS = sys.argv[1:]
LINE = " ".join(ARGS)
REC = os.environ.get("FAKE_RECORD", "")


def record(name):
    """Appends the arguments as one line to <FAKE_RECORD>/<name>."""
    with open(os.path.join(REC, name), "ab") as f:
        f.write(os.fsencode(LINE + "\n"))


def say(text):
    sys.stdout.buffer.write(os.fsencode(text + "\n"))
    sys.stdout.flush()


def write(path, text, mode="wb"):
    with open(path, mode) as f:
        f.write(text.encode("utf-8"))


def arg_after(flag):
    """The argument after the last <flag>, or nothing."""
    value = ""
    for i, arg in enumerate(ARGS):
        if arg == flag:
            value = ARGS[i + 1] if i + 1 < len(ARGS) else ""
    return value
'''

# FAKE_SCENARIO decides what the "run" leaves behind: ok, notloggedin, noop and sleep answer
# without touching the worktree; the others write REPORT.md, HANDOFF.md or NOTES.md into the
# session directory and commit.
FAKE_CLAUDE = FAKE_HEAD + r'''
import re
import shutil
import subprocess
import time


def git(*args, **how):
    return subprocess.call(["git"] + list(args), **how)


def remove(path):
    if os.path.exists(path):
        os.remove(path)


def contains(path, text):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return text in f.read()
    except OSError:
        return False


record("claude.args")
scenario = os.environ.get("FAKE_SCENARIO", "")
if scenario == "ok":
    say("OK")
    sys.exit(0)
if scenario == "notloggedin":
    say("Not logged in")
    sys.exit(1)
if scenario == "noop":
    say('{"type":"result"}')
    sys.exit(0)
if scenario == "sleep":
    write(REC + "/claude.pid", "%d\n" % os.getpid())
    os.execvp("sleep", ["sleep", "30"])

item = ARGS[1] if len(ARGS) > 1 else ""
if item.startswith("/autopilot "):
    item = item[len("/autopilot "):]
if item.startswith("docs/autopilot/sessions/"):
    sd = item
else:
    sd = "docs/autopilot/sessions/2026-09-20-" + re.sub(r"[^A-Za-z0-9-]", "-", item)
with open(REC + "/claude.args", "rb") as f:
    n = len([line for line in f.read().split(b"\n") if line])
if os.path.isfile(".claude/.autopilot-active"):
    write(REC + "/sentinel.seen", "attempt %d\n" % n, "ab")
write(REC + "/claude.path.%d" % n, os.environ.get("PATH", "").split(":")[0] + "\n")
if os.access(".claude/hooks/autopilot-context-budget.sh", os.X_OK) \
        and contains(".claude/settings.json", "autopilot-context-budget"):
    write(REC + "/hooks.seen", "attempt %d\n" % n, "ab")
if os.path.isfile(REC + "/jira.args"):
    shutil.copyfile(REC + "/jira.args", REC + "/jira-at-claude-start.%d" % n)
os.makedirs(".claude", exist_ok=True)
write(".claude/.autopilot-status", "2026-09-21T00:00:00Z ctx=1 tool=Bash\n")
if git("symbolic-ref", "-q", "HEAD", stdout=subprocess.DEVNULL) != 0:
    git("checkout", "-q", "-B", "feat/" + os.path.basename(sd.rstrip("/")))
with open(REC + "/claude.gitlog.%d" % n, "wb") as f:
    git("log", "--oneline", "-20", stdout=f)
os.makedirs(sd, exist_ok=True)
report, handoff, notes = sd + "/REPORT.md", sd + "/HANDOFF.md", sd + "/NOTES.md"
scenario = scenario or "report"
if scenario == "report":
    remove(handoff)
    write(report, "Status: done\n\n# REPORT\n\nshipped %s\n" % item)
elif scenario == "report-blocked":
    write(report, "Status: blocked - cannot reach the API\n\n# REPORT\n")
elif scenario == "report-full":
    remove(handoff)
    write(report, "Status: done\n\n## What shipped\n- **greet** helper with \"quotes\" and a back\\slash\n"
          + "".join("- shipped line %d\n" % i for i in range(2, 11))
          + "\n## Verification\n- gate green\n\n## Open items\n- ask Markus about the copy\n")
elif scenario == "report-edge":
    remove(handoff)
    write(report, "Status: done\r\n\r\n## What shipped\r\n"
          "- ping <!channel> & see [docs](https://x.y/z?a=1&b=2)\r\n"
          "- esc \033[31mred\033[0m end\r\n"
          "- " + "ä" * 300 + "\r\n\r\n## Open Items:\r\n- none left\r\n")
elif scenario == "report-blocked-open":
    write(report, "Status: blocked - gate needs a database\n\n## Open items\n- start Postgres on the Mini\n")
elif scenario == "report-nostatus":
    write(report, "# REPORT\n\nno status here\n")
elif scenario == "handoff-then-report":
    if n == 1:
        write(handoff, "# HANDOFF\n")
    else:
        remove(handoff)
        write(report, "Status: done\n")
elif scenario == "handoff-always":
    write(handoff, "# HANDOFF %d\n" % n)
elif scenario == "early-exit-then-report":
    # the first attempt commits work but ends its turn without REPORT.md or HANDOFF.md
    if n == 1:
        write(notes, "wip\n")
    else:
        write(report, "Status: done\n")
elif scenario == "early-exit-always":
    write(notes, "wip %d\n" % n)
elif scenario == "handoff-then-abort":
    if n == 1:
        write(handoff, "# HANDOFF\n")
    else:
        time.sleep(1)
        write(report, "Status: blocked - gate needs a database\n")
elif scenario == "budget":
    say('{"type":"result","subtype":"error_max_budget_usd","is_error":true,"total_cost_usd":60.1}')
    sys.exit(1)
git("add", "-A", "--", ".", ":!.claude", stdout=subprocess.DEVNULL)
git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "fake run %d" % n)
say('{"type":"result","total_cost_usd":0.1}')
'''

# FAKE_GH_PRS names a file with one PR per line: <number> <head branch> <url> [<base branch,
# default main>]. FAKE_GH_FAIL: a call whose arguments contain this text fails.
# FAKE_REVIEW_INLINE and FAKE_REVIEW_TOP hold the logins of the review comments; a login may
# carry a thread spec: "bot:1" is comment id 1 starting a thread, "andreas>1" a reply to
# comment 1, a bare login a thread start with a fresh id.
FAKE_GH = FAKE_HEAD + r'''
import fnmatch
import json
import shutil

env = os.environ.get


def pr_lines(quiet=False):
    try:
        with open(env("FAKE_GH_PRS") or "/nonexistent", encoding="utf-8") as f:
            return f.read().split("\n")[:-1]
    except OSError:
        if not quiet:
            sys.stderr.write("fake gh: %s: No such file or directory\n" % (env("FAKE_GH_PRS") or "/nonexistent"))
        return []


def words(line, count):
    found = line.split()
    return found + [""] * (count - len(found))


def jq(expr, data):
    """What gh prints for --jq <expr>, for the expressions the runner sends."""
    if expr in ("", "."):
        return json.dumps(data, indent=2)
    if expr == ".login" and isinstance(data, dict):
        return data["login"]
    sys.stderr.write("fake gh: --jq %s is not supported\n" % expr)
    sys.exit(1)


record("gh.args")
if (env("FAKE_GH_FAIL") or "@@none@@") in LINE:
    sys.stderr.write("fake gh: failing on purpose\n")
    sys.exit(1)
command = " ".join((ARGS + ["", ""])[:2])
if command == "auth status" and env("FAKE_GH_AUTH_FAIL"):
    sys.stderr.write("You are not logged into any GitHub hosts. To log in, run: gh auth login\n")
    sys.exit(1)
if command in ("auth status", "label create", "pr ready", "pr edit"):
    sys.exit(0)
if command == "pr comment":
    n = len([name for name in os.listdir(REC) if name.startswith("comment.")])
    for i, arg in enumerate(ARGS):
        if arg == "--body-file" and i + 1 < len(ARGS):
            try:
                shutil.copyfile(ARGS[i + 1], "%s/comment.%d" % (REC, n + 1))
            except OSError as e:
                sys.stderr.write("fake gh: %s\n" % e)
    sys.exit(0)
if command == "label list":
    say("\n".join(os.environ.get("FAKE_GH_LABELS", "autopilot-ready autopilot-done autopilot-blocked").split()))
    sys.exit(0)
if command == "pr view":
    if "--json author" in LINE:
        say(env("FAKE_PR_AUTHOR") or "andreas")
        sys.exit(0)
    if "--json title" in LINE:
        say(env("FAKE_PR_TITLE") or "Fake PR title")
        sys.exit(0)
    ref = ARGS[2] if len(ARGS) > 2 else ""
    for line in pr_lines():
        if line.startswith(ref + " "):
            number, branch, url, base = words(line, 4)[:4]
            say(" ".join([number, branch, base or "main", url]))
    sys.exit(0)
if command == "repo view":
    say("e/r")
    sys.exit(0)
if command.startswith("api "):
    path, expr = ARGS[1], arg_after("--jq")
    if path == "user":
        # the gh account of the queue machine
        say(jq(expr, {"login": env("FAKE_GH_ME") or "andreas"}))
        sys.exit(0)
    if fnmatch.fnmatchcase(path, "*/pulls/*/comments"):
        logins = env("FAKE_REVIEW_INLINE") or ""
    elif fnmatch.fnmatchcase(path, "*/issues/*/comments"):
        logins = env("FAKE_REVIEW_TOP") or ""
    else:
        sys.exit(1)
    comments, fresh = [], 100
    for spec in logins.split():
        fresh += 1
        try:
            if ">" in spec:
                login, _, parent = spec.partition(">")
                comments.append({"id": fresh, "user": {"login": login}, "in_reply_to_id": int(parent)})
            elif ":" in spec:
                login, _, number = spec.partition(":")
                comments.append({"id": int(number), "user": {"login": login}, "in_reply_to_id": None})
            else:
                comments.append({"id": fresh, "user": {"login": spec}, "in_reply_to_id": None})
        except ValueError:
            sys.stderr.write("fake gh: thread spec %s has no number\n" % spec)
            sys.exit(0)
    say(jq(expr, comments))
    sys.exit(0)
if command == "pr list":
    if "--label" in LINE:
        for line in pr_lines(quiet=True):
            say(" ".join(words(line, 3)[:3]))
        sys.exit(0)
    if "--head" in LINE:
        if env("FAKE_GH_NO_PR"):
            sys.exit(0)
        branch = arg_after("--head")
        hits = [line for line in pr_lines(quiet=True) if " %s " % branch in line]
        if hits:
            number, _, url = words(hits[0], 3)[:3]
            say("%s true %s" % (number, url))
        else:
            say("7 true https://github.com/e/r/pull/7")
        sys.exit(0)
sys.exit(0)
'''

# FAKE_DOCKER_PS: the "ps" output, one "<compose project>|<working dir>" per line.
FAKE_DOCKER = FAKE_HEAD + r'''
record("docker.args")
if ARGS[:1] == ["ps"] and os.environ.get("FAKE_DOCKER_PS"):
    say(os.environ["FAKE_DOCKER_PS"])
sys.exit(0)
'''

FAKE_JIRA = FAKE_HEAD + r'''
record("jira.args")
if os.environ.get("FAKE_JIRA_FAIL"):
    sys.stderr.write("jira: HTTP 401 on GET /rest/api/2/myself: Unauthorized\n")
    sys.exit(1)
key = ARGS[1] if len(ARGS) > 1 else ""
if ARGS[:1] == ["start"]:
    say("started: %s  In Arbeit  Andreas Straub  Do the thing" % key)
elif ARGS[:1] == ["comment"]:
    n = len([name for name in os.listdir(REC) if name.startswith("jira-comment.")])
    with open("%s/jira-comment.%d" % (REC, n + 1), "wb") as f:
        f.write(sys.stdin.buffer.read())
    say("commented: %s comment 9001 (12 chars read back)" % key)
sys.exit(0)
'''

FAKE_CURL = FAKE_HEAD + r'''
record("curl.args")
sys.exit(int(os.environ.get("FAKE_CURL_EXIT") or 0))
'''

FAKE_OSASCRIPT = FAKE_HEAD + r'''
record("osascript.args")
sys.exit(0)
'''

FAKE_LAUNCHCTL = FAKE_HEAD + r'''
record("launchctl.args")
sys.exit(0)
'''

# git hooks of the test repositories, see sections (y2) and (y3)
HOOK_PRE_RECEIVE = r'''#!/usr/bin/env python3
import sys

for line in sys.stdin:
    parts = line.split(None, 2)
    if len(parts) == 3 and "PAUL-88" in parts[2]:
        sys.stderr.write("rejected for the test\n")
        sys.exit(1)
sys.exit(0)
'''

HOOK_PRE_PUSH = r'''#!/usr/bin/env python3
import sys

sys.stderr.write("gate red\n")
sys.exit(1)
'''


# ---------- helpers ----------

def check(label, passed):
    """Records one check; a failed one does not stop its section."""
    RESULTS.append((label, bool(passed)))


def has(needle, haystack):
    return needle in haystack


def lacks(needle, haystack):
    return needle not in haystack


def exists(path):
    return os.path.exists(path)


def write(path, text):
    with open(path, "wb") as f:
        f.write(text.encode("utf-8"))


def script(path, text):
    write(path, text)
    os.chmod(path, 0o755)


def read(path):
    """The file's text, empty when there is no such file."""
    try:
        with open(path, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except OSError:
        return ""


def cat(path):
    """The file's text without its trailing newlines, empty when there is no such file."""
    return read(path).rstrip("\n")


def lines_of(text):
    parts = text.split("\n")
    if parts and parts[-1] == "":
        parts.pop()
    return parts


def first_line(text):
    return text.split("\n")[0]


def line(path, number):
    """Line <number> (from 1) of the file, empty when there is none."""
    found = lines_of(read(path))
    return found[number - 1] if len(found) >= number else ""


def last_line(path):
    found = lines_of(read(path))
    return found[-1] if found else ""


def remove(path):
    if os.path.lexists(path):
        os.remove(path)


def ls(pattern):
    return sorted(glob.glob(pattern))


def one(pattern):
    """The path a glob stands for when exactly one file matches; any other count gives a path
    that does not exist."""
    return "\n".join(ls(pattern))


def bre(pattern):
    """A POSIX basic regular expression as a Python one: ( ) { } + ? | are literal there, ^
    anchors at the start only, $ at the end only, a leading * is literal."""
    out, i = [], 0
    while i < len(pattern):
        c = pattern[i]
        if c == "\\" and i + 1 < len(pattern):
            out.append(pattern[i:i + 2])
            i += 2
            continue
        if c == "[":
            j = i + 1
            if j < len(pattern) and pattern[j] == "^":
                j += 1
            if j < len(pattern) and pattern[j] == "]":
                j += 1
            while j < len(pattern) and pattern[j] != "]":
                j += 1
            out.append(pattern[i:j + 1])
            i = j + 1
            continue
        literal = (c in "(){}+?|" or (c == "^" and i > 0) or (c == "$" and i < len(pattern) - 1)
                   or (c == "*" and (i == 0 or pattern[:i] == "^")))
        out.append("\\" + c if literal else c)
        i += 1
    return "".join(out)


def grep(pattern, text, fixed=False, whole=False, ere=False):
    """The lines of the text that match: a basic regular expression, an extended one (ere),
    or a fixed string (fixed); whole wants the whole line to match."""
    if fixed:
        return [x for x in lines_of(text) if (x == pattern if whole else pattern in x)]
    regex = re.compile(pattern if ere else bre(pattern))
    return [x for x in lines_of(text) if (regex.fullmatch(x) if whole else regex.search(x))]


def grep_q(pattern, *paths, **how):
    """True when a line of one of the files matches; a missing file has no lines."""
    return any(grep(pattern, read(path), **how) for path in paths)


def grep_c(pattern, path, **how):
    """How many lines of the file match; nothing when there is no such file."""
    if not os.path.isfile(path):
        return None
    return len(grep(pattern, read(path), **how))


def count_lines(path):
    return grep_c(".", path)


def live_lines(path):
    """How many lines are neither blank nor a comment; nothing when there is no such file."""
    if not os.path.isfile(path):
        return None
    return len([x for x in lines_of(read(path)) if not re.match(r"[ \t\r\f\v]*(#|$)", x)])


def shell_status(returncode):
    """An exit code as a shell reports it: 128 + signal for a killed process."""
    return returncode if returncode >= 0 else 128 - returncode


def env_for(extra=None, unset=()):
    """ENV plus the additions of one call, minus the names it leaves out. Refuses to start
    anything whose queue home, record dir, fakes or Jira home lie outside the temp dir."""
    env = dict(ENV)
    env.update(extra or {})
    for name in unset:
        env.pop(name, None)
    for name in ("MISSION_CONTROL_HOME", "FAKE_RECORD", "CLAUDE_BIN", "GH_BIN", "JIRA_BIN", "JIRA_HOME", "DOCKER_BIN"):
        if not env.get(name, "").startswith(S.tmp + "/"):
            raise RuntimeError(f"{name} is not inside the temp dir: {env.get(name)!r}")
    return env


def mc(*args, env=None, unset=(), cwd=None, stderr=True):
    """(output, exit code) of mission-control <args>. The output is stdout and stderr together
    (stdout alone with stderr=False), without its trailing newlines."""
    done = subprocess.run([TOOL] + list(args), env=env_for(env, unset), cwd=cwd, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT if stderr else subprocess.DEVNULL)
    return done.stdout.decode("utf-8", "replace").rstrip("\n"), shell_status(done.returncode)


def start_run(output):
    """mission-control run in the background, its output in the file. A thread collects the
    exit code the moment the run ends, as a shell does for a background job: "stop" waits
    until the run's pid is gone, and a finished child nobody has waited for still has one."""
    with open(output, "wb") as f:
        runner = subprocess.Popen([TOOL, "run"], env=env_for(), stdin=subprocess.DEVNULL, stdout=f,
                                  stderr=subprocess.STDOUT)
    threading.Thread(target=runner.wait, daemon=True).start()
    return runner


def wait_for(path):
    """Waits up to 10 s for the file."""
    for _ in range(100):
        if os.path.isfile(path):
            break
        time.sleep(0.1)


def pid_in(path):
    """The pid the file holds, 0 when it holds none."""
    try:
        return int(read(path).strip())
    except ValueError:
        return 0


def gone(pid):
    """True when no signal can reach the process. Pid 0 (none recorded) counts as not gone."""
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return True
    return False


def kill9(pid):
    if pid > 0:
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


def git(*args):
    """Exit code of git <args>, its output dropped."""
    return subprocess.run(["git"] + list(args), env=ENV, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode


def git_out(*args):
    """stdout of git <args> without its trailing newlines."""
    done = subprocess.run(["git"] + list(args), env=ENV, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL)
    return done.stdout.decode("utf-8", "replace").rstrip("\n")


def commit(repo, *args):
    return git("-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", *args)


def on_origin(branch):
    return git("-C", S.origin, "rev-parse", "-q", "--verify", f"refs/heads/{branch}") == 0


def is_main_clean():
    return (git_out("-C", S.proj, "symbolic-ref", "--short", "HEAD") == "main"
            and git_out("-C", S.proj, "status", "--porcelain") == "")


def session_file(session, name, text):
    """Writes docs/autopilot/sessions/<session>/<name> in the project checkout."""
    os.makedirs(f"{S.proj}/{SESSIONS}/{session}", exist_ok=True)
    write(f"{S.proj}/{SESSIONS}/{session}/{name}", text)


def commit_and_push(message, branch):
    git("-C", S.proj, "add", "-A")
    commit(S.proj, "-m", message)
    git("-C", S.proj, "push", "-q", "origin", branch)


def plan_branch(branch, start, session, plan, message):
    """A new branch from <start> with one session plan, pushed; the checkout returns to main."""
    git("-C", S.proj, "checkout", "-q", "-b", branch, start)
    session_file(session, "PLAN.md", plan)
    commit_and_push(message, branch)
    git("-C", S.proj, "checkout", "-q", "main")


def fresh_home(name):
    """A new queue home and record dir; returns both."""
    S.qh, S.rec = f"{S.tmp}/home-{name}", f"{S.tmp}/rec-{name}"
    os.makedirs(S.qh, exist_ok=True)
    os.makedirs(S.rec, exist_ok=True)
    ENV["MISSION_CONTROL_HOME"], ENV["FAKE_RECORD"] = S.qh, S.rec
    return S.qh, S.rec


def queue(*items):
    """queue.txt with one line per item, each for the project."""
    write(f"{S.qh}/queue.txt", "".join(f"{S.proj} {item}\n" for item in items))


def write_plist(home, hour, minute, legacy=False):
    """A LaunchAgent plist as install-schedule writes it; legacy leaves out --scheduled (a
    plist from before the pause feature)."""
    os.makedirs(f"{home}/Library/LaunchAgents", exist_ok=True)
    args = "<string>run</string>" if legacy else "<string>run</string><string>--scheduled</string>"
    write(f"{home}/Library/LaunchAgents/de.evelan.mission-control.plist",
          "<dict><key>ProgramArguments</key><array><string>/x/mission-control</string>" + args
          + "</array><key>StartCalendarInterval</key><dict><key>Hour</key>"
          + f"<integer>{hour}</integer><key>Minute</key><integer>{minute}</integer></dict></dict>\n")


def slack_message(path, needle):
    """(text, exit code): the text of the first Slack message in the curl record whose line
    contains the needle. Exit code 1 when there is none, or the record is not UTF-8, or the
    payload is not JSON."""
    try:
        with open(path, encoding="utf-8") as f:
            for recorded in f:
                m = re.search(r"--data (\{.*\}) https://hooks", recorded)
                if m and needle in recorded:
                    return json.loads(m.group(1))["text"].rstrip("\n"), 0
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return "", 1


def build_fakes():
    os.makedirs(S.fakes)
    for name, text in (("claude", FAKE_CLAUDE), ("gh", FAKE_GH), ("docker", FAKE_DOCKER), ("jira", FAKE_JIRA),
                       ("curl", FAKE_CURL), ("osascript", FAKE_OSASCRIPT)):
        script(f"{S.fakes}/{name}", text)


def build_project():
    """The project: a repo with main, an origin, and feature branches."""
    proj = S.proj
    git("init", "-q", "-b", "main", proj)
    commit(proj, "--allow-empty", "-m", "init")
    # an old, unrelated session with a REPORT.md on main (must never count for another item)
    session_file("2026-01-01-OLD-1-unrelated", "REPORT.md", "Status: done\n")
    # a planned session on main with an Effort header
    session_file("2026-09-18-PAUL-20-effort", "PLAN.md", "# PLAN\n\nEffort: high\n")
    # planned sessions on main with a Model header
    session_file("2026-09-25-PAUL-160-opus", "PLAN.md", "# PLAN\nModel: opus\nEffort: medium\n")
    session_file("2026-09-25-PAUL-161-sonnet", "PLAN.md", "# PLAN\nModel: sonnet   (sonnet | opus)\nEffort: medium\n")
    session_file("2026-09-25-PAUL-162-sonnetmax", "PLAN.md", "# PLAN\nModel: Sonnet\nEffort: max\n")
    session_file("2026-09-25-PAUL-164-bold", "PLAN.md", "# PLAN\n- **Model:** `Opus`\n**Effort:** High.\n")
    git("-C", proj, "add", "-A")
    commit(proj, "-m", "sessions on main")
    git("init", "-q", "--bare", S.origin)
    git("-C", proj, "remote", "add", "origin", S.origin)
    git("-C", proj, "push", "-q", "origin", "main")
    # PR branch with a plan
    plan_branch("feat/PAUL-9-thing", "main", "2026-09-19-PAUL-9-thing",
                "# PLAN - PAUL-9 - 2026-09-19\nBranch: feat/PAUL-9-thing   Base: main   Ticket: PAUL-9\nEffort: medium\n",
                "plan")
    # PR branch without a plan
    git("-C", proj, "checkout", "-q", "-b", "feat/PAUL-10-noplan")
    commit(proj, "--allow-empty", "-m", "work")
    git("-C", proj, "push", "-q", "origin", "feat/PAUL-10-noplan")
    git("-C", proj, "checkout", "-q", "main")
    # a session dir committed only on a feature branch (list item with a branch)
    plan_branch("feat/PAUL-21-branchy", "main", "2026-09-18-PAUL-21-branchy", "# PLAN\n\nModel: opus\nEffort: low\n",
                "plan on branch")
    # PR branch whose plan names an unknown model
    plan_branch("feat/PAUL-163-bogus", "main", "2026-09-25-PAUL-163-bogus", "# PLAN\nModel: gpt-5\nEffort: high\n",
                "plan with an unknown model")
    # PRs that target preview: preview holds finished sessions that main does not have yet;
    # PR branches start from preview and add their own plan
    git("-C", proj, "checkout", "-q", "-b", "preview")
    session_file("2026-09-23-two-factor-auth", "PLAN.md",
                 "# PLAN\nBranch: feat/two-factor-auth   Base: preview   Ticket: none\n"
                 "Branch mode: session     PR: per session\n")
    session_file("2026-09-23-two-factor-auth", "REPORT.md", "Status: done\n")
    session_file("2026-09-01-PAUL-190-old", "PLAN.md", "# PLAN\nBranch: feat/PAUL-190-old   Base: preview   Ticket: none\n")
    session_file("2026-09-01-PAUL-190-old", "REPORT.md", "Status: done\n")
    commit_and_push("finished sessions merged into preview", "preview")
    plan_branch("feat/default-org-redirect", "preview", "2026-09-23-default-org-redirect",
                "# PLAN\nBranch: feat/default-org-redirect   Base: preview   Ticket: none\n"
                "Branch mode: session     PR: per session\n", "plan for default-org-redirect")
    plan_branch("feat/borrowed-plan", "preview", "2026-09-24-borrowed",
                "# PLAN\nBranch: feat/somewhere-else   Base: preview   Ticket: none\n"
                "Branch mode: session     PR: per session\n", "plan that names another branch")
    plan_branch("feat/big", "preview", "2026-09-24-big-s2",
                "# PLAN\nBranch: feat/big-s2   Base: preview   Ticket: none\n"
                "Branch mode: feature-branch feat/big     PR: none\n", "feature-branch session plan")
    # a branch holding a ticket key whose own plan sits in a directory without the key, while
    # an older finished directory with that key is on preview
    plan_branch("feat/PAUL-190-new", "preview", "2026-09-24-new-work",
                "# PLAN\nBranch: feat/PAUL-190-new   Base: preview   Ticket: none\n",
                "plan without the key in its directory name")
    # a plan whose Branch: header has backticks and a comma
    plan_branch("feat/tick", "preview", "2026-09-24-tick", "# PLAN\nBranch: `feat/tick`, Base: preview\n",
                "plan with a markdown Branch header")


def setUpModule():
    S.tmp = tempfile.mkdtemp()
    atexit.register(shutil.rmtree, S.tmp, ignore_errors=True)   # also after Ctrl-C
    S.proj, S.origin, S.fakes = S.tmp + "/proj", S.tmp + "/origin.git", S.tmp + "/fakes"
    S.host = subprocess.run(["hostname", "-s"], stdout=subprocess.PIPE).stdout.decode().strip()
    ENV.clear()
    ENV.update(os.environ)
    build_fakes()
    build_project()
    ENV.update(CLAUDE_BIN=S.fakes + "/claude", GH_BIN=S.fakes + "/gh")
    # Never the real Jira: the fake jira, and a JIRA_HOME without credentials unless a section
    # points it at <tmp>/jirahome. Without both the runner takes bin/jira and the machine's
    # real ~/.claude/jira/env and changes real tickets.
    ENV.update(JIRA_BIN=S.fakes + "/jira", JIRA_HOME=S.tmp + "/nojira")
    ENV.update(DOCKER_BIN=S.fakes + "/docker", NVM_DIR=S.tmp + "/nvm")
    ENV.update(MISSION_CONTROL_WATCH_MIN="0", MISSION_CONTROL_NO_NOTIFY="1", MISSION_CONTROL_TIMEOUT_MIN="5")
    for name in ("FAKE_GH_PRS", "FAKE_GH_NO_PR", "FAKE_GH_FAIL", "FAKE_GH_LABELS", "FAKE_GH_AUTH_FAIL",
                 "MISSION_CONTROL_EFFORT", "MISSION_CONTROL_MODEL"):
        ENV.pop(name, None)


def tearDownModule():
    passed = len([1 for _, ok in RESULTS if ok])
    report = []
    if os.environ.get("MC_TEST_VERBOSE") == "1":
        report = ["%s - %s" % ("ok  " if ok else "FAIL", label) for label, ok in RESULTS] + ["---"]
    report.append(f"PASS={passed} FAIL={len(RESULTS) - passed}")
    sys.stderr.flush()
    sys.stdout.write("\n" + "\n".join(report) + "\n")
    sys.stdout.flush()


class MissionControl(unittest.TestCase):
    def setUp(self):
        self.first = len(RESULTS)

    def tearDown(self):
        failed = [label for label, ok in RESULTS[self.first:] if not ok]
        if failed:
            self.fail("failed checks:\n  " + "\n  ".join(failed))

    def test_010_a_text_item_report_done(self):
        """(a) text item, REPORT.md with Status: done -> done"""
        qh, rec = fresh_home("a")
        proj = S.proj
        ENV["FAKE_SCENARIO"] = "report"
        write(f"{qh}/queue.txt", f"# comment\n{proj} PAUL-1\n")
        out, got = mc("run")
        check("(a) run exits 0", got == 0)
        check("(a) queue.txt emptied", live_lines(f"{qh}/queue.txt") == 0)
        done_line = cat(f"{qh}/done.txt")
        check("(a) done.txt has status done and the PR url",
              grep_q(f"^[0-9T:Z-]+ {re.escape(proj)} PAUL-1 done https://github.com/e/r/pull/7( no-plan)?$",
                     f"{qh}/done.txt", ere=True))
        check("(a) done.txt marks no-plan (PAUL-1 had none)", has(" no-plan", done_line))
        gh_args = cat(f"{rec}/gh.args")
        check("(a) gh pr ready called", has("pr ready 7", gh_args))
        check("(a) gh pr edit swaps labels to autopilot-done",
              has("pr edit 7 --remove-label autopilot-ready --add-label autopilot-done", gh_args))
        check("(a) gh pr comment called", has("pr comment 7 --body-file", gh_args))
        check("(a) PR comment body contains the report head", has("shipped PAUL-1", cat(f"{rec}/comment.1")))
        check("(a) PR comment body starts with the report heading",
              has("## Autopilot report", first_line(read(f"{rec}/comment.1"))))
        check("(a) claude started with /autopilot PAUL-1 and the launch flags",
              has("-p /autopilot PAUL-1 --model sonnet --effort xhigh --advisor fable --fallback-model opus "
                  "--permission-mode auto --max-budget-usd 200 --output-format json", cat(f"{rec}/claude.args")))
        check("(a) progress lines on stdout",
              has("[mission-control] proj PAUL-1: done (PR https://github.com/e/r/pull/7", out))
        check("(a) worktree removed after done", not exists(f"{proj}/.claude/worktrees/autopilot-PAUL-1/.git"))
        check("(a) the branch reached origin before the worktree was removed", on_origin("feat/2026-09-20-PAUL-1"))
        check("(a) the worktree lived inside the project, not under the queue home", not exists(f"{qh}/worktrees"))
        check("(a) .claude/worktrees/ excluded in the project's local exclude file",
              grep_q(".claude/worktrees/", f"{proj}/.git/info/exclude", whole=True))
        check("(a) main checkout untouched (still on main, clean)", is_main_clean())
        check("(a) log file written", bool(ls(f"{qh}/logs/*-PAUL-1.log")))
        check("(a) the run saw the sentinel .claude/.autopilot-active", grep_q("attempt 1", f"{rec}/sentinel.seen"))

    def test_020_a2_report_blocked(self):
        """(a2) Status: blocked -> blocked with the reason"""
        qh, rec = fresh_home("a2")
        wt = f"{S.proj}/.claude/worktrees/autopilot-PAUL-31"
        ENV["FAKE_SCENARIO"] = "report-blocked"
        queue("PAUL-31")
        out, got = mc("run")
        check("(a2) run exits 0", got == 0)
        check("(a2) status blocked in done.txt", grep_q(" PAUL-31 blocked ", f"{qh}/done.txt"))
        check("(a2) reason from the Status line on stdout", has("blocked: cannot reach the API", out))
        check("(a2) PR labelled autopilot-blocked",
              has("pr edit 7 --remove-label autopilot-ready --add-label autopilot-blocked", cat(f"{rec}/gh.args")))
        check("(a2) PR comment carries the reason", has("cannot reach the API", cat(f"{rec}/comment.1")))
        check("(a2) worktree kept", exists(f"{wt}/.git"))
        check("(a2) the blocked run's branch is on origin, at the worktree's commit",
              git_out("-C", S.origin, "rev-parse", "-q", "--verify", "refs/heads/feat/2026-09-20-PAUL-31")
              == git_out("-C", wt, "rev-parse", "HEAD"))
        check("(a2) the push is said", has("PAUL-31: branch feat/2026-09-20-PAUL-31 pushed to origin", out))
        check("(a2) the PR comment names the pushed branch",
              has("Branch `feat/2026-09-20-PAUL-31` pushed to origin", cat(f"{rec}/comment.1")))
        check("(a2) no push-failed in done.txt", lacks("push-failed", cat(f"{qh}/done.txt")))
        check("(a2) sentinel removed from the kept worktree", not exists(f"{wt}/.claude/.autopilot-active"))
        check("(a2) status file removed from the kept worktree", not exists(f"{wt}/.claude/.autopilot-status"))

    def test_030_a2b_budget_exhausted(self):
        """(a2b) budget exhausted, no REPORT.md or HANDOFF.md -> blocked with the budget named"""
        qh, rec = fresh_home("a2b")
        ENV["FAKE_SCENARIO"] = "budget"
        queue("PAUL-36")
        out, got = mc("run")
        check("(a2b) blocked", grep_q(" PAUL-36 blocked ", f"{qh}/done.txt"))
        check("(a2b) reason names the budget",
              has("budget of 200 USD exhausted before REPORT.md or HANDOFF.md was written", out))

    def test_040_a2c_handoff_then_abort_report(self):
        """(a2c) HANDOFF.md then an abort REPORT.md (HANDOFF left behind) -> blocked, no restart loop"""
        qh, rec = fresh_home("a2c")
        ENV["FAKE_SCENARIO"] = "handoff-then-abort"
        queue("PAUL-35")
        out, got = mc("run")
        check("(a2c) claude called exactly twice", count_lines(f"{rec}/claude.args") == 2)
        check("(a2c) blocked with the report's reason", grep_q(" PAUL-35 blocked ", f"{qh}/done.txt"))
        check("(a2c) reason from the newer REPORT.md", has("blocked: gate needs a database", out))
        check("(a2c) log says the report decided",
              grep_q("REPORT.md is newer than HANDOFF.md", *ls(f"{qh}/logs/*-PAUL-35.log")))

    def test_050_a3_report_without_status(self):
        """(a3) REPORT.md without a Status line -> blocked"""
        qh, rec = fresh_home("a3")
        ENV["FAKE_SCENARIO"] = "report-nostatus"
        queue("PAUL-32")
        out, got = mc("run")
        check("(a3) status blocked in done.txt", grep_q(" PAUL-32 blocked ", f"{qh}/done.txt"))
        check("(a3) reason names the missing status line", has("report without status line", out))

    def test_060_a4_old_session_never_counts(self):
        """(a4) an old unrelated session never makes a new item done"""
        qh, rec = fresh_home("a4")
        ENV["FAKE_SCENARIO"] = "noop"
        queue("PAUL-99")
        out, got = mc("list")
        check("(a4) list marks the item no plan (OLD-1 does not count)", has("PAUL-99 (no plan)", out))
        out, got = mc("run")
        done = lines_of(read(f"{qh}/done.txt"))
        check("(a4) run does not report done", len(done) > len(grep(" PAUL-99 done ", read(f"{qh}/done.txt"))))
        check("(a4) status blocked, no session directory", grep_q(" PAUL-99 blocked - no-plan", f"{qh}/done.txt"))
        check("(a4) reason names the missing session directory", has("no session directory for this item", out))

    def test_070_a2d_exit_without_report_or_handoff(self):
        """(a2d) clean exit without REPORT.md or HANDOFF.md -> restarted like a hand-off"""
        qh, rec = fresh_home("a2d")
        ENV["FAKE_SCENARIO"] = "early-exit-then-report"
        queue("PAUL-37")
        out, got = mc("run")
        check("(a2d) claude called twice", count_lines(f"{rec}/claude.args") == 2)
        check("(a2d) restart announced with the reason",
              has("ended without REPORT.md or HANDOFF.md, restart 1/5", out))
        check("(a2d) done with restarts=1", grep_q(" PAUL-37 done .* restarts=1", f"{qh}/done.txt"))
        qh, rec = fresh_home("a2e")
        ENV.update(FAKE_SCENARIO="early-exit-always", MISSION_CONTROL_MAX_RESTARTS="2")
        queue("PAUL-38")
        out, got = mc("run")
        check("(a2e) claude called 1 + MAX_RESTARTS times", count_lines(f"{rec}/claude.args") == 3)
        check("(a2e) handoff-limit with the artifact reason", grep_q(" PAUL-38 handoff-limit ", f"{qh}/done.txt"))
        check("(a2e) reason on stdout", has("no REPORT.md or HANDOFF.md after 2 restarts", out))
        ENV.pop("MISSION_CONTROL_MAX_RESTARTS", None)

    def test_080_a5_topic_item(self):
        """(a5) topic item: session dir found because it was created since the start"""
        qh, rec = fresh_home("a5")
        ENV["FAKE_SCENARIO"] = "report"
        queue('"Move the picker"')
        out, got = mc("run")
        check("(a5) topic item done via the directory created by the run",
              grep_q(' "Move the picker" done ', f"{qh}/done.txt"))

    def test_090_b_handoff_then_report(self):
        """(b) HANDOFF.md then REPORT.md -> done with restarts=1"""
        qh, rec = fresh_home("b")
        ENV["FAKE_SCENARIO"] = "handoff-then-report"
        queue("PAUL-2")
        out, got = mc("run")
        check("(b) run exits 0", got == 0)
        check("(b) claude called twice", count_lines(f"{rec}/claude.args") == 2)
        check("(b) done with restarts=1", grep_q(" PAUL-2 done .* restarts=1", f"{qh}/done.txt"))
        check("(b) restart announced", has("hand-off found, restart 1/5", out))
        check("(b) the restarted run saw the sentinel again", grep_q("attempt 2", f"{rec}/sentinel.seen"))

    def test_100_c_handoff_every_time(self):
        """(c) HANDOFF.md every time -> handoff-limit"""
        qh, rec = fresh_home("c")
        ENV.update(FAKE_SCENARIO="handoff-always", MISSION_CONTROL_MAX_RESTARTS="2")
        queue("PAUL-3")
        out, got = mc("run")
        check("(c) run exits 0", got == 0)
        check("(c) claude called 1 + MAX_RESTARTS times", count_lines(f"{rec}/claude.args") == 3)
        check("(c) status handoff-limit in done.txt", grep_q(" PAUL-3 handoff-limit ", f"{qh}/done.txt"))
        check("(c) PR labelled autopilot-blocked",
              has("pr edit 7 --remove-label autopilot-ready --add-label autopilot-blocked", cat(f"{rec}/gh.args")))
        check("(c) worktree kept", exists(f"{S.proj}/.claude/worktrees/autopilot-PAUL-3/.git"))
        ENV.pop("MISSION_CONTROL_MAX_RESTARTS", None)

    def test_110_d_pr_items(self):
        """(d) PR items from repos.txt, including a PR whose branch is missing"""
        qh, rec = fresh_home("d")
        ENV["FAKE_SCENARIO"] = "report"
        write(f"{rec}/prs.txt", "11 feat/PAUL-9-thing https://github.com/e/r/pull/11\n"
                                "12 feat/PAUL-10-noplan https://github.com/e/r/pull/12\n"
                                "13 feat/PAUL-11-missing https://github.com/e/r/pull/13\n")
        ENV["FAKE_GH_PRS"] = f"{rec}/prs.txt"
        write(f"{qh}/repos.txt", f"{S.proj}\n")
        out, got = mc("run")
        check("(d) run exits 0", got == 0)
        cl = cat(f"{rec}/claude.args")
        check("(d) PR 11 run with the session dir found on its branch", has(f"/autopilot {PAUL9} ", cl))
        check("(d) PR 12 run with the ticket key from the branch name", has("/autopilot PAUL-10 ", cl))
        check("(d) PR 11 done without no-plan",
              grep_q(f" {PAUL9} done https://github.com/e/r/pull/11$", f"{qh}/done.txt"))
        check("(d) PR 12 done and marked no-plan",
              grep_q(" PAUL-10 done https://github.com/e/r/pull/12 no-plan$", f"{qh}/done.txt"))
        gh_args = cat(f"{rec}/gh.args")
        check("(d) labels swapped on PR 11",
              has("pr edit 11 --remove-label autopilot-ready --add-label autopilot-done", gh_args))
        check("(d) PR 11 got a start comment with model and effort before the run",
              has(f"pr comment 11 --body Autopilot started on {S.host} at ", gh_args))
        check("(d) the start comment names the launch settings",
              has("(model sonnet, effort xhigh). Please do not push to this branch", gh_args))
        check("(d) PR 13 (not run) got no start comment", lacks("pr comment 13 --body Autopilot started", gh_args))
        check("(d) labels swapped on PR 12",
              has("pr edit 12 --remove-label autopilot-ready --add-label autopilot-done", gh_args))
        check("(d) PR 13 (branch missing) blocked in done.txt",
              grep_q(" #13 blocked https://github.com/e/r/pull/13$", f"{qh}/done.txt"))
        check("(d) PR 13 labelled autopilot-blocked although no worktree exists",
              has("pr edit 13 --remove-label autopilot-ready --add-label autopilot-blocked", gh_args))
        check("(d) PR 13 got a comment", has("pr comment 13 --body-file", gh_args))
        check("(d) PR 13 was not run", lacks("PAUL-11", cl))
        check("(d) main checkout still on main, clean", is_main_clean())
        check("(d) PR 11 log named after the PR number and the resolved session dir",
              bool(ls(f"{qh}/logs/*-_11-2026-09-19-PAUL-9-thing.log")))
        check("(d) PR 12 log named after the PR number and the ticket key", bool(ls(f"{qh}/logs/*-_12-PAUL-10.log")))
        check("(d) no log left under the pre-resolution name", not ls(f"{qh}/logs/*-_11.log"))
        check("(d) PR 13 (blocked before resolution) keeps the PR-number name", bool(ls(f"{qh}/logs/*-_13.log")))
        check("(d) the renamed log holds the whole run",
              grep_q("#11: resolving", *ls(f"{qh}/logs/*-_11-2026-09-19-PAUL-9-thing.log")))
        ENV.pop("FAKE_GH_PRS", None)

    def test_120_d2_term_kills_the_claude_process(self):
        """(d2) TERM during a PR item kills the claude process"""
        qh, rec = fresh_home("d2")
        ENV["FAKE_SCENARIO"] = "sleep"
        write(f"{rec}/prs.txt", "12 feat/PAUL-10-noplan https://github.com/e/r/pull/12\n")
        ENV["FAKE_GH_PRS"] = f"{rec}/prs.txt"
        write(f"{qh}/repos.txt", f"{S.proj}\n")
        runner = start_run(f"{rec}/out")
        wait_for(f"{rec}/claude.pid")
        time.sleep(0.5)
        runner.send_signal(signal.SIGTERM)
        got = shell_status(runner.wait())
        cpid = pid_in(f"{rec}/claude.pid")
        time.sleep(0.5)
        check("(d2) claude pid recorded", cpid > 0)
        check("(d2) run exited on TERM with 130", got == 130)
        check("(d2) fake claude is gone after TERM to the queue", gone(cpid))
        check("(d2) lock released", not exists(f"{qh}/run.lock"))
        kill9(cpid)
        ENV.pop("FAKE_GH_PRS", None)

    def test_130_d3_pr_list_failure(self):
        """(d3) gh pr list --label failure is reported, the other source still runs"""
        qh, rec = fresh_home("d3")
        proj = S.proj
        ENV.update(FAKE_SCENARIO="report", FAKE_GH_FAIL="pr list --label")
        queue("PAUL-33")
        write(f"{qh}/repos.txt", f"{proj}\n")
        out, got = mc("run")
        check("(d3) run exits 1 when a source failed", got == 1)
        check("(d3) FAIL line on stdout", has(f"FAIL - {proj}: gh pr list --label autopilot-ready failed", out))
        check("(d3) FAIL line in the log",
              grep_q("gh pr list --label autopilot-ready failed", f"{qh}/logs/queue.log"))
        check("(d3) the list item was still processed", grep_q(" PAUL-33 done ", f"{qh}/done.txt"))
        out, got = mc("list")
        check("(d3) list reports the failure too",
              has(f"FAIL - {proj}: gh pr list --label autopilot-ready failed", out))
        check("(d3) list exits 1 when a source failed", got == 1)
        ENV.pop("FAKE_GH_FAIL", None)

    def test_140_d4_gh_cannot_read_its_token(self):
        """(d4) gh cannot read its token: one notice, no per-repo FAIL lines"""
        qh, rec = fresh_home("d4")
        proj = S.proj
        ENV.update(FAKE_SCENARIO="report", FAKE_GH_AUTH_FAIL="1")
        fakehome = f"{S.tmp}/fakehome-d4"
        os.makedirs(fakehome, exist_ok=True)
        write(f"{qh}/repos.txt", f"{proj}\n{proj}\n")
        ssh_notice = ("gh: token not readable in this SSH session (macOS Keychain); labelled PRs unknown here, "
                      "the scheduled run in the GUI session sees them")
        login_notice = 'gh: not authenticated (run "gh auth login -h github.com -w"); labelled PRs unknown'
        unknown_line = "labelled PRs: unknown (gh not authenticated in this session)"
        ssh = {"SSH_CONNECTION": "10.0.0.2 51234 10.0.0.1 22"}
        # over SSH: the token sits in the Keychain of the GUI session
        out, got = mc("status", env=dict(ssh, HOME=fakehome))
        check("(d4) status over SSH exits 0", got == 0)
        check("(d4) status over SSH prints the Keychain notice exactly once",
              len(grep(ssh_notice, out, fixed=True)) == 1)
        check("(d4) status over SSH prints no per-repo FAIL line", lacks("FAIL -", out))
        check("(d4) status over SSH says the labelled PRs are unknown", has(unknown_line, out))
        check("(d4) status over SSH prints no PR count", lacks("labelled PRs: 0", out))
        check("(d4) status over SSH did not poll the repos", lacks("pr list --label", cat(f"{rec}/gh.args")))
        out, got = mc("status", env={"SSH_TTY": "/dev/ttys003", "HOME": fakehome})
        check("(d4) SSH_TTY alone counts as an SSH session", has(ssh_notice, out))
        out, got = mc("list", env=ssh)
        check("(d4) list over SSH exits 0", got == 0)
        check("(d4) list over SSH prints the Keychain notice exactly once",
              len(grep(ssh_notice, out, fixed=True)) == 1)
        check("(d4) list over SSH prints no per-repo FAIL line", lacks("FAIL -", out))
        queue("PAUL-90")
        out, got = mc("run", env=ssh)
        check("(d4) run over SSH exits 0", got == 0)
        check("(d4) run over SSH prints the Keychain notice exactly once",
              len(grep(ssh_notice, out, fixed=True)) == 1)
        check("(d4) run over SSH prints no per-repo FAIL line", lacks("FAIL -", out))
        check("(d4) run over SSH still processed the queue item", grep_q(" PAUL-90 done ", f"{qh}/done.txt"))
        check("(d4) run over SSH logged the notice", grep_q(ssh_notice, f"{qh}/logs/queue.log", fixed=True))
        check("(d4) run over SSH does not say a source failed", lacks("one source failed", out))
        # not over SSH: a real login problem
        out, got = mc("status", env={"HOME": fakehome}, unset=NO_SSH)
        check("(d4) status without SSH exits 0", got == 0)
        check("(d4) status without SSH says to log in", has(login_notice, out))
        check("(d4) status without SSH does not mention the Keychain", lacks("Keychain", out))
        check("(d4) status without SSH says the labelled PRs are unknown", has(unknown_line, out))
        out, got = mc("list", unset=NO_SSH)
        check("(d4) list without SSH exits 1", got == 1)
        check("(d4) list without SSH prints the login notice exactly once",
              len(grep(login_notice, out, fixed=True)) == 1)
        check("(d4) list without SSH prints no per-repo FAIL line", lacks("FAIL -", out))
        queue("PAUL-91")
        out, got = mc("run", unset=NO_SSH)
        check("(d4) run without SSH exits 1 (a real auth problem)", got == 1)
        check("(d4) run without SSH prints the login notice exactly once",
              len(grep(login_notice, out, fixed=True)) == 1)
        check("(d4) run without SSH still processed the queue item", grep_q(" PAUL-91 done ", f"{qh}/done.txt"))
        # no repos: gh is not asked at all
        write(f"{qh}/repos.txt", "")
        out, got = mc("list", env=ssh)
        check("(d4) list without repos exits 0", got == 0)
        check("(d4) list without repos prints no notice", lacks("gh:", out))
        ENV.pop("FAKE_GH_AUTH_FAIL", None)

    def test_150_e_list_prints_both_sources(self):
        """(e) list prints both sources without running"""
        qh, rec = fresh_home("e")
        proj = S.proj
        branchy = f"{SESSIONS}/2026-09-18-PAUL-21-branchy feat/PAUL-21-branchy"
        queue("PAUL-4", '"Move the picker"', "PAUL-20", branchy)
        write(f"{qh}/repos.txt", f"{proj}\n")
        write(f"{rec}/prs.txt", "11 feat/PAUL-9-thing https://github.com/e/r/pull/11\n")
        ENV["FAKE_GH_PRS"] = f"{rec}/prs.txt"
        out, got = mc("list")
        check("(e) list exits 0", got == 0)
        check("(e) list shows the ticket item", has(f"queue  {proj}  PAUL-4 (no plan)", out))
        check("(e) list shows the quoted topic", has(f'queue  {proj}  "Move the picker" (no plan)', out))
        check("(e) list finds the plan by ticket key", has(f"queue  {proj}  PAUL-20\n", out))
        check("(e) list finds the plan on the recorded branch", has(f"queue  {proj}  {branchy}\n", out))
        check("(e) list shows the labelled PR",
              has(f"pr     {proj}  #11 feat/PAUL-9-thing https://github.com/e/r/pull/11", out))
        check("(e) list did not start claude", not exists(f"{rec}/claude.args"))
        check("(e) list left queue.txt alone", live_lines(f"{qh}/queue.txt") == 4)
        ENV.pop("FAKE_GH_PRS", None)

    def test_160_f_add(self):
        """(f) add: quoting and branch detection"""
        qh, rec = fresh_home("f")
        proj = S.proj
        branchy = f"{SESSIONS}/2026-09-18-PAUL-21-branchy"
        mc("add", proj, "PAUL-5")
        mc("add", proj, "Move", "the", "picker", "into", "the", "composer")
        check("(f) add writes a plain item unquoted",
              grep_q(f"{proj} PAUL-5", f"{qh}/queue.txt", fixed=True, whole=True))
        check("(f) add quotes an item with spaces",
              grep_q(f'{proj} "Move the picker into the composer"', f"{qh}/queue.txt", fixed=True, whole=True))
        out, got = mc("add", f"{S.tmp}/nowhere", "X")
        check("(f) add refuses a non-repo (exit 1)", got == 1)
        check("(f) add names the reason", has("not a git repository", out))
        out, got = mc("add", proj, branchy)
        check("(f) add finds the branch holding a session dir absent from the checkout",
              grep_q(f"{proj} {branchy} feat/PAUL-21-branchy", f"{qh}/queue.txt", fixed=True, whole=True))
        check("(f) add prints the branch", has("feat/PAUL-21-branchy", out))
        mc("add", proj, f"{SESSIONS}/2026-09-18-PAUL-20-effort/")
        check("(f) add records the current branch for a session dir in the checkout",
              grep_q(f"{proj} {SESSIONS}/2026-09-18-PAUL-20-effort main", f"{qh}/queue.txt", fixed=True, whole=True))
        mc("add", proj, branchy, "feat/given")
        check("(f) add takes an explicit branch",
              grep_q(f"{proj} {branchy} feat/given", f"{qh}/queue.txt", fixed=True, whole=True))

    def test_170_f2_list_item_on_a_feature_branch(self):
        """(f2) a list item on a feature branch runs on that branch with its plan"""
        qh, rec = fresh_home("f2")
        branchy = f"{SESSIONS}/2026-09-18-PAUL-21-branchy"
        ENV["FAKE_SCENARIO"] = "report"
        mc("add", S.proj, branchy)
        out, got = mc("run")
        check("(f2) run exits 0", got == 0)
        check("(f2) done without no-plan",
              grep_q(f" {branchy} done https://github.com/e/r/pull/7$", f"{qh}/done.txt"))
        check("(f2) model opus and effort low taken from the plan on the branch",
              has("--model opus --effort low ", cat(f"{rec}/claude.args")))
        check("(f2) the run saw the branch history", grep_q("plan on branch", f"{rec}/claude.gitlog.1"))
        check("(f2) the run was on feat/PAUL-21-branchy", grep_q("PAUL-21-branchy", f"{qh}/done.txt"))

    def test_180_g_doctor_and_labels(self):
        """(g) doctor and labels"""
        qh, rec = fresh_home("g")
        proj = S.proj
        write(f"{qh}/repos.txt", f"{proj}\n")
        ENV["FAKE_SCENARIO"] = "notloggedin"
        out, got = mc("doctor")
        check("(g) doctor exits 1 when claude is not logged in", got == 1)
        check("(g) doctor explains the Keychain-over-SSH caveat", has("Keychain", out))
        ENV["FAKE_SCENARIO"] = "ok"
        write(f"{qh}/env", "SLACK_WEBHOOK_URL=x\n")
        os.chmod(f"{qh}/env", 0o644)
        out, got = mc("doctor")
        check("(g) doctor exits 1 on env mode 644", got == 1)
        check("(g) doctor names the wanted mode", has("want 600", out))
        os.chmod(f"{qh}/env", 0o600)
        out, got = mc("doctor")
        check("(g) doctor passes with login, gh, repo, labels, env 600", got == 0)
        check("(g) doctor reports all checks passed", has("all checks passed", out))
        check("(g) doctor checked the labels", has("label autopilot-blocked exists in proj", out))
        check("(g) doctor lists the repos", has("repos in the queue: 1", out))
        ENV["FAKE_GH_LABELS"] = "autopilot-ready"
        out, got = mc("labels", cwd=proj)
        check("(g) labels exits 0", got == 0)
        check("(g) labels keeps an existing label", has("label autopilot-ready exists in proj", out))
        check("(g) labels creates the missing ones", has("label autopilot-done created in proj", out))
        check("(g) labels uses the agreed colours",
              has("label create autopilot-blocked --color B60205", cat(f"{rec}/gh.args")))
        check("(g) labels uses the agreed colours (done)",
              has("label create autopilot-done --color 1D76DB", cat(f"{rec}/gh.args")))
        ENV["FAKE_GH_FAIL"] = "label create"
        out, got = mc("labels", proj)
        check("(g) labels exits 1 when a label cannot be created", got == 1)
        check("(g) labels names the failure", has("FAIL - label autopilot-done missing in proj", out))
        ENV.pop("FAKE_GH_FAIL", None)
        ENV.pop("FAKE_GH_LABELS", None)

    def test_190_h0_machine_without_a_queue(self):
        """(h0) machine without a queue: queue commands refuse with exit 3"""
        qh, rec = fresh_home("h0")
        shutil.rmtree(qh)
        for c in ("status", "list", "run", "add", "stop", "log", "kickstart"):
            out, got = mc(c, S.proj, "X")
            check(f"(h0) {c} refuses on a machine without the queue home (exit 3)", got == 3)
            check(f"(h0) {c} names the office Mini and /autopilot-plan", has("office Mini", out))
        check("(h0) no queue.txt was created by add", not exists(f"{qh}/queue.txt"))
        out, got = mc("retry", S.proj, "7")
        check("(h0) retry refuses too (exit 3)", got == 3)
        os.makedirs(qh)
        out, got = mc("status")
        check("(h0) status works once the queue home exists", got == 0)

    def test_200_h_lock(self):
        """(h) lock"""
        qh, rec = fresh_home("h")
        ENV["FAKE_SCENARIO"] = "report"
        queue("PAUL-6")
        os.makedirs(f"{qh}/run.lock")
        write(f"{qh}/run.lock/pid", f"{os.getpid()}\n")
        out, got = mc("run")
        check("(h) second run refused while the lock is held by a live pid", got == 1)
        check("(h) refusal names the lock", has("another run is active", out))
        check("(h) refused run did not start claude", not exists(f"{rec}/claude.args"))
        write(f"{qh}/run.lock/pid", "999999\n")
        out, got = mc("run")
        check("(h) stale lock (dead pid) is taken over", got == 0)
        check("(h) lock released after the run", not exists(f"{qh}/run.lock"))

    def test_210_i_notifications(self):
        """(i) no secret printed, curl failure logged with its exit code"""
        qh, rec = fresh_home("i")
        proj = S.proj
        ENV["FAKE_SCENARIO"] = "report"
        ENV.pop("MISSION_CONTROL_NO_NOTIFY", None)
        secret = "https://hooks.slack.com/services/T000/B000/SECRETXYZ"
        write(f"{qh}/env", f"SLACK_WEBHOOK_URL={secret}\n")
        os.chmod(f"{qh}/env", 0o600)
        fakes = {"PATH": f"{S.fakes}:{ENV['PATH']}"}
        queue("PAUL-7")
        out, got = mc("run", env=fakes)
        check("(i) run exits 0 with notifications on", got == 0)
        check("(i) Slack webhook was called", has("SECRETXYZ", cat(f"{rec}/curl.args")))
        check("(i) macOS notification was sent", has("PAUL-7: done", cat(f"{rec}/osascript.args")))
        check("(i) done notification plays Glass", has('sound name "Glass"', cat(f"{rec}/osascript.args")))
        queue("PAUL-7b")
        out, got = mc("run", env=dict(fakes, FAKE_SCENARIO="report-blocked"))
        check("(i) blocked notification carries the reason and plays Sosumi",
              has("PAUL-7b: blocked: cannot reach the API", "\n".join(grep("Sosumi", read(f"{rec}/osascript.args")))))
        check("(i) stdout never contains the webhook URL", lacks("SECRETXYZ", out))
        check("(i) logs never contain the webhook URL",
              lacks("SECRETXYZ", "".join(read(path) for path in ls(f"{qh}/logs/*.log"))))
        queue("PAUL-8")
        out, got = mc("run", env=dict(fakes, FAKE_CURL_EXIT="22"))
        check("(i) curl failure logged with its exit code",
              grep_q("Slack webhook failed (curl exit 22)", *ls(f"{qh}/logs/*-PAUL-8.log")))
        # Slack at the start and a detailed message at the end
        write(f"{rec}/curl.args", "")
        queue("PAUL-7c")
        out, got = mc("run", env=dict(fakes, FAKE_SCENARIO="report-full"))
        slack = cat(f"{rec}/curl.args")
        check("(i) Slack at the start: title, model and effort",
              has(f"*Autopilot started* on {S.host}: proj - PAUL-7c", slack))
        check("(i) Slack at the start: model and effort", has("Model sonnet, effort xhigh", slack))
        check("(i) Slack at the end: status and title", has("*Autopilot done*: proj - PAUL-7c", slack))
        check("(i) Slack at the end: PR link, minutes and cost",
              has("https://github.com/e/r/pull/7 · 0 min · $0.10", slack))
        check("(i) Slack at the end: what shipped, Markdown bold as Slack bold", has("- *greet* helper with", slack))
        check("(i) Slack at the end: at most 8 shipped lines, the rest counted", has("(2 more in REPORT.md)", slack))
        check("(i) Slack at the end: the ninth shipped line is not listed", lacks("shipped line 9", slack))
        check("(i) Slack at the end: open items", has("- ask Markus about the copy", slack))
        check("(i) Slack at the end: other report sections stay out", lacks("gate green", slack))
        write(f"{rec}/curl.args", "")
        queue("PAUL-7d")
        out, got = mc("run", env=dict(fakes, FAKE_SCENARIO="report-blocked-open"))
        slack = cat(f"{rec}/curl.args")
        check("(i) Slack when blocked: status, reason and open items",
              has("*Autopilot blocked*: proj - PAUL-7d", slack) and has("Reason: gate needs a database", slack)
              and has("- start Postgres on the Mini", slack))
        check("(i) Slack when blocked: no what-shipped section", lacks("*What shipped*", slack))
        # a PR item: the PR's title and, from the plan, what it is about
        plan_branch("feat/PAUL-220-export", "main", "2026-09-26-PAUL-220-export",
                    "# PLAN - Export button - 2026-09-26\nBranch: feat/PAUL-220-export   Base: main   Ticket: none\n\n"
                    "## Destination\nUsers export the report as CSV\nfrom /reports.\n\n## Goal artifact\nx\n",
                    "export plan")
        write(f"{rec}/prs.txt", "21 feat/PAUL-220-export https://github.com/e/r/pull/21\n")
        write(f"{qh}/repos.txt", f"{proj}\n")
        write(f"{rec}/curl.args", "")
        out, got = mc("run", env=dict(fakes, FAKE_GH_PRS=f"{rec}/prs.txt",
                                      FAKE_PR_TITLE="WEB-9: CSV export on /reports <Select> & co"))
        slack = cat(f"{rec}/curl.args")
        check("(i) PR item: Slack start with the PR's title, escaped",
              has(f"*Autopilot started* on {S.host}: proj - WEB-9: CSV export on /reports &lt;Select&gt; &amp; co",
                  slack))
        check("(i) PR item: what it is about, from the plan's Destination",
              has("Users export the report as CSV from /reports.", slack))
        check("(i) PR item: the PR link at the start", has("effort xhigh · https://github.com/e/r/pull/21", slack))
        write(f"{rec}/repos.txt", "")
        remove(f"{qh}/repos.txt")
        # the plan's topic when there is no PR title, and a valid JSON payload
        topic = f"{SESSIONS}/2026-09-26-PAUL-221-topic"
        plan_branch("feat/PAUL-221-topic", "main", "2026-09-26-PAUL-221-topic",
                    '# PLAN - Quote "fix" - 2026-09-26\nBranch: feat/PAUL-221-topic   Base: main   Ticket: none\n',
                    "topic plan")
        mc("add", proj, topic, "feat/PAUL-221-topic")
        write(f"{rec}/curl.args", "")
        out, got = mc("run", env=dict(fakes, FAKE_SCENARIO="report-full", FAKE_GH_NO_PR="1"))
        payloads = [m.group(1) for recorded in lines_of(read(f"{rec}/curl.args"))
                    for m in re.finditer(r"--data (\{.*\}) https://hooks", recorded)]
        check("(i) plan topic as the title when there is no PR",
              has('proj - Quote \\"fix\\"',
                  "\n".join(grep("Autopilot started", read(f"{rec}/curl.args"), fixed=True))))
        try:
            text = json.loads(payloads[-1])["text"]
            valid = "\n*What shipped*\n" in text and '"quotes"' in text and "back\\slash" in text
        except (IndexError, ValueError, KeyError, TypeError):
            valid = False
        check("(i) the Slack payload is valid JSON with newlines, quotes and a backslash", valid)
        # Slack-safe text: escaping, links, umlauts cut by characters, control characters,
        # heading variants
        write(f"{rec}/curl.args", "")
        queue("PAUL-7e")
        out, got = mc("run", env=dict(fakes, FAKE_SCENARIO="report-edge"))
        msg, got = slack_message(f"{rec}/curl.args", "Autopilot done")
        check("(i) the end message is valid JSON and UTF-8", got == 0)
        check("(i) <, > and & escaped, a Markdown link in Slack form",
              has("ping &lt;!channel&gt; &amp; see <https://x.y/z?a=1&amp;b=2|docs>", msg))
        umlauts = [x for x in msg.splitlines() if x.startswith("- ää")]
        check("(i) the umlaut line cut to 220 characters, not inside a character",
              bool(umlauts) and len(umlauts[0]) == 220)
        check('(i) "## Open Items:" with CRLF found', has("*Open items*\n- none left", msg))
        check("(i) the escape character is dropped", has("- esc [31mred[0m end", msg))
        write(f"{rec}/curl.args", "")
        queue("PAUL-7f")
        out, got = mc("run", env=dict(fakes, LC_ALL="de_DE.UTF-8", FAKE_SCENARIO="report"))
        check("(i) a German locale still writes the cost with a point", has("· $0.10", cat(f"{rec}/curl.args")))
        write(f"{rec}/curl.args", "")
        queue("PAUL-7g")
        out, got = mc("run", env=dict(fakes, FAKE_SCENARIO="sleep", FAKE_GH_NO_PR="1",
                                      MISSION_CONTROL_TIMEOUT_MIN="0.02"))
        slack = cat(f"{rec}/curl.args")
        check("(i) timeout: status, reason and the stopped attempt in Slack",
              has("*Autopilot timeout*: proj - PAUL-7g", slack) and has("Reason: wall-clock timeout", slack)
              and has("+ a stopped attempt", slack))
        check("(i) no PR: the log instead of a PR link", has(f"log {qh}/logs/", slack))
        kill9(pid_in(f"{rec}/claude.pid"))
        ENV["MISSION_CONTROL_NO_NOTIFY"] = "1"

    def test_220_j_reused_worktree(self):
        """(j) reused worktree: fetch and fast-forward before the retry"""
        qh, rec = fresh_home("j")
        proj, devclone = S.proj, f"{S.tmp}/devclone"
        ENV["FAKE_SCENARIO"] = "report-blocked"
        mc("add", proj, PAUL9, "feat/PAUL-9-thing")
        out, got = mc("run")
        wt = f"{proj}/.claude/worktrees/autopilot-2026-09-19-PAUL-9-thing"
        check("(j) first run blocked, worktree kept", exists(f"{wt}/.git"))
        git("-C", proj, "push", "-q", "origin", "feat/PAUL-9-thing")   # the run's commit, as the real run would push it
        git("clone", "-q", S.origin, devclone)
        git("-C", devclone, "checkout", "-q", "feat/PAUL-9-thing")
        commit(devclone, "--allow-empty", "-m", "developer fix")
        git("-C", devclone, "push", "-q", "origin", "feat/PAUL-9-thing")
        mc("add", proj, PAUL9, "feat/PAUL-9-thing")
        out, got = mc("run")
        write(f"{rec}/wt.gitlog", git_out("-C", wt, "log", "--oneline", "-5") + "\n")
        check("(j) retry fast-forwarded the reused worktree to the developer's push",
              grep_q("developer fix", f"{rec}/wt.gitlog"))
        check("(j) the run saw the developer fix", grep_q("developer fix", f"{rec}/claude.gitlog.2"))
        check("(j) no fast-forward complaint", lacks("not fast-forwardable", out))
        commit(wt, "--allow-empty", "-m", "local divergence")
        commit(devclone, "--allow-empty", "-m", "another fix")
        git("-C", devclone, "push", "-q", "origin", "feat/PAUL-9-thing")
        mc("add", proj, PAUL9, "feat/PAUL-9-thing")
        out, got = mc("run")
        check("(j) diverged worktree: said, run continues",
              has("feat/PAUL-9-thing is not fast-forwardable to origin/feat/PAUL-9-thing, "
                  "continuing on the local state", out))
        check("(j) diverged worktree: item still processed", grep_c("PAUL-9-thing blocked", f"{qh}/done.txt") == 3)

    def test_230_j2_branch_checked_out_in_the_main_checkout(self):
        """(j2) the plan branch is checked out in the user's main checkout"""
        qh, rec = fresh_home("j2")
        proj = S.proj
        wt = f"{proj}/.claude/worktrees/autopilot-2026-09-19-PAUL-9-thing"
        ENV["FAKE_SCENARIO"] = "report-blocked"
        # worktrees live in the project, so the one (j) kept would be reused; this case needs a new one
        git("-C", proj, "worktree", "remove", "--force", wt)
        git("-C", proj, "checkout", "-q", "--ignore-other-worktrees", "feat/PAUL-9-thing")
        mc("add", proj, PAUL9, "feat/PAUL-9-thing")
        out, got = mc("run")
        check("(j2) run exits 0", got == 0)
        check("(j2) says where else the branch is checked out",
              has("branch feat/PAUL-9-thing is also checked out in ", out))
        check("(j2) names the other checkout and the rule",
              has("/proj; the run works on feat/PAUL-9-thing here, do not commit there until it is done", out))
        check("(j2) the worktree is on the branch, not detached",
              git_out("-C", wt, "symbolic-ref", "--short", "HEAD") == "feat/PAUL-9-thing")
        check("(j2) blocked as the fake run reports", grep_q(f" {PAUL9} blocked ", f"{qh}/done.txt"))
        git("-C", proj, "checkout", "-q", "main")

    def test_240_j3_jira(self):
        """(j3) jira: start before the first attempt, comment at the end, failures said"""
        qh, rec = fresh_home("j3")
        proj = S.proj
        ENV["FAKE_SCENARIO"] = "report"
        os.makedirs(f"{S.tmp}/jirahome", exist_ok=True)
        write(f"{S.tmp}/jirahome/env", "JIRA_SITE=x\nJIRA_EMAIL=y\nJIRA_TOKEN=z\n")
        jira = {"JIRA_BIN": f"{S.fakes}/jira", "JIRA_HOME": f"{S.tmp}/jirahome"}
        mc("add", proj, PAUL9, "feat/PAUL-9-thing")
        out, got = mc("run", env=jira)
        comment = f"{rec}/jira-comment.1"
        check("(j3) jira start called with the plan's ticket before the run",
              line(f"{rec}/jira.args", 1) == "start PAUL-9")
        check("(j3) jira start happened before claude",
              grep_q("start PAUL-9", f"{rec}/jira-at-claude-start.1", whole=True))
        check("(j3) jira comment called at the end", line(f"{rec}/jira.args", 2) == "comment PAUL-9 -")
        check("(j3) comment body: status, PR and the report head",
              grep_q("^Autopilot: done", comment) and grep_q("^PR: https://github.com/e/r/pull/7", comment)
              and grep_q("shipped", comment))
        check("(j3) comment body has no Markdown headings", not grep_q("^#", comment))
        check("(j3) done.txt has no jira-failed", not grep_q("jira-failed", f"{qh}/done.txt"))
        qh, rec = fresh_home("j3b")
        mc("add", proj, PAUL9, "feat/PAUL-9-thing")
        out, got = mc("run", env=dict(jira, FAKE_JIRA_FAIL="1"))
        check("(j3b) jira failure is said with jira's last line",
              has("jira start PAUL-9 failed: jira: HTTP 401", out))
        check("(j3b) the run still happened", count_lines(f"{rec}/claude.args") == 1)
        check("(j3b) done.txt marks jira-failed", grep_q(" jira-failed", f"{qh}/done.txt"))
        qh, rec = fresh_home("j3c")
        mc("add", proj, PAUL9, "feat/PAUL-9-thing")
        out, got = mc("run", env={"JIRA_BIN": f"{S.fakes}/jira", "JIRA_HOME": f"{S.tmp}/nojira"})
        check("(j3c) without a credentials file jira is not called", not exists(f"{rec}/jira.args"))
        check("(j3c) the log says why",
              grep_q("PAUL-9 not updated (no jira script or no", *ls(f"{qh}/logs/*-2026-09-19-PAUL-9-thing.log")))
        qh, rec = fresh_home("j3d")
        ENV["FAKE_SCENARIO"] = "report-blocked"
        mc("add", proj, PAUL9, "feat/PAUL-9-thing")
        out, got = mc("run", env=jira)
        comment = f"{rec}/jira-comment.1"
        check("(j3d) blocked: comment carries the status and the report head",
              grep_q("^Autopilot: blocked", comment) and grep_q("cannot reach the API", comment))

    def test_250_j4_review_bot_comments(self):
        """(j4) review-bot comments counted in done.txt when the repo has the review workflow"""
        qh, rec = fresh_home("j4")
        proj = S.proj
        ENV["FAKE_SCENARIO"] = "report"
        os.makedirs(f"{proj}/.github/workflows", exist_ok=True)
        write(f"{proj}/.github/workflows/claude-code-review.yml", "name: review\n")
        if git("-C", proj, "add", "-A") == 0:
            commit(proj, "-m", "review workflow")
        git("-C", proj, "push", "-q", "origin", "main")
        queue("PAUL-70")
        out, got = mc("run", env={"FAKE_REVIEW_INLINE": "claude[bot] claude[bot]",
                                  "FAKE_REVIEW_TOP": "andreas github-actions[bot]"})
        check("(j4) done.txt counts the comments not by the PR author",
              grep_q(" PAUL-70 done .* review-comments=3", f"{qh}/done.txt"))
        check("(j4) both bot threads unanswered",
              grep_q(" PAUL-70 done .* unanswered-review-comments=2", f"{qh}/done.txt"))
        check("(j4) unanswered comments are said",
              has("PAUL-70: 2 review-bot comment(s) on the PR have no reply from the run", out))
        queue("PAUL-72")
        out, got = mc("run", env={"FAKE_REVIEW_INLINE": "claude[bot]:1 claude[bot]:2 andreas>1 claude[bot]>1",
                                  "FAKE_REVIEW_TOP": ""})
        check("(j4) a thread with an author reply counts as answered; a bot follow-up does not",
              grep_q(" PAUL-72 done .* review-comments=3 unanswered-review-comments=1", f"{qh}/done.txt"))
        queue("PAUL-73")
        out, got = mc("run", env={"FAKE_REVIEW_INLINE": "claude[bot]:1 andreas>1", "FAKE_REVIEW_TOP": ""})
        check("(j4) all answered: no unanswered field",
              grep_q(" PAUL-73 done .* review-comments=1$", f"{qh}/done.txt"))
        check("(j4) all answered: nothing said", lacks("PAUL-73: ", "\n".join(grep("no reply", out))))
        queue("PAUL-71")
        out, got = mc("run", env={"FAKE_REVIEW_INLINE": "", "FAKE_REVIEW_TOP": "andreas"})
        check("(j4) zero bot comments: said on stdout",
              has("PAUL-71: no review-bot comment on the PR yet, check it", out))
        check("(j4) zero bot comments: recorded", grep_q(" PAUL-71 done .* review-comments=0", f"{qh}/done.txt"))
        # a developer's PR: the run answers from the queue machine's gh account, not as the PR author
        queue("PAUL-74")
        out, got = mc("run", env={"FAKE_PR_AUTHOR": "dev", "FAKE_GH_ME": "andreas",
                                  "FAKE_REVIEW_INLINE": "claude[bot]:1 andreas>1", "FAKE_REVIEW_TOP": "andreas"})
        check("(j4) developer PR: replies from the queue machine's account count as answered",
              grep_q(" PAUL-74 done .* review-comments=1$", f"{qh}/done.txt"))
        check("(j4) developer PR: nothing said about unanswered comments", lacks("no reply from the run", out))
        if git("-C", proj, "rm", "-q", "-r", ".github") == 0 and commit(proj, "-m", "remove review workflow") == 0:
            git("-C", proj, "push", "-q", "origin", "main")

    def test_260_k_timeout_kills_the_run(self):
        """(k) timeout kills the run"""
        qh, rec = fresh_home("k")
        ENV.update(FAKE_SCENARIO="sleep", MISSION_CONTROL_TIMEOUT_MIN="0.02")
        queue("PAUL-34")
        out, got = mc("run")
        cpid = pid_in(f"{rec}/claude.pid")
        check("(k) run exits 0", got == 0)
        check("(k) status timeout in done.txt", grep_q(" PAUL-34 timeout ", f"{qh}/done.txt"))
        check("(k) reason names the wall-clock timeout", has("wall-clock timeout of 0.02 min", out))
        check("(k) fake claude killed", gone(cpid))
        kill9(cpid)
        ENV["MISSION_CONTROL_TIMEOUT_MIN"] = "5"

    def test_270_l_env_precedence(self):
        """(l) env precedence: environment over env file over default; effort from the plan"""
        qh, rec = fresh_home("l")
        ENV["FAKE_SCENARIO"] = "report"
        write(f"{qh}/env", "MISSION_CONTROL_MODEL=haiku\nMISSION_CONTROL_EFFORT=xhigh\n"
                           "MISSION_CONTROL_FALLBACK_MODEL=sonnet\n")
        os.chmod(f"{qh}/env", 0o600)
        queue("PAUL-35")
        mc("run")
        check("(l) env file beats the default (model haiku, effort xhigh, fallback sonnet)",
              has("--model haiku --effort xhigh --advisor fable --fallback-model sonnet",
                  last_line(f"{rec}/claude.args")))
        queue("PAUL-35")
        mc("run", env={"MISSION_CONTROL_MODEL": "opus", "MISSION_CONTROL_EFFORT": "low"})
        check("(l) environment beats the env file", has("--model opus --effort low ", last_line(f"{rec}/claude.args")))
        queue("PAUL-20")
        mc("run")
        check("(l) Effort: high from PLAN.md beats the env file",
              has("--effort high ", last_line(f"{rec}/claude.args")))
        queue("PAUL-20")
        mc("run", env={"MISSION_CONTROL_EFFORT": "low"})
        check("(l) explicit environment effort beats PLAN.md", has("--effort low ", last_line(f"{rec}/claude.args")))
        remove(f"{qh}/env")
        queue("PAUL-36")
        mc("run")
        check("(l) defaults without env file (sonnet at xhigh)",
              has("--model sonnet --effort xhigh --advisor fable --fallback-model opus --permission-mode auto "
                  "--max-budget-usd 200 ", last_line(f"{rec}/claude.args")))

    def test_280_l2_model_from_the_plan(self):
        """(l2) model from the plan header, sonnet effort floor, fallback and budget"""
        qh, rec = fresh_home("l2")
        args = f"{rec}/claude.args"
        ENV["FAKE_SCENARIO"] = "report"
        queue("PAUL-160")
        out, got = mc("run")
        check("(l2) Model: opus from PLAN.md, its effort kept, no fallback, budget 400",
              has("--model opus --effort medium --advisor fable --permission-mode auto --max-budget-usd 400 ",
                  last_line(args)))
        check("(l2) the run line names the model", has("run (attempt 1, model opus, effort medium)", out))
        queue("PAUL-161")
        mc("run")
        check("(l2) Model: sonnet with Effort: medium runs at xhigh, fallback opus, budget 200",
              has("--model sonnet --effort xhigh --advisor fable --fallback-model opus --permission-mode auto "
                  "--max-budget-usd 200 ", last_line(args)))
        check("(l2) the raise is logged", grep_q("effort medium raised to xhigh", one(f"{qh}/logs/*-PAUL-161.log")))
        queue("PAUL-162")
        mc("run")
        check("(l2) Model: Sonnet with Effort: max keeps max", has("--model sonnet --effort max ", last_line(args)))
        queue("PAUL-160")
        mc("run", env={"MISSION_CONTROL_MODEL": "sonnet"})
        check("(l2) environment model beats the plan, the floor still applies",
              has("--model sonnet --effort xhigh ", last_line(args)))
        queue("PAUL-160")
        mc("run", env={"MISSION_CONTROL_BUDGET_USD": "30"})
        check("(l2) an explicit budget beats the per-model default",
              has("--model opus --effort medium --advisor fable --permission-mode auto --max-budget-usd 30 ",
                  last_line(args)))
        write(f"{qh}/env", "MISSION_CONTROL_FALLBACK_MODEL=fable\n")
        os.chmod(f"{qh}/env", 0o600)
        queue("PAUL-160")
        mc("run")
        check("(l2) a fallback of another family is kept for an opus run",
              has("--model opus --effort medium --advisor fable --fallback-model fable ", last_line(args)))
        write(f"{qh}/env", "MISSION_CONTROL_FALLBACK_MODEL=opus,fable\n")
        queue("PAUL-160")
        mc("run")
        check("(l2) opus is dropped from a fallback list for an opus run",
              has("--model opus --effort medium --advisor fable --fallback-model fable --permission-mode",
                  last_line(args)))
        remove(f"{qh}/env")
        queue("PAUL-164")
        mc("run")
        check("(l2) markdown headers (- **Model:** `Opus`, **Effort:** High.) are read",
              has("--model opus --effort high ", last_line(args)))

    def test_290_l3_unknown_model_blocks(self):
        """(l3) an unknown Model: blocks the item before anything runs"""
        qh, rec = fresh_home("l3")
        write(f"{rec}/prs.txt", "14 feat/PAUL-163-bogus https://github.com/e/r/pull/14\n")
        ENV["FAKE_GH_PRS"] = f"{rec}/prs.txt"
        write(f"{qh}/repos.txt", f"{S.proj}\n")
        out, got = mc("run")
        check("(l3) an unknown Model: in the plan: run exits 0", got == 0)
        check("(l3) claude not started", not exists(f"{rec}/claude.args"))
        check("(l3) done.txt says blocked",
              grep_q(f" {SESSIONS}/2026-09-25-PAUL-163-bogus blocked https://github.com/e/r/pull/14$",
                     f"{qh}/done.txt"))
        check("(l3) the reason names the header line",
              has("PLAN.md header 'Model: gpt-5' is not sonnet or opus", out))
        check("(l3) the PR comment carries the reason",
              has("'Model: gpt-5' is not sonnet or opus", cat(f"{rec}/comment.1")))
        check("(l3) the PR is labelled blocked",
              has("pr edit 14 --remove-label autopilot-ready --add-label autopilot-blocked", cat(f"{rec}/gh.args")))
        ENV.pop("FAKE_GH_PRS", None)

    def test_300_m_no_pr_after_the_run(self):
        """(m) no PR found after the run"""
        qh, rec = fresh_home("m")
        ENV.update(FAKE_SCENARIO="report", FAKE_GH_NO_PR="1")
        queue("PAUL-137")
        out, got = mc("run")
        check("(m) run exits 0", got == 0)
        check("(m) done with - as the PR url", grep_q(" PAUL-137 done - no-plan$", f"{qh}/done.txt"))
        check("(m) no label or comment call without a PR", lacks("pr edit", cat(f"{rec}/gh.args")))
        check("(m) stdout says done (PR -)", has("PAUL-137: done (PR -", out))
        ENV.pop("FAKE_GH_NO_PR", None)

    def test_310_m2_refused_push_keeps_the_worktree(self):
        """(m2) a done run whose push is refused keeps its worktree

        PAUL-37's branch is on origin since (a2d); this run builds a different history on the
        same branch name, origin refuses the non-fast-forward, and the commits exist only
        locally."""
        qh, rec = fresh_home("m2")
        wt = f"{S.proj}/.claude/worktrees/autopilot-PAUL-37"
        ENV["FAKE_SCENARIO"] = "report"
        queue("PAUL-37")
        out, got = mc("run")
        check("(m2) the refused push is recorded", grep_q(" PAUL-37 done .*push-failed", f"{qh}/done.txt"))
        check("(m2) the worktree is kept, not removed", exists(f"{wt}/.git"))
        check("(m2) and it says why",
              has(f"PAUL-37: worktree kept at {wt} because its branch is not on origin", out))
        subjects = git_out("-C", S.origin, "log", "--format=%s", "feat/2026-09-20-PAUL-37")
        check("(m2) nothing was force-pushed", len(grep("^fake run", subjects)) != 1)
        git("-C", S.proj, "worktree", "remove", "--force", wt)

    def test_320_n_unparsable_queue_lines(self):
        """(n) unparsable queue lines are removed and named"""
        qh, rec = fresh_home("n")
        proj = S.proj
        ENV["FAKE_SCENARIO"] = "report"
        write(f"{qh}/queue.txt", f"{proj}\n{proj} PAUL-38\n")
        out, got = mc("run")
        check("(n) run exits 0", got == 0)
        check("(n) the unparsable line is named", has(f"removed unparsable line from queue.txt: {proj}", out))
        check("(n) the good line was processed", grep_q(" PAUL-38 done ", f"{qh}/done.txt"))
        check("(n) queue.txt emptied", live_lines(f"{qh}/queue.txt") == 0)

    def test_330_o_env_file_mode_warning(self):
        """(o) env file mode warning on run and list"""
        qh, rec = fresh_home("o")
        ENV["FAKE_SCENARIO"] = "report"
        write(f"{qh}/env", "MISSION_CONTROL_BUDGET_USD=5\n")
        os.chmod(f"{qh}/env", 0o644)
        queue("PAUL-39")
        out, got = mc("list")
        check("(o) list warns once about the env mode", len(grep("has mode 644, want 600", out)) == 1)
        check("(o) list still exits 0", got == 0)
        out, got = mc("run")
        check("(o) run warns about the env mode and continues", has("has mode 644, want 600", out))
        check("(o) run still used the env file", has("--max-budget-usd 5 ", cat(f"{rec}/claude.args")))
        check("(o) run exits 0", got == 0)

    def test_340_p_label_failure_after_the_run(self):
        """(p) gh label or comment failure after the run -> labels-failed"""
        qh, rec = fresh_home("p")
        ENV.update(FAKE_SCENARIO="report", FAKE_GH_FAIL="pr edit")
        queue("PAUL-40")
        out, got = mc("run")
        check("(p) run exits 0", got == 0)
        check("(p) done.txt records done with labels-failed",
              grep_q(" PAUL-40 done https://github.com/e/r/pull/7 no-plan labels-failed$", f"{qh}/done.txt"))
        check("(p) the failure is said", has("PAUL-40: gh pr edit (labels) failed", out))
        check("(p) the final line shows done labels-failed", has("PAUL-40: done labels-failed (PR", out))
        check("(p) the comment was still attempted", has("pr comment 7 --body-file", cat(f"{rec}/gh.args")))
        ENV.pop("FAKE_GH_FAIL", None)

    def test_350_q_status_and_stop(self):
        """(q) status while a run is active, then stop"""
        qh, rec = fresh_home("q")
        proj = S.proj
        ENV["FAKE_SCENARIO"] = "sleep"
        fakehome = f"{S.tmp}/fakehome-q"
        os.makedirs(fakehome, exist_ok=True)
        home = {"HOME": fakehome}
        queue("PAUL-50", "PAUL-51", "PAUL-52", "PAUL-53")
        write(f"{qh}/repos.txt", f"{proj}\n")
        write(f"{rec}/prs.txt", "11 feat/PAUL-9-thing https://github.com/e/r/pull/11\n")
        ENV["FAKE_GH_PRS"] = f"{rec}/prs.txt"
        write(f"{qh}/done.txt", f"2026-09-19T20:00:00Z {proj} PAUL-40 done https://github.com/e/r/pull/40\n")
        runner = start_run(f"{rec}/out")
        wait_for(f"{rec}/claude.pid")
        time.sleep(0.5)
        out, got = mc("status", env=home)
        check("(q) status exits 0", got == 0)
        check("(q) status shows the running item with attempt and phase",
              has("running: proj PAUL-50 (attempt 1, since ", out))
        check("(q) status phase is the run line from the item log",
              has(", phase: run (attempt 1, model sonnet, effort xhigh)", out))
        check("(q) status: no package line for a ticket item", has("  package: none marked [~]", out))
        check("(q) status: run line before the hook wrote one", has("  run: no status line yet", out))
        check("(q) status: diff line", has("  diff since base: ", out))
        qwt = f"{proj}/.claude/worktrees/autopilot-PAUL-50"
        session = f"{SESSIONS}/2026-09-20-PAUL-50-x"
        os.makedirs(f"{qwt}/.claude", exist_ok=True)
        os.makedirs(f"{qwt}/{session}", exist_ok=True)
        write(f"{qwt}/.claude/.autopilot-status", "2026-09-20T22:00:00Z ctx=123456 tool=Edit\n")
        write(f"{qwt}/{session}/PLAN.md",
              "# PLAN\n### P1 [x] done thing\n### P2 [~] the current package\n### P3 [ ] later\n")
        write(f"{qwt}/new-file.txt", "new\n")
        write(f"{qh}/run.lock/current", f"proj\n{session}\n1\n{int(time.time())}\n{qh}/logs/x.log\n{qwt}\n")
        out, got = mc("status", env=home)
        check("(q) status: current package from PLAN.md", has("  package: P2 [~] the current package", out))
        check("(q) status: run line from the hook's status file",
              has("  run: 2026-09-20T22:00:00Z ctx=123456 tool=Edit", out))
        write(f"{qh}/run.lock/current", f"proj\nPAUL-50\n1\n{int(time.time())}\n{qh}/logs/x.log\n{qwt}\n")
        check("(q) status counts the queue", has("queue: 4 items", out))
        check("(q) status lists the next three lines only", len(grep(f"^  {proj} PAUL-5", out)) == 3)
        check("(q) status counts the labelled PRs per repo", has("labelled PRs: 1 (proj 1)", out))
        check("(q) status shows the last done lines", has(f"  2026-09-19T20:00:00Z {proj} PAUL-40 done", out))
        check("(q) status says no schedule", has("schedule: not installed", out))
        check("(q) status names the lock holder", has(f"lock: held by pid {runner.pid}", out))
        check("(q) status never prints the webhook variable", lacks("SLACK_WEBHOOK_URL", out))
        write_plist(fakehome, 22, 5)
        out, got = mc("status", env=home)
        check("(q) status reads the schedule time from the plist", has("schedule: installed at 22:05, active", out))
        out, got = mc("stop")
        cpid = pid_in(f"{rec}/claude.pid")
        runner.wait()
        check("(q) stop exits 0", got == 0)
        check("(q) stop reports stopped with repo and item", has("stopped proj PAUL-50", out))
        check("(q) stop killed the fake claude", gone(cpid))
        check("(q) lock released after stop", not exists(f"{qh}/run.lock"))
        kill9(cpid)
        out, got = mc("status", env=home)
        check("(q) status after stop: running none", has("running: none", out))
        check("(q) status after stop: lock free", has("lock: free", out))
        check("(q) the stopped item is still first in queue.txt",
              len(grep("PAUL-50", first_line(mc("list", stderr=False)[0]))) == 1)
        os.makedirs(f"{qh}/run.lock", exist_ok=True)
        write(f"{qh}/run.lock/pid", "999999\n")
        out, got = mc("status", env=home)
        check("(q) status with a stale lock exits 0", got == 0)
        check("(q) status with a stale lock: running none", has("running: none", out))
        check("(q) status names the stale lock", has("lock: stale (pid 999999 is dead", out))
        shutil.rmtree(f"{qh}/run.lock")
        out, got = mc("stop")
        check("(q) stop without a run says so", has("nothing running", out))
        check("(q) stop without a run exits 0", got == 0)
        ENV["FAKE_GH_FAIL"] = "pr list --label"
        out, got = mc("status", env=home)
        check("(q) status tolerates a gh failure with a FAIL line",
              has(f"FAIL - {proj}: gh pr list --label autopilot-ready failed", out))
        check("(q) status still exits 0 on a gh failure", got == 0)
        ENV.pop("FAKE_GH_FAIL", None)
        ENV.pop("FAKE_GH_PRS", None)

    def test_360_q2_stop_returns_within_seconds(self):
        """(q2) stop returns within seconds although the run loop sleeps 30 s"""
        qh, rec = fresh_home("q2")
        ENV.update(FAKE_SCENARIO="sleep", MISSION_CONTROL_WATCH_MIN="0.5")
        queue("PAUL-54")
        runner = start_run(f"{rec}/out")
        wait_for(f"{rec}/claude.pid")
        time.sleep(0.5)
        if DARWIN:
            fakehome = f"{S.tmp}/fakehome-q2"
            os.makedirs(fakehome, exist_ok=True)
            out, got = mc("kickstart", env={"HOME": fakehome})
            check("(q2) kickstart refuses while a run is active", got == 1)
            check("(q2) kickstart names the run",
                  has(f"a run is active (pid {runner.pid}, PAUL-54), stop it first", out))
        t0 = int(time.time())
        out, got = mc("stop")
        t1 = int(time.time())
        cpid = pid_in(f"{rec}/claude.pid")
        runner.wait()
        check("(q2) stop exits 0", got == 0)
        check("(q2) stop reports stopped with the item", has("stopped proj PAUL-54", out))
        check("(q2) stop returned within 5 s (sleep interrupted)", t1 - t0 <= 5)
        check("(q2) fake claude gone", gone(cpid))
        check("(q2) item still queued after stop", grep_q("PAUL-54", f"{qh}/queue.txt"))
        out, got = mc("log", "PAUL-54")
        check("(q2) log still finds the stopped item's log", got == 0)
        kill9(cpid)
        ENV["MISSION_CONTROL_WATCH_MIN"] = "0"

    def test_370_r_retry(self):
        """(r) retry: a PR gets its label back, an item is queued again"""
        qh, rec = fresh_home("r")
        proj, tmp = S.proj, S.tmp
        wt = f"{proj}/.claude/worktrees/autopilot-2026-09-19-PAUL-9-thing"
        ENV["FAKE_SCENARIO"] = "report-blocked"
        out, got = mc("retry", proj, "#41")
        check("(r) retry #pr exits 0", got == 0)
        check("(r) retry #pr swaps blocked for ready",
              has("pr edit 41 --remove-label autopilot-blocked --add-label autopilot-ready", cat(f"{rec}/gh.args")))
        check("(r) retry #pr says so", has("retry: PR #41 in proj labelled autopilot-ready again", out))
        out, got = mc("retry", proj, "42")
        check("(r) retry accepts a bare number",
              has("pr edit 42 --remove-label autopilot-blocked", cat(f"{rec}/gh.args")))
        ENV["FAKE_GH_FAIL"] = "pr edit"
        out, got = mc("retry", proj, "#43")
        check("(r) retry #pr exits 1 when gh fails", got == 1)
        check("(r) retry #pr names the failure with gh's first stderr line",
              has("gh pr edit 43 failed in proj: fake gh: failing on purpose", out))
        ENV.pop("FAKE_GH_FAIL", None)
        out, got = mc("retry", proj, "12abc")
        check("(r) retry treats a mixed argument as an item, not a PR",
              grep_q(f"{proj} 12abc", f"{qh}/queue.txt", fixed=True, whole=True))
        check("(r) retry did not label a PR for the mixed argument", lacks("pr edit 12abc", cat(f"{rec}/gh.args")))
        mc("add", proj, PAUL9, "feat/PAUL-9-thing")
        mc("run")
        check("(r) blocked run left its worktree", exists(f"{wt}/.git"))
        check("(r) queue empty before retry", live_lines(f"{qh}/queue.txt") == 0)
        # the branch the kept worktree is on; retry must record exactly that one
        wt_branch = git_out("-C", wt, "symbolic-ref", "--short", "HEAD")
        check("(r) the worktree is on a branch", wt_branch != "")
        out, got = mc("retry", proj, PAUL9)
        check("(r) retry item exits 0", got == 0)
        check("(r) retry item queues it with the worktree's branch",
              grep_q(f"{proj} {PAUL9} {wt_branch}", f"{qh}/queue.txt", fixed=True, whole=True))
        check("(r) retry item says added", has(f"added: {proj} {PAUL9} {wt_branch}", out))
        out, got = mc("retry", proj, "PAUL-31")
        check("(r) retry ticket key queues it", grep_q(f"{proj} PAUL-31", f"{qh}/queue.txt", fixed=True, whole=True))
        out, got = mc("retry", f"{tmp}/nowhere", "#1")
        check("(r) retry refuses a non-repo", got == 1)
        out, got = mc("retry", "~/proj", "PAUL-44", env={"HOME": tmp})
        check("(r) retry expands ~ in the repo path",
              grep_q(f"{proj} PAUL-44", f"{qh}/queue.txt", fixed=True, whole=True))
        out, got = mc("add", "~/proj", "PAUL-45", env={"HOME": tmp})
        check("(r) add expands ~ in the repo path",
              grep_q(f"{proj} PAUL-45", f"{qh}/queue.txt", fixed=True, whole=True))
        out, got = mc("add", "proj", "PAUL-46", env={"MISSION_CONTROL_PROJECTS": tmp})
        check("(r) add resolves a bare project name under the projects directory",
              grep_q(f"{proj} PAUL-46", f"{qh}/queue.txt", fixed=True, whole=True))
        out, got = mc("add", "nosuchproj", "PAUL-47", env={"MISSION_CONTROL_PROJECTS": tmp})
        check("(r) a bare name that resolves to nothing is refused", got == 1)
        check("(r) refusal names the argument", has("nosuchproj is not a git repository", out))
        out, got = mc("labels", "~/proj", env={"HOME": tmp})
        check("(r) labels expands ~ in the repo path", got == 0)

    def test_380_s_log(self):
        """(s) log: newest item log, or by substring"""
        qh, rec = fresh_home("s")
        ENV["FAKE_SCENARIO"] = "report"
        queue("PAUL-60")
        mc("run")
        time.sleep(1)
        queue("PAUL-61")
        mc("run")
        out, got = mc("log")
        check("(s) log exits 0", got == 0)
        check("(s) log names the newest item log", has(f"log: {qh}/logs/", out))
        check("(s) log picks the newest item", has("PAUL-61.log", first_line(out)))
        check("(s) log shows the log content", has("PAUL-61: done (PR", out))
        out, got = mc("log", "PAUL-60")
        check("(s) log <substring> exits 0", got == 0)
        check("(s) log <substring> names that file", has("PAUL-60.log", first_line(out)))
        check("(s) log <substring> shows that run", has("PAUL-60: done (PR", out))
        check("(s) log output is at most 41 lines", out.count("\n") + 1 <= 41)
        out, got = mc("log", "NOPE")
        check("(s) log with no match exits 1", got == 1)
        check("(s) log with no match says so", has("no item log with 'NOPE'", out))
        # hand-made logs: the timestamp part must never match, the item part matches by its safe name
        qh, rec = fresh_home("s2")
        os.makedirs(f"{qh}/logs", exist_ok=True)
        write(f"{qh}/logs/20261212-121212-PAUL-70.log", "2026-12-12T12:12:12Z proj PAUL-70: done\n")
        time.sleep(1)
        write(f"{qh}/logs/20261212-121213-_34-2026-09-19-PAUL-2801-export.log",
              "2026-12-12T12:12:13Z proj #34: resolving\n")
        out, got = mc("log", "#34")
        check("(s2) log '#34' finds the PR item's log", has("_34-2026-09-19-PAUL-2801-export.log", first_line(out)))
        out, got = mc("log", "PAUL-2801")
        check("(s2) log <ticket key> finds the run whose session dir contains the key",
              has("_34-2026-09-19-PAUL-2801-export.log", first_line(out)))
        out, got = mc("log", f"{SESSIONS}/2026-09-19-PAUL-2801-export")
        check("(s2) log <session dir> finds it too", got == 0)
        out, got = mc("log", "12")
        check("(s2) log 12 does not match the timestamp", got == 1)
        out, got = mc("log", "PAUL-70")
        check("(s2) log PAUL-70 finds the older log", has("20261212-121212-PAUL-70.log", first_line(out)))
        out, got = mc("bogus")
        check("(s) unknown command lists the new commands", has("status | stop | retry | log", out))
        out, got = mc("help")
        check("(s) usage mentions start", has("mission-control start", out))

    def test_390_t_pause(self):
        """(t) pause: scheduled runs skip, manual runs go on"""
        day = datetime.date.today()
        S.today = today = day.isoformat()
        S.yesterday = yesterday = (day - datetime.timedelta(days=1)).isoformat()
        S.in3days = in3days = (day + datetime.timedelta(days=3)).isoformat()
        qh, rec = fresh_home("t")
        ENV["FAKE_SCENARIO"] = "report"
        fakehome = f"{S.tmp}/fakehome-t"
        home = {"HOME": fakehome}
        write_plist(fakehome, 22, 0)
        out, got = mc("status", env=home)
        check("(t) status: schedule active without a pause file", has("schedule: installed at 22:00, active", out))
        out, got = mc("pause", env=home)
        check("(t) pause exits 0", got == 0)
        check("(t) pause says paused until today", out == f"paused until {today}")
        check("(t) pause file holds today's date", cat(f"{qh}/paused") == today)
        out, got = mc("status", env=home)
        check("(t) status: schedule paused until today, nothing after the date",
              bool(grep(f"schedule: installed at 22:00, paused until {today}", out, whole=True)))
        check("(t) status: the date appears once on the schedule line", len(grep(today + today, out)) == 0)
        queue("PAUL-80")
        out, got = mc("run", "--scheduled")
        check("(t) scheduled run exits 0 while paused", got == 0)
        check("(t) scheduled run says it skipped",
              has(f"paused until {today}: scheduled run skipped (manual runs still work)", out))
        check("(t) scheduled run logged the skip",
              grep_q(f"paused until {today}: scheduled run skipped", f"{qh}/logs/queue.log"))
        check("(t) scheduled run left the queue alone", live_lines(f"{qh}/queue.txt") == 1)
        check("(t) scheduled run did not start claude", not exists(f"{rec}/claude.args"))
        check("(t) scheduled run did not take the lock", not exists(f"{qh}/run.lock"))
        out, got = mc("run")
        check("(t) manual run exits 0 while paused", got == 0)
        check("(t) manual run processed the item", grep_q(" PAUL-80 done ", f"{qh}/done.txt"))
        check("(t) manual run kept the pause", cat(f"{qh}/paused") == today)
        out, got = mc("resume", env=home)
        check("(t) resume exits 0", got == 0)
        check("(t) resume says resumed", out == "resumed")
        check("(t) resume removed the file", not exists(f"{qh}/paused"))
        out, got = mc("resume", env=home)
        check("(t) resume without a pause exits 0", got == 0)
        check("(t) resume without a pause says not paused", out == "not paused")
        # expired pause: removed, run proceeds
        write(f"{qh}/paused", f"{yesterday}\n")
        queue("PAUL-81")
        out, got = mc("run", "--scheduled")
        check("(t) expired pause: scheduled run exits 0", got == 0)
        check("(t) expired pause: item processed", grep_q(" PAUL-81 done ", f"{qh}/done.txt"))
        check("(t) expired pause: file removed", not exists(f"{qh}/paused"))
        check("(t) expired pause: logged",
              grep_q(f"pause expired ({yesterday}), file removed", f"{qh}/logs/queue.log"))
        out, got = mc("status", env=home)
        check("(t) status: active again after the expired pause", has("schedule: installed at 22:00, active", out))
        # unreadable pause file (empty, garbage): removed and said, run proceeds
        for junk in ("", "garbage"):
            write(f"{qh}/paused", junk)
            queue("PAUL-81")
            out, got = mc("run", "--scheduled")
            shown = junk or "empty"
            check(f"(t) unreadable pause '{shown}': scheduled run exits 0", got == 0)
            check(f"(t) unreadable pause '{shown}': said on stdout",
                  has(f"[mission-control] pause file unreadable ({shown}), removed, run goes ahead", out))
            check(f"(t) unreadable pause '{shown}': logged",
                  grep_q(f"pause file unreadable ({shown}), removed, run goes ahead", f"{qh}/logs/queue.log"))
            check(f"(t) unreadable pause '{shown}': not called expired", lacks(f"expired ({shown})", out))
            check(f"(t) unreadable pause '{shown}': file removed", not exists(f"{qh}/paused"))
            check(f"(t) unreadable pause '{shown}': item processed", grep_q(" PAUL-81 done ", f"{qh}/done.txt"))
        check("(t) unreadable pause: run went ahead both times", grep_c(" PAUL-81 done ", f"{qh}/done.txt") == 3)
        # pause until <date>, pause <N>d, invalid dates, a date in the past
        out, got = mc("pause", "until", "2099-12-31", env=home)
        check("(t) pause until exits 0", got == 0)
        check("(t) pause until says the date", out == "paused until 2099-12-31")
        check("(t) pause until writes the date", cat(f"{qh}/paused") == "2099-12-31")
        out, got = mc("pause", "until", today, env=home)
        check("(t) pause until today is allowed", got == 0)
        out, got = mc("pause", "3d", env=home)
        check("(t) pause 3d exits 0", got == 0)
        check("(t) pause 3d says the date three days ahead", out == f"paused until {in3days}")
        check("(t) pause 3d writes that date", cat(f"{qh}/paused") == in3days)
        out, got = mc("pause", "until", yesterday, env=home)
        check("(t) pause until <yesterday> exits 2", got == 2)
        check("(t) pause until <yesterday> says the date is in the past",
              out == f"mission-control: date is in the past: {yesterday}")
        check("(t) pause until <yesterday> left the previous pause untouched", cat(f"{qh}/paused") == in3days)
        pause_usage = "usage: mission-control pause [until <YYYY-MM-DD> | <N>d]"
        for bad, want in (("until 2026-02-30", "not a date: '2026-02-30' (want YYYY-MM-DD"),
                          ("until 31.12.2026", "not a date: '31.12.2026' (want YYYY-MM-DD"),
                          ("until yesterday", "not a date: 'yesterday' (want YYYY-MM-DD"),
                          ("until", f"{pause_usage} (got: until)"),
                          ("3", f"{pause_usage} (got: 3)"),
                          ("x3d", f"{pause_usage} (got: x3d)"),
                          ("3d extra", pause_usage)):
            out, got = mc("pause", *bad.split(), env=home)
            check(f"(t) pause {bad} exits 2", got == 2)
            check(f"(t) pause {bad} names the problem", has(f"mission-control: {want}", out))
        check("(t) an invalid pause left the previous pause untouched", cat(f"{qh}/paused") == in3days)
        # force-once: consumed by the scheduled run, overrides the pause once
        write(f"{qh}/force-once", "")
        queue("PAUL-82")
        out, got = mc("run", "--scheduled")
        check("(t) force-once: scheduled run exits 0", got == 0)
        check("(t) force-once: item processed despite the pause", grep_q(" PAUL-82 done ", f"{qh}/done.txt"))
        check("(t) force-once: file consumed", not exists(f"{qh}/force-once"))
        check("(t) force-once: pause still in place", cat(f"{qh}/paused") == in3days)
        queue("PAUL-83")
        out, got = mc("run", "--scheduled")
        check("(t) the next scheduled run is paused again",
              has(f"paused until {in3days}: scheduled run skipped", out))
        check("(t) the next scheduled run left the item queued", live_lines(f"{qh}/queue.txt") == 1)
        out, got = mc("run", "--bogus")
        check("(t) run rejects an unknown flag with exit 2", got == 2)
        out, got = mc("bogus")
        check("(t) unknown command lists pause and resume", has("pause | resume", out))
        out, got = mc("help")
        check("(t) usage mentions pause", has("pause", out))

    @unittest.skipUnless(DARWIN, "LaunchAgents exist on macOS only")
    def test_400_t2_install_schedule_and_start(self):
        """(t2) install-schedule writes run --scheduled; kickstart writes force-once"""
        script(f"{S.fakes}/launchctl", FAKE_LAUNCHCTL)
        qh, rec = fresh_home("t2")
        fakehome = f"{S.tmp}/fakehome-t2"
        os.makedirs(fakehome, exist_ok=True)
        plist = f"{fakehome}/Library/LaunchAgents/de.evelan.mission-control.plist"
        scheduled = "<string>run</string><string>--scheduled</string>"
        mac = {"HOME": fakehome, "PATH": f"{S.fakes}:{ENV['PATH']}"}
        out, got = mc("install-schedule", "22:00", env=mac)
        check("(t2) install-schedule exits 0", got == 0)
        check("(t2) plist written under the temporary HOME", os.path.isfile(plist))
        check("(t2) plist runs mission-control run --scheduled", grep_q(scheduled, plist))
        check("(t2) plist carries the time",
              grep_q("<key>Hour</key><integer>22</integer><key>Minute</key><integer>0</integer>", plist))
        la = cat(f"{rec}/launchctl.args")
        check("(t2) install-schedule boots out, then bootstraps", len(grep(".", la)) == 2)
        check("(t2) bootout first", has("bootout gui/", first_line(la)))
        check("(t2) bootstrap second", has("bootstrap gui/", "\n".join(la.split("\n")[1:2])))
        check("(t2) only the fake launchctl was called (no real launchd)", lacks("kickstart", la))
        out, got = mc("install-schedule", "23:30", env=mac)
        check("(t2) re-running install-schedule replaces the plist",
              grep_q("<key>Hour</key><integer>23</integer><key>Minute</key><integer>30</integer>", plist))
        check("(t2) re-run booted out and bootstrapped again", grep_c(".", f"{rec}/launchctl.args") == 4)
        mc("pause")
        out, got = mc("kickstart", env=mac)
        check("(t2) kickstart exits 0 during a pause", got == 0)
        check("(t2) kickstart called launchctl kickstart", has("kickstart gui/", last_line(f"{rec}/launchctl.args")))
        check("(t2) kickstart wrote force-once", exists(f"{qh}/force-once"))
        check("(t2) kickstart says the pause is overridden once",
              has(f"the pause until {S.today} is overridden for this run only", out))
        ENV["FAKE_SCENARIO"] = "report"
        queue("PAUL-84")
        out, got = mc("run", "--scheduled")
        check("(t2) the kickstarted scheduled run processed the item", grep_q(" PAUL-84 done ", f"{qh}/done.txt"))
        check("(t2) force-once consumed by that run", not exists(f"{qh}/force-once"))
        remove(plist)
        write(f"{rec}/launchctl.args", "")
        out, got = mc("start", env=mac)
        check("(t2) start without a schedule exits 0", got == 0)
        check("(t2) start installed the LaunchAgent on demand", os.path.isfile(plist))
        check("(t2) on-demand plist has no StartCalendarInterval", not grep_q("StartCalendarInterval", plist))
        check("(t2) on-demand plist still runs run --scheduled", grep_q(scheduled, plist))
        check("(t2) start booted out, bootstrapped, then kickstarted",
              "".join(x.split(" ")[0] + " " for x in lines_of(read(f"{rec}/launchctl.args"))[:3])
              == "bootout bootstrap kickstart ")
        check("(t2) start wrote force-once", exists(f"{qh}/force-once"))
        check("(t2) start says where the output goes",
              has("started: de.evelan.mission-control runs now in the GUI session", out))
        out, got = mc("status", env=mac)
        check("(t2) status shows the on-demand schedule",
              has('schedule: on demand only ("mission-control start"), no nightly run', out))
        remove(f"{qh}/force-once")
        os.makedirs(f"{qh}/run.lock", exist_ok=True)
        write(f"{qh}/run.lock/pid", f"{os.getpid()}\n")
        out, got = mc("start", env=mac)
        check("(t2) start during a run exits 1", got == 1)
        check("(t2) refused start (active run) wrote no force-once", not exists(f"{qh}/force-once"))
        out, got = mc("kickstart", env=mac)
        check("(t2) kickstart is an alias of start (refused the same way)", got == 1)
        shutil.rmtree(f"{qh}/run.lock")

    def test_410_t3_legacy_plist(self):
        """(t3) legacy plist (no --scheduled): pause, resume and status warn"""
        qh, rec = fresh_home("t3")
        today = S.today
        fakehome = f"{S.tmp}/fakehome-t3"
        home = {"HOME": fakehome}
        write_plist(fakehome, 21, 15, legacy=True)
        legacy_warn = ('schedule installed without --scheduled: run "mission-control install-schedule 21:15" again, '
                       "otherwise the nightly job ignores the pause")
        out, got = mc("status", env=home)
        check("(t3) status exits 0 with a legacy plist", got == 0)
        check("(t3) status shows the legacy schedule line",
              has("schedule: installed at 21:15 (legacy, ignores pause)", out))
        check("(t3) status prints the warning with the plist time", has(legacy_warn, out))
        out, got = mc("pause", env=home)
        check("(t3) pause exits 0 with a legacy plist", got == 0)
        check("(t3) pause still writes the file", cat(f"{qh}/paused") == today)
        check("(t3) pause says paused", has(f"paused until {today}", out))
        check("(t3) pause prints the warning", has(legacy_warn, out))
        out, got = mc("status", env=home)
        check("(t3) status with a legacy plist and a pause still says legacy",
              has("schedule: installed at 21:15 (legacy, ignores pause)", out))
        check("(t3) status with a legacy plist never says paused until", lacks("paused until", out))
        out, got = mc("resume", env=home)
        check("(t3) resume exits 0 with a legacy plist", got == 0)
        check("(t3) resume says resumed", has("resumed", out))
        check("(t3) resume prints the warning", has(legacy_warn, out))
        write_plist(fakehome, 21, 15)
        out, got = mc("pause", env=home)
        check("(t3) a plist with --scheduled gets no warning from pause", out == f"paused until {today}")
        out, got = mc("status", env=home)
        check("(t3) a plist with --scheduled gets no warning from status", lacks("without --scheduled", out))
        remove(f"{fakehome}/Library/LaunchAgents/de.evelan.mission-control.plist")
        out, got = mc("resume", env=home)
        check("(t3) no plist: no warning from resume", out == "resumed")

    def test_420_v_pr_items_against_the_target_branch(self):
        """(v) PR items resolve their plan against the PR's target branch"""
        qh, rec = fresh_home("v")
        ENV["FAKE_SCENARIO"] = "report"
        write(f"{rec}/prs.txt", "16 feat/default-org-redirect https://github.com/e/r/pull/16 preview\n"
                                "17 feat/borrowed-plan https://github.com/e/r/pull/17 preview\n"
                                "18 feat/big https://github.com/e/r/pull/18 preview\n"
                                "19 feat/PAUL-190-new https://github.com/e/r/pull/19 preview\n"
                                "20 feat/tick https://github.com/e/r/pull/20 preview\n")
        ENV["FAKE_GH_PRS"] = f"{rec}/prs.txt"
        write(f"{qh}/repos.txt", f"{S.proj}\n")
        out, got = mc("run")
        cl = cat(f"{rec}/claude.args")
        check("(v) PR 16 runs its own plan", has(f"/autopilot {SESSIONS}/2026-09-23-default-org-redirect ", cl))
        check("(v) the finished session on preview is never run", lacks("2026-09-23-two-factor-auth", cl))
        check("(v) PR 16 done with its own session dir",
              grep_q(f" {SESSIONS}/2026-09-23-default-org-redirect done https://github.com/e/r/pull/16$",
                     f"{qh}/done.txt"))
        check("(v) PR 17 (its plan names another branch) not run", lacks("2026-09-24-borrowed", cl))
        check("(v) PR 17 blocked",
              grep_q(f" {SESSIONS}/2026-09-24-borrowed blocked https://github.com/e/r/pull/17$", f"{qh}/done.txt"))
        check("(v) the reason names both branches",
              has("belongs to branch feat/somewhere-else, not to the PR branch feat/borrowed-plan", out))
        check("(v) PR 17 labelled blocked",
              has("pr edit 17 --remove-label autopilot-ready --add-label autopilot-blocked", cat(f"{rec}/gh.args")))
        check("(v) PR 18 (a feature-branch session on its feature branch) runs",
              has(f"/autopilot {SESSIONS}/2026-09-24-big-s2 ", cl))
        check("(v) PR 19 runs its own plan, not the older one with the ticket key",
              has(f"/autopilot {SESSIONS}/2026-09-24-new-work ", cl))
        check("(v) the older plan with the ticket key is never run", lacks("2026-09-01-PAUL-190-old", cl))
        check("(v) PR 20 (Branch: header with backticks and a comma) runs, not blocked",
              has(f"/autopilot {SESSIONS}/2026-09-24-tick ", cl))
        ENV.pop("FAKE_GH_PRS", None)

    def test_430_w_hooks_and_docker(self):
        """(w) hooks installed before the run; a run's Docker stack stopped afterwards"""
        qh, rec = fresh_home("w")
        proj = S.proj
        ENV["FAKE_SCENARIO"] = "report"
        queue("PAUL-200")
        wt200 = f"{proj}/.claude/worktrees/autopilot-PAUL-200"
        out, got = mc("run", env={"FAKE_DOCKER_PS": f"proj-paul-200|{wt200}\nproj-paul-200|{wt200}/docker/dev\n"
                                                    f"other-stack|/somewhere/else\nprefix-trap|{wt200}-other"})
        hooks_subject = "install or update the autopilot hooks"
        check("(w) the run saw the hooks installed and registered", grep_q("attempt 1", f"{rec}/hooks.seen"))
        check("(w) without a branch the hooks are not committed", grep_c(hooks_subject, f"{rec}/claude.gitlog.1") == 0)
        check("(w) without a branch: said",
              has("PAUL-200: autopilot hooks installed for this run, not committed (no branch yet)", out))
        check("(w) the run's compose project was stopped once, from /, with orphans",
              grep_c("^compose -p proj-paul-200 down --remove-orphans$", f"{rec}/docker.args") == 1)
        check("(w) another compose project was left alone", lacks("compose -p other-stack", cat(f"{rec}/docker.args")))
        check("(w) a worktree path that is only a prefix does not count",
              lacks("compose -p prefix-trap", cat(f"{rec}/docker.args")))
        check("(w) the main checkout got no hooks", not exists(f"{proj}/.claude/hooks/autopilot-gate.sh"))
        # a branch on origin without hooks: one commit with only the hook files, pushed
        plan_branch("feat/PAUL-202-nohooks", "main", "2026-09-26-PAUL-202-nohooks",
                    "# PLAN\nBranch: feat/PAUL-202-nohooks   Base: main   Ticket: none\n", "plan without hooks")
        mc("add", proj, f"{SESSIONS}/2026-09-26-PAUL-202-nohooks", "feat/PAUL-202-nohooks")
        out, got = mc("run")
        check("(w) on a branch the hooks are committed before the run",
              grep_q("chore(autopilot): install or update the autopilot hooks", f"{rec}/claude.gitlog.2"))
        check("(w) on a branch: said with the branch",
              has("autopilot hooks installed or updated and committed on feat/PAUL-202-nohooks", out))
        hooks_commit = git_out("-C", S.origin, "log", "--format=%H", "--grep", hooks_subject, "feat/PAUL-202-nohooks")
        check("(w) the hooks commit was pushed to origin", hooks_commit != "")
        names = git_out("-C", S.origin, "show", "--name-only", "--format=", hooks_commit) if hooks_commit else ""
        check("(w) the hooks commit holds only the hook files, settings and .gitignore",
              "".join(name + " " for name in sorted(lines_of(names)))
              == ".claude/hooks/autopilot-context-budget.sh .claude/hooks/autopilot-gate-filter.sh "
                 ".claude/hooks/autopilot-gate.sh .claude/hooks/autopilot-session-start.sh .claude/settings.json "
                 ".gitignore ")
        # a branch whose hooks are already current gets no commit
        git("-C", proj, "checkout", "-q", "-b", "feat/PAUL-201-hooked", "main")
        hooks_out = subprocess.run([os.path.join(HERE, "autopilot-hooks"), "install", proj], env=ENV,
                                   stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL).stdout.decode("utf-8", "replace")
        commit_and_push("hooks already there", "feat/PAUL-201-hooked")
        session_file("2026-09-26-PAUL-201-hooked", "PLAN.md",
                     "# PLAN\nBranch: feat/PAUL-201-hooked   Base: main   Ticket: none\n")
        commit_and_push("plan", "feat/PAUL-201-hooked")
        git("-C", proj, "checkout", "-q", "main")
        mc("add", proj, f"{SESSIONS}/2026-09-26-PAUL-201-hooked", "feat/PAUL-201-hooked")
        out, got = mc("run")
        check("(w) current hooks: no hooks commit", grep_c(hooks_subject, f"{rec}/claude.gitlog.3") == 0)
        check("(w) current hooks: logged as current",
              grep_q("autopilot hooks current", one(f"{qh}/logs/*-2026-09-26-PAUL-201-hooked.log")))
        check("(w) current hooks: the run saw them", grep_q("attempt 3", f"{rec}/hooks.seen"))
        check("(w) the setup helper reported its work", has("added .claude/hooks/autopilot-gate.sh", hooks_out))

    def test_440_x_nvm_node_on_the_path(self):
        """(x) the run gets the project's nvm Node on its PATH"""
        qh, rec = fresh_home("x")
        proj, nvm = S.proj, ENV["NVM_DIR"]
        ENV["FAKE_SCENARIO"] = "report"
        for version in ("v20.1.0", "v22.2.0", "v22.10.1", "v24.0.0"):
            os.makedirs(f"{nvm}/versions/node/{version}/bin", exist_ok=True)
        os.makedirs(f"{nvm}/alias", exist_ok=True)
        write(f"{nvm}/alias/default", "24\n")
        queue("PAUL-210")
        mc("run")
        check("(x) without .nvmrc: nvm's default alias (24)",
              cat(f"{rec}/claude.path.1") == f"{nvm}/versions/node/v24.0.0/bin")
        git("-C", proj, "checkout", "-q", "-b", "feat/PAUL-211-node", "main")
        write(f"{proj}/.nvmrc", "v22\n")
        session_file("2026-09-26-PAUL-211-node", "PLAN.md",
                     "# PLAN\nBranch: feat/PAUL-211-node   Base: main   Ticket: none\n")
        commit_and_push("node 22 plan", "feat/PAUL-211-node")
        git("-C", proj, "checkout", "-q", "main")
        mc("add", proj, f"{SESSIONS}/2026-09-26-PAUL-211-node", "feat/PAUL-211-node")
        mc("run")
        check("(x) .nvmrc v22: the highest installed 22.x (v22.10.1, not v22.2.0)",
              cat(f"{rec}/claude.path.2") == f"{nvm}/versions/node/v22.10.1/bin")
        check("(x) the Node choice is logged",
              grep_q(f"node for the run: {nvm}/versions/node/v22.10.1/bin",
                     one(f"{qh}/logs/*-2026-09-26-PAUL-211-node.log")))
        shutil.rmtree(nvm, ignore_errors=True)

    # (y) every run's branch reaches origin; worktrees live inside the project. A blocked run
    # whose commits sit in a worktree on one Mac only is invisible on GitHub and outside every
    # backup.

    def test_450_y1_legacy_worktree_moves_into_the_project(self):
        """(y1) a worktree an older runner kept under the queue home moves into the project"""
        qh, rec = fresh_home("y")
        proj = S.proj
        ENV["FAKE_SCENARIO"] = "report-blocked"
        git("-C", proj, "worktree", "add", "-q", "--detach", f"{qh}/worktrees/proj-PAUL-77", "main")
        queue("PAUL-77")
        out, got = mc("run")
        check("(y1) the old worktree moved into the project", exists(f"{proj}/.claude/worktrees/autopilot-PAUL-77/.git"))
        check("(y1) nothing left at the old place", not exists(f"{qh}/worktrees/proj-PAUL-77"))
        check("(y1) the move is said", has("PAUL-77: worktree moved into the project", out))
        check("(y1) and the run's branch pushed", on_origin("feat/2026-09-20-PAUL-77"))

    def test_460_y2_origin_refuses_the_push(self):
        """(y2) origin refuses the push: said, recorded, the work stays in the worktree"""
        qh, proj, origin = S.qh, S.proj, S.origin
        # The hooks live in the test repos' own hooks folders. A machine-wide core.hooksPath
        # would silently replace them, so each repo names its folder explicitly.
        git("-C", origin, "config", "core.hooksPath", f"{origin}/hooks")
        git("-C", proj, "config", "core.hooksPath", f"{proj}/.git/hooks")
        os.makedirs(f"{origin}/hooks", exist_ok=True)
        script(f"{origin}/hooks/pre-receive", HOOK_PRE_RECEIVE)
        check("(y2) sanity: origin really refuses such a branch",
              git("-C", proj, "push", "-q", "origin", "main:refs/heads/probe-PAUL-88") != 0)
        queue("PAUL-88")
        out, got = mc("run")
        remove(f"{origin}/hooks/pre-receive")
        check("(y2) the failed push is said", has("PAUL-88: pushing feat/2026-09-20-PAUL-88 to origin failed", out))
        check("(y2) done.txt marks push-failed", grep_q(" PAUL-88 blocked .*push-failed", f"{qh}/done.txt"))
        check("(y2) the branch is not on origin", not on_origin("feat/2026-09-20-PAUL-88"))
        check("(y2) the worktree keeps the commits", exists(f"{proj}/.claude/worktrees/autopilot-PAUL-88/.git"))

    def test_470_y3_pre_push_hook_is_skipped(self):
        """(y3) the project's own pre-push hook never keeps a blocked run off GitHub"""
        proj = S.proj
        os.makedirs(f"{proj}/.git/hooks", exist_ok=True)
        script(f"{proj}/.git/hooks/pre-push", HOOK_PRE_PUSH)
        check("(y3) sanity: the hook blocks a normal push",
              git("-C", proj, "push", "-q", "origin", "main:refs/heads/probe-hook") != 0)
        queue("PAUL-90")
        out, got = mc("run")
        remove(f"{proj}/.git/hooks/pre-push")
        git("-C", proj, "config", "--unset", "core.hooksPath")
        git("-C", S.origin, "config", "--unset", "core.hooksPath")
        check("(y3) pushed despite the failing pre-push hook", on_origin("feat/2026-09-20-PAUL-90"))

    def test_480_y4_base_branch_is_never_pushed(self):
        """(y4) a run that ends on a base branch is never pushed there"""
        qh, proj, origin = S.qh, S.proj, S.origin
        wt = f"{proj}/.claude/worktrees/autopilot-2026-09-27-PAUL-89-dev"
        plan_branch("develop", "main", "2026-09-27-PAUL-89-dev", "# PLAN\nBranch: develop   Base: main   Ticket: none\n",
                    "plan on develop")
        queue(f"{SESSIONS}/2026-09-27-PAUL-89-dev develop")
        out, got = mc("run")
        check("(y4) the run's work is not on origin's develop",
              not grep("^fake run", git_out("-C", origin, "log", "--format=%s", "develop")))
        # the hooks installed before the run are not committed on a base branch, so nothing of
        # the runner's reaches origin's develop either
        check("(y4) origin's develop did not move",
              git_out("-C", origin, "log", "-1", "--format=%s", "develop") == "plan on develop")
        check("(y4) no hooks commit on the local develop",
              not grep("install or update the autopilot hooks", git_out("-C", proj, "log", "--format=%s", "develop")))
        check("(y4) the hooks are in the worktree for the run",
              os.access(f"{wt}/.claude/hooks/autopilot-gate.sh", os.X_OK))
        check("(y4) hooks on a base branch: said",
              has("2026-09-27-PAUL-89-dev: autopilot hooks installed for this run, not committed "
                  "(base branch develop)", out))
        check("(y4) and it says why", has("ended on the base branch develop; not pushed", out))
        check("(y4) recorded as push-failed", grep_q("2026-09-27-PAUL-89-dev blocked .*push-failed", f"{qh}/done.txt"))
        check("(y4) the project checkout stays clean", is_main_clean())
        git("-C", proj, "worktree", "remove", "--force", wt)

    def test_490_y5_default_branch_with_another_name(self):
        """(y5) a default branch with another name (origin/HEAD points to it) counts as a base branch"""
        proj = S.proj
        plan_branch("trunk", "main", "2026-09-27-PAUL-91-trunk", "# PLAN\nBranch: trunk   Base: main   Ticket: none\n",
                    "plan on trunk")
        git("-C", proj, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk")
        queue(f"{SESSIONS}/2026-09-27-PAUL-91-trunk trunk")
        out, got = mc("run")
        git("-C", proj, "symbolic-ref", "-d", "refs/remotes/origin/HEAD")
        check("(y5) origin's default branch did not move",
              git_out("-C", S.origin, "log", "-1", "--format=%s", "trunk") == "plan on trunk")
        check("(y5) hooks on the default branch: said",
              has("2026-09-27-PAUL-91-trunk: autopilot hooks installed for this run, not committed "
                  "(base branch trunk)", out))
        check("(y5) the run's work is not pushed there", has("ended on the base branch trunk; not pushed", out))
        git("-C", proj, "worktree", "remove", "--force", f"{proj}/.claude/worktrees/autopilot-2026-09-27-PAUL-91-trunk")

    def test_500_y6_dev_is_a_base_branch(self):
        """(y6) dev is a base branch too"""
        proj = S.proj
        plan_branch("dev", "main", "2026-09-27-PAUL-92-dev", "# PLAN\nBranch: dev   Base: main   Ticket: none\n",
                    "plan on dev")
        queue(f"{SESSIONS}/2026-09-27-PAUL-92-dev dev")
        out, got = mc("run")
        check("(y6) origin's dev did not move",
              git_out("-C", S.origin, "log", "-1", "--format=%s", "dev") == "plan on dev")
        check("(y6) hooks on dev: said",
              has("2026-09-27-PAUL-92-dev: autopilot hooks installed for this run, not committed (base branch dev)",
                  out))
        check("(y6) the run's work is not pushed there", has("ended on the base branch dev; not pushed", out))
        git("-C", proj, "worktree", "remove", "--force", f"{proj}/.claude/worktrees/autopilot-2026-09-27-PAUL-92-dev")


if __name__ == "__main__":
    unittest.main()
