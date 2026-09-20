# Token and wall-clock review of mission-control + autopilot (2026-09-19)

Why: orchestrated sessions ran for days and burned through usage limits. This review measured
three real sessions from local transcripts (`~/.claude/projects/<project>/<session>.jsonl` plus
the `subagents/` folder) and derived the changes shipped in plugin 1.7.0.

## Measurements

| Session | Part | Turns | Avg context / turn | Max context | Cache-read tokens | List price |
| --- | --- | --- | --- | --- | --- | --- |
| evelan-hub mission-control (5 days, 73 subagents) | coordinator | 3,590 | 494k | 998k | 1.74B | ~$1,100 |
| | subagents | ~25,000 | 400-570k | 942k | 5.14B | ~$3,250 |
| jexity-monitor mission-control (2.5 days, 51 subagents) | coordinator | 1,586 | 518k | 966k | 0.80B | ~$520 |
| | subagents | ~7,000 | 150-415k | | 1.47B | ~$930 |
| nessy-portfolio standalone autopilot | main | 1,571 | 562k | 920k | 0.86B | ~$615 |

List prices (Sept 2026): Fable 5.1 cache read $0.25/M, Opus 5 $0.50/M, Fable 5 $1/M; output
Fable 5.1 $50/M, Opus 5 $25/M. Subscription usage counts the same tokens against the limits.

Findings:

1. Cache reads were 70-80% of the cost. Cost is context size times turn count.
2. Implementer subagents never compacted: auto-compact on 1M models triggers at ~967k. One
   whole-topic implementer ran 1,125 turns at 567k average context. Per-package dispatch
   (jexity) kept subagents at a third of that.
3. A `general-purpose` subagent started every turn with 45-60k tokens (tool definitions of 16
   plugins and all connectors plus the global CLAUDE.md). The `autopilot-reviewer` agent with
   a tools allowlist started at 5-11k.
4. Of 6,740 Bash calls in one session's subagents, 20% were `grep`, 9% `sed`, 4% `cat`, 6.5%
   `git`; the gate ran 3-4 times per package with full output (267 vitest runs).
5. The coordinator pulled 900k characters of subagent transcript into its own context via 51
   blocking `TaskOutput` calls and ran 1,555 Bash calls itself.
6. Time: ~60% of active subagent time was model generation, ~40% tool time. The 10-minute
   watchdog stopped agents that had already reported done; finished agents were re-woken hours
   later by background-task notifications.

## Changes shipped (plugin 1.7.0)

- `agents/autopilot-lead.md`: Fable 5.1, tools allowlist, `maxTurns: 500`. Mission control
  dispatches it instead of `general-purpose` + Opus.
- Mission control dispatches one lead per work package (`PACKAGE <id>`) plus one `FINALIZE`
  dispatch; writes `DIGEST.md` (exploration digest) once; never reads transcripts; 20-minute watchdog on task
  status and branch progress; browser verification delegated to a verifier subagent; launch
  requirement `--autocompact 300k`; Codex review once per session.
- Autopilot: orchestrated modes, context-hygiene section (bounded reads, tail, one gate run
  per package), superpowers chain trimmed for unattended runs, no Stop-hook sentinel in
  orchestrated mode.
- `autopilot-gate-filter.sh` PreToolUse hook (installed by `/autopilot init`): failures plus
  summary instead of full runner output, exit status preserved, hook-written evidence log
  `.claude/autopilot-gate.log` that the reviewer may accept when it matches HEAD.
- Reviewer at `effort: medium`.

Expected effect: 2-3x fewer cache-read tokens per session and proportionally shorter wall
clock. Measure the next orchestrated session the same way (the analysis scripts read the
transcript JSONL and sum `usage` per assistant record) and compare.

## Follow-up (plugin 1.8.0, same day)

Second review round with Andreas: auto-compaction is not the mechanism to rely on. Anthropic
documents what compaction drops (skill bodies capped at 5k tokens, hook context, most of the
history) and offers no hook that fires at a context threshold or blocks compaction. So the
context limiter is now an explicit hand-off:

- `autopilot-context-budget.sh` (PostToolUse): reads the session's own transcript after each
  tool call, sums input + cache_creation + cache_read of the last assistant record, and above
  the budget (default 250k) injects the instruction to write `HANDOFF.md`, commit and return
  `STATUS: incomplete`. Mission control then dispatches a fresh lead with the hand-off path.
  Deterministic, no model summary. Verified on real subagent transcripts that the usage fields
  are present; whether `transcript_path` inside a subagent points to the subagent's own file
  is undocumented and must be confirmed on the first real run.

  **Confirmed on the first real run (evelan-slides, 2026-09-19 evening, plugin 1.8.1): it does
  not.** `transcript_path` is always the main session's transcript, also inside a subagent
  (Claude Code 2.1.241 builds it from the session id; only `SubagentStop` carries an
  `agent_transcript_path`). The hook therefore measured the idle coordinator (314k tokens, a
  value that never moved) while the lead's real context was 49k-107k, forced a hand-off after
  two minutes without code, and the coordinator "fixed" it by raising `contextBudget` to 650k.
  Plugin 1.8.2 resolves `<main transcript>/subagents/agent-<agent_id>.jsonl`, stays silent
  when that file is missing, takes the minimum of the last three usage records (transcripts
  contain one-off spikes far above the neighbouring turns), keeps one reminder counter per
  agent, and names the measured file in the reminder. The 650k setting in evelan-slides must
  go back to the default.

  Measured in that session, for the record: coordinator 111k tokens at its first turn and
  333k after one package (Slack and Jira reads, full `git show` of three design docs, writing
  and revising a 480-line `PLAN.md`); Explore agent 56k → 220k in 83 `cat -n` dumps; lead
  49k base + 6k skill body, 181k after 165 turns; a lead reads `PLAN.md` in full one to three
  times per dispatch.
- `autopilot-session-start.sh` (SessionStart, matcher `compact`): if compaction happens
  anyway, re-injects the session folder pointer. The only documented post-compaction pattern.
- The auto-compact launch requirement is gone; the lead's `maxTurns` is 400.
- `bin/autopilot-watchdog`: one progress tick from `git log` and `PLAN.md` mtime with its own
  stall counter, so the coordinator never improvises a watchdog script or reads output files.
- Autopilot is decoupled from Superpowers entirely. TDD, debugging and review rules are inline
  (seams, vertical slices, anti-patterns, two failed fixes then bisect). In the analysed
  orchestrated sessions the implementer subagents had invoked no Superpowers skill at all; the
  remaining cost was the per-session hook injection and the interactive workflows that ask
  questions an unattended run must not ask.
- Matt Pocock's engineering and productivity skills (MIT) are vendored under `skills/` with
  Evelan names (see `skills/THIRD-PARTY-NOTICES.md`), as the interactive counterpart:
  `question-with-docs` before `mission-control` is the recorded rule, `handoff` is the
  interactive hand-off, `code-review` supplies the standards axis the reviewer runs on
  request.

## Follow-up (plugin 1.9.0, same evening): where the tokens of a real session go

Measured with the new `bin/autopilot-usage` on the local-recording session (MacBook, plugin
1.8.2 hook, one package plus its hand-off continuation, still running when measured):

| agent | turns | first ctx | last ctx | cache reads | output |
| --- | --- | --- | --- | --- | --- |
| coordinator | 135 | 106k | 262k | 22.7M | 246k |
| Explore | 57 | 36k | 153k | 5.2M | 18k |
| plan reviewer (general-purpose) | 57 | 82k | 184k | 6.6M | 20k |
| lead P1 | 166 | 63k | 258k | 29.5M | 88k |
| reviewer | 48 | 42k | 98k | 3.5M | 10k |
| lead P1 continuation | 13 | 63k | 88k | 0.9M | 3k |

The evelan-slides session (office Mini, three packages in, 942 turns, 147M cache reads):
coordinator 235 turns, 111k → 358k, 61M cache reads (42% of the session), 311k at the
first lead dispatch; Explore 129 turns, 56k → 220k, 19M; the three leads 2.7M, 12M and
24M; the two reviewers 2M each. The lead for WP2 ran to 336k without a hand-off because
the budget stood at 650k at the time. Several agents show one-off `max_ctx` records far
above their neighbours (coordinator 612k, Explore 420k), which is why the hook takes the
minimum of the last three records.

The fixed hook fired in the local-recording session on the lead's own transcript at 252k
(`measured from agent-a5c3….jsonl`), the lead wrote `HANDOFF.md`, and mission control
dispatched the continuation lead with it: the hand-off works end to end.

Findings and what 1.9.0 does about them:

1. **The base every agent carries.** A lead starts at 49-63k tokens before it has read a
   single project file. Of that, the user-controlled part is: plugin skill and agent
   descriptions listed in every system prompt (~7.5k tokens across 17 installed plugins;
   `vercel` 3.2k, `figma` 1.6k, `pr-review-toolkit` 1.0k, `superpowers` 0.5k, `evelan` 0.4k),
   the global `CLAUDE.md` (~5.6k tokens) and the project `CLAUDE.md` (local-recording:
   ~12k tokens). The rest is the harness prompt and built-in tools. Disabling the plugins a
   machine does not use and condensing both `CLAUDE.md` files saves 10-15k tokens per turn
   of every agent, roughly 8% of a lead's average context. That is the user's housekeeping,
   outside the plugin; the numbers are here so it can be decided.
2. **The plan is read whole, several times.** `PLAN.md` was 480-513 lines; a lead read it in
   full one to three times per dispatch, the plan reviewer and Codex read it as well. 1.9.0
   splits it: `PLAN.md` is the short index (scope, goal artifact, decisions, package list
   with statuses, aim under 150 lines) and each package has `packages/<id>.md`; a lead reads
   exactly `PLAN.md`, its package file and `DIGEST.md`, the reviewer gets the package file.
   Expected saving: 5-10k tokens per dispatch plus fewer re-reads.
3. **The Explore agent dumps files.** 83 `cat -n` calls, 36k → 153k (local-recording) and
   56k → 220k (evelan-slides). Its prompt carried no reading rules. 1.9.0 puts the rules
   into the mission-control and autopilot instructions for the Explore prompt and the
   plan-review prompt (grep to locate, sed slices of at most ~80 lines, paths and line
   references instead of contents, digest under ~2000 words).
4. **A planner subagent for mission control: measured, not built.** The coordinator carried
   241k (local-recording) and 291k (evelan-slides) into the first lead dispatch, i.e.
   planning costs it 130-180k of context for the rest of the run. But most coordinator
   turns ARE planning turns (about 110 of 135 in local-recording); after the first dispatch
   it made ~25 turns. Moving planning into a subagent would save those ~25 turns × ~130k ≈
   3M cache-read tokens of 68M in the session, about 4%; in evelan-slides (65 post-planning
   turns × ~200k) about 13M of 147M, 9%. Not worth the restructuring at this stage;
   re-measure when sessions run 8+ packages and the coordinator's post-planning share grows. `autopilot-usage` prints the figure ("coordinator context at the first
   autopilot-lead dispatch") so every session answers this question itself.
5. **Truncating outputs was proposed and rejected** (Andreas: cut-off output is missing
   information, not saved tokens). Reading discipline stays a rule, not a filter.
