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

**Per item** the script:

1. creates a worktree from the repo's integration branch (`git worktree add`), or reuses the
   session branch when the item is a continuation;
2. starts `claude -p "/autopilot <item> defer PR" --permission-mode auto` in that worktree,
   with `--max-turns` and a wall-clock timeout, output to `logs/<item>.log`;
3. watches with `autopilot-watchdog` every 20 minutes (zero tokens); on `stalls=4` it kills
   the session and restarts it once with the hand-off;
4. on exit: `HANDOFF.md` present → restart with the same item (up to N times); `REPORT.md`
   present → push the branch, open the PR (the script owns push and PR, the run does not),
   append the result to the done file; otherwise record the blocker;
5. notifies: macOS notification and, optionally, a Slack message per finished or blocked
   item (the Slack step is a later addition).

**Requires** a logged-in `claude` CLI on the machine (`claude /login` once per Mac; both Macs
are currently not logged in for headless use) and `gh` for the PR.

**Open questions for Andreas:**

- Queue file per repo (`docs/autopilot/QUEUE.txt`, committed) or one machine-wide file?
- Should the queue open the PR itself, or leave push and PR to the run (the run can do it;
  the script doing it keeps every run "defer PR" and gives one place to retry)?
- Sequential only (one session at a time, as tonight's need), or up to N in parallel later?
- Ticket keys without a plan: allowed (the run plans conservatively) or refused (plans are
  always written interactively first)?

## Expected effect

For the WEB-1095 session: no coordinator ($62), one review instead of fifteen (about $28
saved), seven runs of one context each instead of fifteen lead starts (fewer base loads and
plan re-reads), no planner and plan-reviewer agents in the run. Estimate $90-110 instead of
$220, and roughly a third of the agents. To be measured on the first real run with
`autopilot-usage`.
