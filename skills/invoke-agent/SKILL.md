---
name: invoke-agent
description: >-
  Bring a second model into the work in a fixed mode: agree on a proposal
  with Codex over up to three rounds, compare a blind answer against yours,
  get ranked debugging hypotheses, have tests written from the spec, or get
  an implementation plan. Use when the user asks for one of these modes with
  Codex or another Claude model - "einig dich mit Codex", "diskutier das mit
  Codex", "blind vergleichen", "was würde Codex unabhängig sagen", "lass
  Codex debuggen", "lass Codex die Tests schreiben", "Plan von Codex",
  "agree this with Codex", "argue it out with Codex", "blind comparison",
  "independent answer", "ask Opus for hypotheses", "invoke agent". A plain
  question or task for Codex is codex-ask; a Codex review of a diff is
  codex-review.
argument-hint: "[agreement | blind | debug | implement | test | review | plan] [codex | claude] [model] <task>"
---

# Invoke Agent

Hand one task to another model in a named mode, then check what comes back.
The other model sees none of this conversation. Its answer is a claim:
evidence comes from checks you run yourself.

## 1. Pick Mode, Agent and Model

**Mode:** the first word of the arguments, else the one the user's wording
names, else `ask` (read-only advice).

**Agent:**

| Mode | Agent |
|---|---|
| `agreement`, `blind` | always Codex: the point is a different model family |
| everything else | the one the user names; Codex when they name none |

Codex needs the CLI: preflight per
`${CLAUDE_PLUGIN_ROOT}/skills/codex-review/references/codex-common.md`.
Preflight fails in a cross-family mode: stop and say so; a Claude subagent is
the same family and gives no blind or adversarial read.

**Model:** the one the user names, else none.

- Codex: resolve the name with `codex-model resolve` and pass the slug, per
  codex-common.md. No name: Codex's own default.
- Claude: a subagent (Agent tool) with `model` set to `fable`, `opus`,
  `sonnet` or `haiku`. No name: omit `model`, the subagent inherits the
  session's model. When the user only says "the strongest" or "a cheap one",
  pick `fable` or `haiku`.

## 2. Write the Brief

The brief stands alone. Write it to a file from `mktemp /tmp/codex-XXXXXX`
(Codex) or pass it as the subagent prompt (Claude). It always carries:

- the task in the user's words, and the mode's payload (table below);
- the context: repo path, the files to read first, the conventions that bind
  this task;
- the scope and limits: read-only ("advise only, no edits") unless the mode
  writes code; "do not commit, push or branch"; "start no further agents";
- the shape of the answer you want back.

| Mode | Payload | Answer shape |
|---|---|---|
| `ask` | the question | the answer with its evidence |
| `agreement` | your proposal and the evidence behind it | endorse, or each objection with its evidence and a revised proposal |
| `blind` | the question and neutral context only | the agent's own answer with evidence |
| `debug` | the repro, observed vs expected, every hypothesis already killed and the evidence that killed it | ranked hypotheses, each with the cheapest check that confirms or kills it |
| `implement` | the ticket or plan in full (or its path), the repo's lint, test and typecheck commands | the change, plus how it verified it |
| `test` | the spec or intended behaviour, never your implementation notes | tests that pin the spec |
| `review` | the exact scope (commit range, diff base or files) and what the change was meant to do | correctness, requirement and safety gaps with `file:line` |
| `plan` | the task | numbered steps, files touched, risks, open questions |

`blind`: write your own answer down before you start the run. Any hint of it
in the brief anchors the other model and turns the run into `agreement`.

## 3. Run

### Codex

| Mode | How |
|---|---|
| `implement`, `test` | the `evelan:codex-ask` procedure as written (dirty-tree check, snapshot, workspace-write run, snapshot diff), with this brief |
| `review` | `evelan:codex-review`; a focus text goes in only per its scope rules |
| all others | read-only run below |

Read-only run, log and answer files from `mktemp /tmp/codex-XXXXXX`, run
per the Running section of codex-common.md:

```bash
codex-cli exec --sandbox read-only [-m <slug>] -o /tmp/codex-<answer> - < /tmp/codex-<brief> > /tmp/codex-<log> 2>&1
```

The answer is in the `-o` file. Note the `session id:` line from the log
header: follow-ups resume that exact session, never `--last` (another run may
be newer):

```bash
codex-cli exec resume -c sandbox_mode=read-only [-m <slug>] -o /tmp/codex-<answer> <session id> - < /tmp/codex-<followup> > /tmp/codex-<log> 2>&1
```

Outside a git repo add `--skip-git-repo-check` to both.

### Claude

One subagent (Agent tool, `run_in_background: false`). Read-only modes use
the `Plan` agent type (no edit tools); `implement` and `test` use
`general-purpose`. Follow-ups go to the same agent through SendMessage.

### Failure

Non-zero exit, an empty answer file, a timeout, or a subagent error is a
failed call. Report it with the log excerpt and path. A failed call is never
agreement and never a clean review.

## 4. Check and Report

Each mode is done when its check is:

- `ask`, `plan`: every file, API and command claim the answer rests on is
  checked against the repo before you adopt it; wrong ones named.
- `agreement`: the loop below ended in one proposal both sides endorse, or
  after round three with the open disagreements listed.
- `blind`: answers compared point by point: where they converge, where they
  split, and for each split whose evidence holds.
- `debug`: you ran the checks, cheapest first, until one hypothesis is
  confirmed or all are killed. An unchecked hypothesis is reported as a lead.
- `implement`: you read the whole diff against the ticket and re-ran lint,
  tests and typecheck yourself. The agent's success report counts for nothing.
- `test`: each kept test goes red when you break the logic it covers and
  green when you restore it. Tests that stay green on the break are dropped.
- `review`: Codex findings relayed verbatim (codex-review rules); then each
  finding checked against the code, and the false ones rejected out loud in
  a separate section.

Report: the mode, which agent and model ran (Codex: the `model:` line of the
log), the log path, the outcome per the check above. Nothing is committed;
Codex changes go through the keep, adjust or revert question of codex-ask.

### Agreement Loop

Each round, one follow-up to the same session: your assessment of its reply,
the evidence for each point you still dispute, your revised proposal. Stop
when both sides endorse the same proposal, or after three rounds. Concede a
point when its evidence holds; hold one only with evidence of your own.
