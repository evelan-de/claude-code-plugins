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
