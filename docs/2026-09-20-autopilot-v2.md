# Autopilot v2: plan, run, queue (2026-09-20)

## Why

Plugin 1.7 to 1.11 built an orchestration layer (mission control as a coordinating model,
one lead agent per package, per-package reviewers, planner and plan-reviewer agents). Measured
on the WEB-1095 session in evelan-slides with corrected request counting: 33 agents, 1,795
requests, 275M cache reads, 6.8M cache writes, about $220 at list price for one ticket. The
coordinator alone was 28% (its context grew to 1.06M and was re-written three times after idle
gaps); fifteen lead starts and fifteen reviews were another 64%. Anthropic's guidance
(multi-agent research system write-up, agent-teams and cost docs) says the same thing the
numbers do: multi-agent setups pay off for parallel research, not for coding, where "few
tasks are truly parallelizable". Tools that coordinate many coding sessions (firstmate,
bernstein, NEEDLE, sortie, Claude Code's own `claude agents`) keep the model out of the
coordination loop: a watcher or a queue dispatches sessions and wakes a human only on events.

Andreas' original reason for mission control was to work through several tickets overnight.
That is a queue, not a coordinating model.

## The three blocks

1. **`/autopilot-plan`** (interactive, in the user's or a developer's session): resolves the
   ticket or spec, explores with bounded reads, asks the shape questions once, writes one
   `PLAN.md` (goal, goal artifact, decisions, packages with seams and verification criteria),
   commits it. Optional fresh-context plan review on request.
2. **`/autopilot`** (unattended, one context): gate, branch, per package test-first with the
   gate green and a commit, one adversarial review on the whole branch, the goal artifact
   exercised for real, `REPORT.md`, PR with CI watched. Hand-off through `HANDOFF.md` when the
   context-budget hook fires; a fresh session resumes. No implementer sub-agent, no
   orchestrated modes, no per-package reviews.
3. **`autopilot-queue`** (a script): runs prepared sessions one after another. Design below;
   format to be agreed with Andreas before it is built.

Removed in 2.0: `mission-control`, `autopilot-lead`, `autopilot-implementer`,
`autopilot-planner`. Kept: `autopilot-reviewer`, `autopilot-plan-reviewer`, the four hooks,
`autopilot-watchdog` (the queue's stall detector), `autopilot-usage`.

## Queue design (proposal)

**Input: a plain text file**, one item per line, in the repo that owns the queue or in
`~/.claude/autopilot-queue.txt`:

```
# repo                                  item
/Users/me/dev/projects/paul             docs/autopilot/sessions/2026-09-20-PAUL-2800-vvg-export
/Users/me/dev/projects/paul             PAUL-2801
/Users/me/dev/projects/evelan-slides    #142
/Users/me/dev/projects/evelan-slides    "Move the layout picker into the composer"
```

An item is a prepared session directory (preferred), a ticket key or GitHub issue number (the
run writes its own plan with conservative decisions), or a quoted topic. Lines starting with
`#` are comments. Items are processed top to bottom; a finished or blocked item is moved to
`autopilot-queue.done.txt` with its result line (branch, PR URL or blocker), so the queue file
always shows what is left.

**Per item** the script (`bin/autopilot-queue`, built 2026-09-20; user docs in
`skills/autopilot/references/queue.md`):

1. creates a worktree from the PR branch (label items) or from the repo's default branch
   (list items), reusing the worktree of a continuation;
2. starts `claude -p "/autopilot <item>" --model sonnet --effort medium --advisor fable
   --fallback-model opus --permission-mode auto --max-budget-usd 60 --output-format json` in
   that worktree (model, effort, advisor and budget from the `env` file), with a wall-clock
   timeout, output to `logs/<item>.log`. `--max-turns` does not exist in the installed CLI;
   the budget and the timeout are the caps. `--append-system-prompt-file` and
   `--exclude-dynamic-system-prompt-sections` stay ideas for later;
3. watches with `autopilot-watchdog` every 20 minutes (zero tokens); on `stalls=4` it kills
   the session;
4. on exit: `HANDOFF.md` present → restart with the same item (up to three times); `REPORT.md`
   present → done; otherwise blocked. The run itself pushed and opened or updated the PR;
   the queue marks the PR ready, swaps the label to `autopilot-done` or `autopilot-blocked`,
   posts the report head as a comment, appends the result to `done.txt`;
5. notifies: macOS notification and a Slack message per finished or blocked item when a
   webhook is configured.

**Sources:** the machine-wide list `~/.claude/autopilot-queue/queue.txt` and, per repo listed
in `repos.txt`, every open PR with the label `autopilot-ready`. Developers produce the second
kind without talking to Andreas: `/autopilot-plan <ticket or topic>` (a topic without a ticket
gets its ticket created through the project's tracker), answer the questions, say "hand to the
queue"; the skill pushes the branch and opens the draft PR with the label. Andreas' part is
zero: the queue runs nightly on the office Mini (`autopilot-queue install-schedule 22:00`,
a LaunchAgent in the GUI session so the Keychain login is readable) and the results arrive on
the PR and in Slack.

**Requires** a logged-in `claude` CLI on the machine and `gh`. Both Macs are logged in since
2026-09-20. Caveat, verified on the office Mini: Claude Code keeps the login in the macOS
Keychain, and a session started over SSH (or by launchd outside the user's GUI session) cannot
read it, so `claude -p` there reports "Not logged in" although the Mac is logged in. The
LaunchAgent runs in the GUI session; for SSH-triggered starts the alternative is a long-lived
token from `claude setup-token`, kept in a mode-600 file and exported as
`CLAUDE_CODE_OAUTH_TOKEN`.

**Decisions (Andreas, 2026-09-20):** one machine-wide list, not per repo; the run owns push
and PR, the queue only retries and reports; sequential only, parallel later if the first week
went well; items without a plan are allowed and marked `no-plan` in `done.txt`. Second source:
GitHub PRs labelled `autopilot-ready`, so developers hand work over without a Slack message.

## Expected effect

For the WEB-1095 session: no coordinator ($62), one review instead of fifteen (about $28
saved), seven runs of one context each instead of fifteen lead starts (fewer base loads and
plan re-reads), no planner and plan-reviewer agents in the run. Estimate $90-110 instead of
$220, and roughly a third of the agents. To be measured on the first real run with
`autopilot-usage`.

## Feedback round 1 (Andreas, 2026-09-20)

**Model per run.** Claude Code fixes the model per session at launch; a skill cannot switch it
without invalidating the whole cache. So the model is a launch parameter: `claude --model
sonnet` (interactive) or a column in the queue (`claude -p --model sonnet ...`). Recorded in
the autopilot skill.

**Advisor.** Claude Code's advisor tool (docs: code.claude.com/docs/en/advisor) pairs the
main model with a stronger one that Claude consults "before committing to an approach, when
an error keeps recurring, and before declaring a task done". Sonnet main + Fable advisor is an
accepted pairing (`claude --advisor fable`, `advisorModel` setting, or `/advisor fable`; needs
Fable access and, on some plans, the one-time usage-credits consent). Cost: each advisor call
re-reads the whole transcript at the advisor's rates, uncached, so a Sonnet run with a few
Fable consultations should cost far less than a Fable run; Anthropic's own claim is that it
"typically costs less than running the stronger model throughout". Subagents inherit the
advisor. Recommended default for autopilot runs: Sonnet main + Fable advisor, to be measured
against Fable-only on the first two real runs with `autopilot-usage` (advisor tokens show up
in `/usage`; the transcript records them under the server tool).

**Queue from the tracker, not only a file.** Items may come from Jira (a filter or label,
e.g. `autopilot-ready`) or GitHub issues (a label) besides a text file; the script gets an
input adapter per source and writes the result back (comment with branch and PR, label
change). The text file stays as the simplest source.

**Feature-branch mode.** Several sessions belong to one feature (e.g. SSO login) and must all
land on one feature branch that is reviewed as a whole. The plan header carries `Branch mode:
feature-branch <name>` and `PR: none`; each run checks out that branch, commits onto it, pushes
it (rebase-pull first), opens no PR; the last session or Andreas opens the feature PR. The
queue processes the feature's items strictly in order and rebases each on the current branch
head. Built into the plan and autopilot skills.

**Effort per run.** Claude Code's `--effort <low|medium|high|xhigh|max>` is, like the
model, a launch parameter. Autopilot runs default to `medium` (the global `effortLevel`
setting is `high` on Andreas' Macs, so the launch line always passes `--effort`). The plan
header carries `Effort: <level>`, the plan skill's hand-over line prints the full launch line
(`claude --model sonnet --effort medium --advisor fable --fallback-model opus --permission-mode auto`; the turn and dollar caps exist only in headless `-p` mode), and the queue gets an effort column
next to the model column. Raised only when the plan's risks call for it.

**Codex review on by default.** After the Claude adversarial review, the run calls
`evelan:codex-review` on the branch whenever `codex-cli --version` succeeds; "ohne Codex" /
"no Codex" in the prompt switches it off. Unattended, nobody picks findings, so Codex's
findings are handled like the reviewer's: correctness, requirement and safety gaps fixed
test-first (one cycle), the rest rebutted in `REPORT.md`. Codex rate-limited or missing →
skipped with one line in `REPORT.md`, no Claude fallback (the adversarial review already ran).

**Write-less rules (Ponytail) in the skill, not as a plugin.** JetBrains tested Ponytail
(blog.jetbrains.com/ai/2026/07/ponytail-skill-claude-tested): the skill installed alone never
self-activated in ten sessions; with the ruleset injected at session start it cut typical task
cost by 10.3% (p=0.004), code written by 15.4% median, wall-clock by 11%, with no measurable
quality change (65 of 80 tasks identical). Andreas' rule: vendor, never install third-party
skills. So the ladder and rules are condensed into the autopilot skill's "Write less"
section, which is in context for the whole run (the skill body is the injection); attribution
in `skills/THIRD-PARTY-NOTICES.md` (MIT, DietrichGebert/ponytail, commit `e3ba2aa`,
2026-09-14). Not vendored: the intensity levels, statusline, review/audit/debt/gain skills.

**Plan skill borrows from the vendored Pocock skills:** seams agreed with the user before
slicing (to-spec), tracer-bullet slices with blocking edges, prefactoring first,
expand/migrate/contract for wide refactors, and a granularity quiz (to-tasks), a named
destination and "decisions before plans". The plan skill refuses a topic that still has open
decision tickets.
