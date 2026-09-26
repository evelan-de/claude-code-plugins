# Autopilot for developers

How a developer at Evelan hands a ticket to the autopilot and gets a reviewed PR back.
This guide covers your side of the workflow. The skill details are in
`skills/autopilot-plan/SKILL.md`, `skills/autopilot/SKILL.md` and
`skills/autopilot/references/mission-control.md`.

**In one sentence:** you write the plan together with Claude in your own session, open a
draft PR with the label `autopilot-ready`, and the queue on the office Mini implements it
overnight and returns a ready PR with a report, which you review and merge.

## Contents

1. [The big picture](#1-the-big-picture)
2. [Why this works better than 1.x](#2-why-this-works-better-than-1x)
3. [Who does what](#3-who-does-what)
4. [Before your first run](#4-before-your-first-run)
5. [Step by step](#5-step-by-step)
6. [What happens inside a run](#6-what-happens-inside-a-run)
7. [PR labels and their meaning](#7-pr-labels-and-their-meaning)
8. [Reviewing the result](#8-reviewing-the-result)
9. [When a run is blocked](#9-when-a-run-is-blocked)
10. [Feature branches: several sessions, one PR](#10-feature-branches-several-sessions-one-pr)
11. [Rules and limits](#11-rules-and-limits)
12. [Cheat sheet](#12-cheat-sheet)

## 1. The big picture

The work is split in two: the **plan** is written interactively, with you in the loop,
because that is where the decisions are. The **run** is headless and asks nothing, because
every decision is already in the plan.

```mermaid
flowchart TB
    subgraph S1["1 · Plan: your machine, interactive"]
        direction LR
        T["Ticket, spec<br/>or idea"] --> Q["/evelan:question-me<br/>optional"]
        Q --> P["/autopilot-plan KEY<br/>asks you 3 times"]
        T --> P
        P --> PLAN[("PLAN.md<br/>on feat/KEY-slug")]
    end

    subgraph S2["2 · Hand over: GitHub"]
        direction LR
        DPR["Draft PR<br/>label autopilot-ready"]
    end

    subgraph S3["3 · Run: office Mini, headless, nightly 22:00"]
        direction LR
        MC["mission-control<br/>queue runner"] --> RUN["/autopilot<br/>own worktree"]
        RUN -- "HANDOFF.md,<br/>up to 5 restarts" --> MC
        MC -.-> JIRA["Jira: In Progress,<br/>result comment"]
        MC -.-> SLACK["Slack<br/>#mission-control"]
    end

    subgraph S4["4 · Review: you, on GitHub"]
        direction LR
        RPR["Ready PR<br/>autopilot-done<br/>+ report comment"] --> BOT["Review-bot comments<br/>answered by the run"]
        BOT --> YOU["You review<br/>and merge"]
    end

    PLAN -- "push, draft PR" --> DPR
    DPR -- "picked up" --> MC
    RUN -- "push, mark ready" --> RPR
```

## 2. Why this works better than 1.x

Plugin 1.x put a **model in charge**: in a session, a coordinating model ("mission control" at
the time) explored, planned, dispatched one lead agent per package, a reviewer per package, a
verifier, and read their results back. That looked like a team, and it behaved like one that
spends most of its day in meetings. We measured it on real sessions
(`docs/2026-09-19-token-efficiency-review.md`) and rebuilt it in two steps: 2.0 removed the
coordinator, 3.0 made every run headless and moved the design work into the plan
(`docs/2026-09-20-autopilot-v2.md`, `docs/2026-09-21-autopilot-v3.md`).

**1.x: a model coordinates models**

```mermaid
flowchart TB
    U1["You: /autopilot or mission control<br/>in your session, kept open"] --> C["Coordinator model<br/>explores, plans, dispatches, reads results back<br/>context 300k to 1M"]
    C --> E1["Explore"]
    C --> PL["Planner +<br/>plan reviewer"]
    C --> L1["Lead P1"]
    C --> L2["Lead P2"]
    C --> L3["Lead Pn"]
    C --> VF["Verifier"]
    L1 --> R1["Reviewer P1"]
    L2 --> R2["Reviewer P2"]
    L3 --> R3["Reviewer Pn"]
```

**3.x: you plan, a script runs, one context works**

```mermaid
flowchart LR
    U3["You + Claude<br/>/autopilot-plan<br/>decisions, code-level plan"] --> PR0["Draft PR<br/>autopilot-ready"]
    PR0 --> Q["mission-control<br/>script, zero tokens"]
    Q --> RUN["One headless run<br/>Sonnet or Opus + Fable advisor"]
    RUN -- "HANDOFF.md" --> Q
    RUN --> REV["One reviewer<br/>whole branch"]
    REV --> OUT["PR + REPORT.md"]
```

| | 1.x | 3.x (now) |
| --- | --- | --- |
| Who coordinates | a model; 28% of the session cost on its own, context grew to 1.06M and was re-written after idle gaps | a shell script (`mission-control`); costs no tokens |
| Agents per ticket | 33 agents, 1,795 requests for one ticket (WEB-1095) | one run context, one reviewer, plus hand-off sessions when the context fills up |
| Cost per ticket (list price) | about $220 for WEB-1095; up to $100+ even for a standalone run | PAUL-2649, three packages: $9.99 + $6.00 across two runs, PR with green CI |
| Cache reads per package | ~45M with lead agents | ~9M in 2.x; 3.x lower by design, measured per run with `autopilot-usage` |
| Who designs the code | the run, while running: plans listed files, not insertion points, so the implementer invented signatures and flows | you and the planner, before the run: `path:line` anchors, signatures, pseudo-code, test cases; the run executes |
| Decisions | made by the coordinator, mid-run, invisible until the end | asked once while planning, written into `PLAN.md`; the rest in `DECISIONS.md` |
| Reviews | one per package (15 for WEB-1095) | one adversarial review on the whole branch, Codex, then the Claude review bot with every comment answered |
| Running out of context | auto-compaction (drops history and skill bodies), later a budget hook that measured the wrong transcript | deterministic hand-off at 500k tokens, the runner restarts a fresh session up to 5 times |
| Stranded work | a standalone run that handed off waited for someone to restart it (still so in 2.x) | every run is started and chained by the runner; nothing waits for a person |
| Browser check | desktop-app browser tools only, so no UI check without an open desktop session (UI tickets ended blocked in the first headless runs) | `agent-browser` headless, with a saved login where needed |
| Jira | desktop-app connectors, used by the model when it remembered to | the runner sets In Progress and comments the result, every time |
| Your time | start a session and keep it running, often for hours, in one case five days | three short moments of questions while planning, then review the PR |
| Who can use it | whoever runs the session on their own machine | every developer: plan, label the draft PR, results arrive on the PR and in Slack |

Why it adds up:

1. **Cost is context size times number of requests.** A coordinator carries everything it has
   seen into every request. A script has no context at all, and one run with a bounded
   context and a hand-off makes far fewer, smaller requests.
2. **Multi-agent pays off for parallel research, not for coding.** Anthropic's own write-up
   says so, and the 1.x numbers agree: most coding work is sequential, so extra agents mostly
   add base loads and hand-over reading.
3. **Deciding is expensive, executing is cheap.** Design questions now happen once, with you,
   on a strong model; the run follows steps instead of inventing them. That is
   also why the result matches what you asked for more often: the decisions are yours and
   written down, not guessed at 3 a.m.
4. **Nothing depends on a session staying open.** The queue, the restarts, the ticket
   updates and the notifications are code, not a model's good intentions.

Honest caveats: the $220 and $16 figures come from different tickets, so they show the order
of magnitude, not an exact ratio. Each run prints its own `autopilot-usage` table, so every
ticket adds a real data point.

## 3. Who does what

| Step | Who | Where | Output |
| --- | --- | --- | --- |
| Set up the project once | you or Andreas | your session, `/autopilot init` | gate, hooks, labels in the repo |
| Add the repo to the queue once | Andreas | office Mini, `repos.txt` | the queue sees the repo's labelled PRs |
| Sharpen the idea (optional) | you + Claude | your session, `/evelan:question-me`, `/evelan:to-spec` | spec, ADRs, `CONTEXT.md` |
| Write the plan | you + Claude | your session, `/autopilot-plan` | `PLAN.md` on the branch |
| Hand it over | Claude, on your go | your session, step 7 of the plan skill | draft PR labelled `autopilot-ready` |
| Implement, test, review, verify | the run | office Mini, headless | commits, `REPORT.md`, ready PR |
| Ticket and notifications | `mission-control` | office Mini | Jira In Progress + comment, Slack, PR label |
| Review and merge | you | GitHub | merged PR |

The run **never merges** and never sets a ticket to Done. Merging stays with you.

```mermaid
sequenceDiagram
    autonumber
    actor Dev as You
    participant CS as Claude session<br/>(your machine)
    participant GH as GitHub
    participant MC as mission-control<br/>(office Mini)
    participant Run as /autopilot run<br/>(headless)
    participant Jira
    participant Slack

    Dev->>CS: /autopilot-plan WEB-1095
    CS->>Dev: seams, shape questions, branch mode (once)
    Dev->>CS: answers
    CS->>Dev: package list (once)
    Dev->>CS: approve
    CS->>CS: write + commit PLAN.md
    CS->>Dev: run here or hand to the queue?
    Dev->>CS: hand to the queue
    CS->>GH: push branch, draft PR, label autopilot-ready
    Note over MC: nightly run (22:00)
    MC->>GH: list PRs labelled autopilot-ready
    MC->>Jira: jira start (In Progress, assigned)
    MC->>Run: claude -p "/autopilot <session dir>"
    loop per package
        Run->>Run: tests first, gate green, commit
    end
    Run->>Run: adversarial review, Codex review, browser check
    Run->>GH: push, PR ready, watch CI
    GH-->>Run: Claude review bot comments
    Run->>GH: fix or rebut every comment
    Run-->>MC: REPORT.md "Status: done"
    MC->>GH: label autopilot-done, report comment
    MC->>Jira: comment with status, PR link, report
    MC->>Slack: done
    Dev->>GH: review, merge
```

## 4. Before your first run

Once per **project** (skip what is already there; `.claude/autopilot.json` in the repo means
it was done):

```
claude
> /autopilot init
```

It detects the package manager, writes the gate (typecheck, lint, test) into
`.claude/autopilot.json`, installs four hooks into `.claude/hooks/` and
`.claude/settings.json`, adds runtime files to `.gitignore`, and creates the labels
`autopilot-ready`, `autopilot-done` and `autopilot-blocked` (plus `claude-re-review` when
the project has the Claude review workflow). Commit and
merge that setup like any other change.

Two things need Andreas:

- **The repo in the queue.** The office Mini only looks at repos listed in its `repos.txt`.
  A repo that is not on it yet: send Andreas the PR link after your first hand-over.
- **A browser login for the run**, if the goal artifact sits behind a login (dashboard,
  admin area). The state file is saved once by hand on the Mini
  (`/autopilot init` prints the recipe). Without it, logged-in checks land in
  `MANUAL_TESTING.md` for you to do.

On **your machine** you need only the plugin (`/plugin install evelan@evelan-plugins`) and
`gh` logged in. No queue, no Jira token, no `agent-browser`. `/mission-control` and
`mission-control` refuse on a machine without a queue and point you back here; that is
expected.

## 5. Step by step

### 5.1 Start from a ticket (or create one)

`/autopilot-plan` accepts a ticket key (`WEB-1095`, `#42`), a spec file, or a plain topic.
A topic without a ticket gets its ticket created through the project's tracker once the
shape is settled. If the topic still has open decisions ("should we even do X?"), settle
them first with `/evelan:question-me`; the plan skill stops on open decision tickets.

### 5.2 Write the plan

```
claude            # Fable is the intended planner, Opus is fine
> /autopilot-plan WEB-1095
```

What the skill does, and where it needs you:

```mermaid
flowchart TD
    A["1. Resolve input<br/>ticket, spec or topic"] --> B["2. Explore<br/>reads every touched file whole"]
    B --> C{{"3. Ask once<br/>seams, shape questions,<br/>goal artifact, branch mode"}}
    C --> D["4. Slice into packages<br/>tracer bullets, max ~6 files / ~300 lines each"]
    D --> E{{"Ask once<br/>granularity, edges, split or merge?"}}
    E -- "change" --> D
    E -- "approved" --> F["5. Write PLAN.md<br/>path:line anchors, signatures,<br/>pseudo-code, tests with input → expected"]
    F --> G{"3+ packages?"}
    G -- "yes" --> H["6. autopilot-plan-reviewer<br/>fresh context, opens every anchor"]
    G -- "no" --> I
    H --> I["7. Commit PLAN.md on the branch<br/>feat/KEY-slug"]
    I --> J{{"Ask: run here or<br/>hand to the queue?"}}

    classDef ask fill:#fff4d6,stroke:#c9a227,color:#3d2f00
    class C,E,J ask
```

The yellow boxes are the three moments you are asked. Answer them carefully: every point you
leave open is later decided conservatively by the run and written into `DECISIONS.md`.

Good answers to the shape questions name:

- **the goal artifact**: what you will look at to accept the work ("the export button works
  at `/reports` in the local app", "report at `docs/x.md`"). The run verifies exactly this
  in a real browser. "Gate green" is not a goal artifact.
- **what is out of scope**, so the run does not build it.
- **the branch mode**: one branch and PR per session (default) or a shared feature branch
  (section 10).

The plan lands in `docs/autopilot/sessions/<date>-<KEY>-<slug>/PLAN.md`. Read it before you
hand it over. Worth a glance: `Model:` (`sonnet` by default, `opus` when you asked for it)
and `Effort:` (how hard the run thinks: `low`, `medium`, `high`, `xhigh`, `max`; Sonnet
always runs at `xhigh` or `max`, Opus at any level, `medium` by default). Say both while
planning ("opus, high"), or change them later with `/autopilot <session dir> opus high`
(either word alone works too); for a PR already handed to the queue, edit the two header
lines on the branch. Then `Options:`
(`defer PR`, `no Codex`), the Goal artifact, the Decisions, and whether the package list
matches what you had in mind.

### 5.3 Hand it to the queue

At the end of `/autopilot-plan` answer **"hand to the queue"**. The skill pushes the branch
and opens a draft PR against the base:

- title `<KEY>: <destination in a few words>`
- body: destination, goal artifact, path of `PLAN.md`
- label `autopilot-ready`

The draft status matters: the Claude review bot skips drafts, so it reviews only once the
run marks the PR ready.

To hand over an existing plan by hand: push the branch, open a draft PR and add the label
`autopilot-ready`. That is all the queue looks for.

### 5.4 Wait for the result

The queue on the office Mini runs **nightly at 22:00**, one item at a time. Andreas can also
start it on demand. You do not need to keep your machine or session open.

While the item runs:

- the Jira ticket moves to **In Progress** and is assigned to the token owner;
- the run works in its own worktree on the Mini on **your PR branch**. Do not push to that
  branch while it runs. A fix you push before the next attempt is picked up (the worktree
  fast-forwards before every start and restart), but concurrent pushes can conflict.

When it ends you get:

- a Slack message in `#mission-control` (done or blocked, with the reason);
- the PR label `autopilot-done` or `autopilot-blocked`, and a comment "Autopilot report"
  with the head of `REPORT.md`;
- a comment on the Jira ticket with status, PR link and report summary.

## 6. What happens inside a run

You do not steer the run, but knowing its steps tells you what the report means and where
to look when something is off.

```mermaid
flowchart TD
    S(["mission-control starts<br/>claude -p '/autopilot &lt;session dir&gt;'"]) --> G1["1 · Gate, branch, sentinel<br/>checks out the PR branch"]
    G1 --> P1

    subgraph PK["2 · Per package, in plan order"]
        direction TB
        P1["Follow the Implementation steps<br/>confirm each path:line anchor"] --> P2["Red: one failing test<br/>at the named seam"]
        P2 --> P3["Green: minimal code"]
        P3 -- "next test" --> P2
        P3 --> P5["Full gate once, commit<br/>package marked [x]"]
    end

    P5 --> R["3 · Review on the whole branch<br/>evelan:autopilot-reviewer, max 2 cycles<br/>+ Codex cross-model review"]
    R --> V["4 · Goal artifact in the running app<br/>agent-browser: routes, forms, errors,<br/>console, phone viewport, screenshots"]
    V --> F["5 · Docs updated, REPORT.md,<br/>INDEX.md line, commit"]
    F --> PR["6 · gateFull, push, PR ready,<br/>CI watched until green"]
    PR --> RB["Review-bot loop, max 2 rounds<br/>every comment answered"]
    RB --> DONE(["REPORT.md<br/>Status: done"])
```

Two exits can happen at any step:

```mermaid
flowchart LR
    ANY["any step"] -- "context budget reached<br/>(500k tokens)" --> HO["HANDOFF.md,<br/>commit, end turn"]
    HO -- "runner starts a fresh<br/>session, up to 5×" --> NEXT["continues at<br/>HANDOFF's next step"]
    ANY -- "gate cannot go green,<br/>never-list, missing precondition" --> BL(["REPORT.md<br/>Status: blocked - reason"])
```

Details that matter for you as a reviewer:

- **Tests first, at the seams from the plan.** A test is written, seen failing, then made
  green. The run never weakens an assertion to get green.
- **One evidence line per gate run** in `.claude/autopilot-gate.log` (machine-local); each
  package commit has a gate result behind it.
- **Adversarial review.** A separate reviewer in a fresh context checks the branch against
  `PLAN.md`: completeness, correctness, safety, stale docs. Real gaps are fixed test-first;
  what remains goes to the top of `REPORT.md` and into the PR description.
- **Codex review** runs by default when the Codex CLI is on the Mini. Its findings are fixed
  or rebutted with evidence in `REPORT.md`. Turn it off with `Options: no Codex`.
- **The goal artifact is exercised in the running app**, headless through `agent-browser`,
  with screenshots in the session folder. Checks the run cannot perform (a login without a
  state file, a device, a payment) go to `MANUAL_TESTING.md`.
- **Hand-offs are normal.** A large plan outgrows one context. The run writes `HANDOFF.md`,
  and the runner starts a fresh session that continues at the next step. You see
  `restarts=N` in the queue log; the result is still one branch.

## 7. PR labels and their meaning

```mermaid
stateDiagram-v2
    direction LR
    [*] --> Draft: /autopilot-plan hand-over
    state "Draft PR<br/>autopilot-ready" as Draft
    state "Running<br/>(label unchanged)" as Running
    state "Ready PR<br/>autopilot-done" as Done
    state "PR<br/>autopilot-blocked" as Blocked
    Draft --> Running: nightly queue picks it up
    Running --> Done: REPORT.md Status done
    Running --> Blocked: blocked, timeout,<br/>handoff limit
    Blocked --> Draft: you fix the cause,<br/>set autopilot-ready again
    Done --> Merged: you review and merge
    Merged --> [*]
```

| Label | Meaning | Your move |
| --- | --- | --- |
| `autopilot-ready` | waiting for the queue (or running) | nothing; do not push to the branch |
| `autopilot-done` | run finished, PR is ready, report posted | review (section 8) |
| `autopilot-blocked` | run stopped, reason in the PR comment and in Slack | fix the cause, relabel (section 9) |
| `claude-re-review` | asks the Claude review bot for one more full review | add after your own changes if you want a second bot pass; the workflow removes it |

## 8. Reviewing the result

Treat the PR like a colleague's PR, with better paperwork. Everything the run did is in the
session folder on the branch, `docs/autopilot/sessions/<date>-<KEY>-<slug>/`:

| File | Read it for |
| --- | --- |
| `REPORT.md` | first line `Status: done`; What shipped, Verification (commands and results, browser checks), Review (reviewer and Codex findings and what happened to them), Open items, Review bot |
| `DECISIONS.md` | every assumption the run made on its own; the place to disagree |
| `MANUAL_TESTING.md` | the steps only a human can do; do them before merging |
| `PLAN.md` | packages marked `[x]` with a one-line result each, or `[!]` with the gap named |
| `*.png` | one screenshot per screen from the browser check |

A reasonable order: `REPORT.md` top (unresolved gaps come first), `DECISIONS.md`, then the
diff, then `MANUAL_TESTING.md`. On the PR itself every review-bot comment has a reply from
the run: `Fixed in <sha>` or `Not changed: <reason>`.

Found something? Two options:

- **small**: fix it yourself on the branch and push, like on any PR;
- **new review-bot findings** (after a `claude-re-review`): relabel `autopilot-ready`. A run
  on a branch with a `Status: done` report and an open PR resumes in its review phase: it
  verifies the new findings, fixes or rebuts them, and updates the report;
- **larger, or the plan was wrong**: comment what is missing, then write a follow-up plan
  with `/autopilot-plan` (a new ticket, its own branch and PR). The done branch is not
  re-planned in place.

## 9. When a run is blocked

The PR comment and the Slack message carry the reason; `REPORT.md` (if written) starts with
`Status: blocked - <reason>`.

| Reason (roughly) | Typical cause | Fix |
| --- | --- | --- |
| gate cannot go green | failing tests on the base, flaky setup, missing env for tests | fix the base or the test setup, push |
| missing precondition | database, seeded user, service not available on the Mini | ask Andreas, or put the setup into the project's scripts |
| needs a browser login | goal artifact behind a login, no `browserState` for the project | Andreas saves the state file on the Mini |
| never-list | the task needs migrations, secrets, env files, production config, force-push | do that part yourself, then relabel |
| `handoff-limit` | plan too large for five sessions | split the plan into smaller packages or two plans |
| `timeout` / stalled | a hanging process (dev server, watch mode), 240 min per attempt | check the log line in the PR comment, fix the script |
| no session directory | no `PLAN.md` on the PR branch, and the run wrote none | commit the plan on the PR branch (without one the run writes its own, marked `no-plan`) |

After the fix: push to the branch, then swap `autopilot-blocked` back to `autopilot-ready`.
The next queue run continues from the kept worktree, not from scratch.

## 10. Feature branches: several sessions, one PR

For a feature too large for one plan, choose **feature branch** as branch mode in
`/autopilot-plan`. Each session commits straight onto the shared feature branch, no PR per
session; the feature branch gets one PR and one review when the last session is done.

```mermaid
flowchart LR
    B["base branch"] --> FB["feature/website-relaunch"]
    S1["session 1 PLAN.md"] -- "commits" --> FB
    S2["session 2 PLAN.md"] -- "commits" --> FB
    S3["session 3 PLAN.md"] -- "commits" --> FB
    FB -- "after the last session" --> PR["one PR, one review"]
```

There is no PR label to hand over a feature-branch session. The hand-over is pushing the
feature branch and adding the item to the queue with `mission-control add <repo> <session
dir>` on the Mini; ask Andreas (or anyone with SSH access through `/mission-control`).

## 11. Rules and limits

- **The plan is the whole spec.** The run sees `PLAN.md`, not the ticket history or your
  Slack thread. Put everything that matters into the plan.
- **No questions during the run.** Open points are decided conservatively and logged in
  `DECISIONS.md`.
- **Done means the goal artifact works**, verified in the running app. "Wired but off by
  default" is not done.
- **Never-list**: no force-push, no `migrations/`, no secrets or env files, no production
  config, no CI credentials, no other people's branches. A task that needs one of these
  ends blocked.
- **Docs are part of done.** The run updates README, `docs/`, `CLAUDE.md` and doc comments
  its change made stale.
- **Limits per item:** budget per attempt $100 on Sonnet, $120 on Opus; 240 minutes per
  attempt, five restarts after a hand-off, stall kill after 80 minutes without a tool call
  or commit.
- **Model setup:** planning on Fable (Opus is fine) in your session; the run on the plan's
  `Model:`, Sonnet (default, always at effort `xhigh` or `max`, Opus as fallback) or Opus
  (no fallback), with Fable as advisor either way; the final reviewer on Opus.

## 12. Cheat sheet

```
# once per project
/autopilot init                        # gate, hooks, labels; commit the result

# per ticket
/evelan:question-me                    # optional: when the shape is still open
/autopilot-plan WEB-1095               # plan with you in the loop
  → answer "hand to the queue"         # draft PR, label autopilot-ready

# afterwards, on GitHub
autopilot-done     → review REPORT.md, DECISIONS.md, MANUAL_TESTING.md, diff; merge
autopilot-blocked  → fix the cause, push, relabel autopilot-ready
claude-re-review   → one more Claude bot review after your own changes
```

Questions about the queue, a repo that is not picked up, or a login state file: Andreas.
