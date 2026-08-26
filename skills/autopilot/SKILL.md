---
name: autopilot
description: Use for autonomous, unattended development of one topic — spec → plan → TDD → adversarial review → quality gate → PR. Triggers on "/autopilot", "autopilot", "autonom umsetzen", "autonome Session", "arbeite das selbstständig ab", "setze das eigenständig um". Also handles "autopilot init" to set up the per-project quality-gate hook.
user-invocable: true
argument-hint: "[init | <task | TICKET-KEY | spec file | session directory>]   (add 'with sonnet' for cost-efficient implementation, 'defer PR' to skip push/PR)"
---

# Autopilot

You run **unattended**: no human will answer questions until the session is reviewed.
Optimize for **correct, reviewed, committed, and COMPLETE** work — never volume. One fully
verified, green-CI, merge-ready PR that **actually finishes its topic** is the goal.

**Definition of done (non-negotiable):** a topic is done only when the feature **works end to
end for the user** and *you have verified that yourself* — not merely when the gate is green.
"Wired but dormant", "off by default", "the binary/model still has to be staged", "thresholds
still need tuning", or "left as a MANUAL_TESTING step" do **NOT** count as done. If you cannot
make it fully work, you do not ship it as done (see Stop conditions) — you never hand the user
back a half-feature to finish and re-verify.

**Effort is never a reason to stop, shrink, defer, or descope.** "Too much work", "large",
"open-ended", "longer-term", "deeper lever", or "out of scope for one run" are **forbidden**
justifications — you exist to do the work regardless of how much it is. If the topic is big,
plan it across the whole session and build ALL of it. The ONLY things you may not do are the
genuine external blockers on the never/blocked list (a purchase, a human-only design asset, or
input that truly cannot be produced in this environment) — nothing else, and never "effort".

**Input:** `$ARGUMENTS`

## Routing

- If `$ARGUMENTS` begins with `init` → **Init mode**: follow `references/init.md` exactly and stop.
- Otherwise → **Run mode** (below).

## Operating principles (non-negotiable)

- **You are not the verification loop.** Every change must pass a gate that *you* run and read.
- **Never assert success.** Show evidence — the exact command and its output.
- **Prefer reversible actions.** NEVER force-push, edit `migrations/`, secrets, env files,
  production config, or CI credentials, and never touch other people's branches. A task needing
  any of these is skipped and logged.
- **One session = one topic = one branch = one PR.** All work packages are commits on that one branch.
- **No questions — decide.** On ambiguity, pick the conservative, easily-reversible option and
  record it in `DECISIONS.md`.
- **Finish or swap — never ship a half.** Deliver the WHOLE feature, working and verified. If a
  genuine external blocker (a purchase, a human-only asset, or input data that truly cannot be
  produced in this environment) stops you from finishing, do NOT ship a partial/dormant version
  and mark it done: abandon that topic cleanly, report the exact blocker at the TOP of
  `REPORT.md`, and pick a DIFFERENT fully-completable topic so the session still delivers
  something whole. A half-feature marked "done" is a session FAILURE, not a partial success.
- **Do the doable verification yourself.** If your environment can run the app, stage a
  binary/model, or exercise the feature — e.g. a local desktop session that has the sidecars and
  real recordings present — you MUST. Device/binary/data steps that ARE possible here may not be
  punted to `MANUAL_TESTING.md`; that file is only for steps genuinely impossible in this
  environment (a purchased cert, other-OS hardware). "Device-bound" is not an excuse when the
  device is right here.

## Use Superpowers skills first (when installed)

For each phase, if the matching Superpowers skill is installed, **invoke it and follow its
workflow** — it takes precedence over the inline instructions here, which are the fallback when
it is absent. Do not hard-depend on Superpowers. Where a Superpowers skill would ask the user a
question, do not pause — decide conservatively (see "No questions — decide") and log it in
`DECISIONS.md`.

| Phase | Superpowers skill |
| --- | --- |
| 0 — spec / rough idea | `superpowers:brainstorming` |
| 2 — isolated workspace | `superpowers:using-git-worktrees` |
| 4 — plan | `superpowers:writing-plans` |
| 5 — implement | `superpowers:test-driven-development` (+ `superpowers:subagent-driven-development` when delegating packages) |
| 5/7 — failures, flaky tests, bugs | `superpowers:systematic-debugging` |
| 6 — review | `superpowers:requesting-code-review` |
| 11 — finish / PR | `superpowers:finishing-a-development-branch` |

## Model strategy

- **You (the session lead) run at the session model.** You never choose it: standalone it
  is simply what the session was started with; dispatched as a subagent it is what the
  coordinator's model override says (mission control passes Opus). Your job: explore, spec,
  plan, review adjudication, all decisions, commit — plus PR/CI unless the run is defer-PR
  (phase 11).
- **Implementation:** by default you implement directly. **Only if the prompt signals cost/speed
  intent** — "with sonnet", "cost-efficient", "fast", "cheap" (DE: "mit Sonnet",
  "kosteneffizient", "schnell", "günstig") — delegate each work package to the
  `evelan:autopilot-implementer` subagent (Sonnet). Inspect its returned block; resolve any
  `needs_review` item yourself before accepting the package.
- **Review:** always use the `evelan:autopilot-reviewer` subagent (fresh context).

## Run-mode workflow

Work ONE topic end to end. Phases run in order per package; a trivial one-line task may collapse them.

### 0. Resolve input (cascade)
↳ Superpowers (if installed): `superpowers:brainstorming` to shape the spec.
0. A **prepared session directory** is provided (a `docs/autopilot/sessions/<slug>/` path
   with a `PLAN.md`, e.g. from a mission-control coordinator) → adopt it verbatim as THIS
   session's artifact folder and its `PLAN.md` as the plan. If the path lies outside your
   working tree (fresh worktree), copy the folder in first; it gets committed with the
   session. A **goal artifact** stated in that plan is binding for phase 9.
   **Continuation:** if that directory already holds session artifacts and a session branch
   for it exists, you are CONTINUING that session — check out the existing branch, keep all
   finished work, apply the feedback from the dispatch prompt, update `PLAN.md` statuses
   and `REPORT.md` in place, and do NOT create a new branch or a new `INDEX.md` entry
   (amend the existing line only if the outcome changed).
1. A spec is provided / referenced / already in the repo (`SPEC.md` or equivalent) → use it.
2. Only a rough idea → write a self-contained spec into `PLAN.md` (problem/goal, scope + non-goals,
   functional requirements with acceptance criteria, affected areas, edge/error cases). Answer
   open questions with conservative assumptions → `DECISIONS.md`.
3. No task given at all → derive the task from project context (open TODOs, leftover plan files,
   issues, obviously unfinished features); record the choice in `DECISIONS.md`; then proceed as (2).

### 1. Project context & gate
Establish the gate command first. If `.claude/autopilot.json` exists, use its `gate`. Otherwise
**detect the package manager** — pnpm (`pnpm-lock.yaml` or `packageManager: pnpm@…`), npm
(`package-lock.json`), yarn (`yarn.lock`), or bun (`bun.lockb`) — and compose the gate from the
scripts that actually exist, using that PM's run verb (see `references/init.md` for the full
algorithm). Examples: pnpm → `pnpm run typecheck && pnpm run lint && pnpm test`; npm →
`npm run typecheck && npm run lint && npm test`. Never assume the PM — read the lockfile/manifest.
**Persist the resolved command to `.claude/autopilot.json`** (create it if missing) so the
implementer and reviewer subagents and the Stop hook all use the exact same package manager. If a
test runner is missing, set one up minimally and project-consistently **before** implementing.
Existing conventions win over generic best practices.

**Sentinel for the optional Stop-hook hard gate:** if the project has the gate installed
(`.claude/hooks/autopilot-gate.sh` + Stop hook in `.claude/settings.json`), create
`.claude/.autopilot-active` NOW — the hook is inert without it. You own its lifecycle:
remove it in phase 12 AND on every abort path (Stop conditions). Never leave it behind — a
stale sentinel gates every future session in that project.

### 2. Branch
Create one session branch following the project's convention:
- Prefix: infer from existing branches / git history (`git branch -a`, recent merges); fall back to `feature/`.
- Ticket: if the prompt has a key (`DNA-901`, `WEB-123`, `PAUL-…`, `EL-…`), include it (original casing) → `<prefix>/DNA-901-<slug>`; else `<prefix>/<slug>`.
- Slug: lowercase, hyphen-separated, from the topic.

### 3. Explore (read-only)
Delegate wide reading to a subagent so it does not flood your context. Get back files, patterns,
risks — not full file contents.

### 4. Plan → `PLAN.md`
↳ Superpowers (if installed): `superpowers:writing-plans`.
Self-contained: files/interfaces touched, explicit out-of-scope, concrete verification criteria
(test cases with inputs/expected outputs, expected typecheck/lint/build result), and an
end-to-end check. Break into small, dependency-ordered packages, each with a Definition of Done
and a status marker `[ ] / [~] / [x] / [!]`. **The packages together must fully deliver the
topic** — do NOT carve a feature into a shippable sliver and park the rest under "out-of-scope".
A non-goal is legitimate only when it is genuinely *unrelated* scope, never a core part of the
same feature deferred because it is large, device-bound, or open-ended. Every package's
Definition of Done is "the user gets this working", not "the code compiles and a manual step is
written down".

### 5. Implement (TDD)
↳ Superpowers (if installed): `superpowers:test-driven-development`; `superpowers:systematic-debugging` for any failure.
Per package: failing test first (confirm it fails for the right reason) → minimal code to green →
refactor. Everything sensibly unit-testable gets tests (utils, hooks, business logic, data
transforms, API handlers, validation); UI components are tested by behavior. Run the **cheap gate**
(typecheck/lint/full test suite) after each meaningful change and show its output. What cannot be
**auto**-tested but **can** be exercised in this environment, you verify **yourself** — run the
app/sidecar, stage the needed binary/model, drive the feature end to end — and show the evidence.
Only steps genuinely impossible here (a purchased cert, other-OS hardware) go to
`MANUAL_TESTING.md`; effort, size, or a vague "device-bound" are NOT reasons to punt when the
device/binary/data is available. In Sonnet mode, delegate the package to
`evelan:autopilot-implementer`.

### 6. Review (fresh context, hybrid depth)
↳ Superpowers (if installed): `superpowers:requesting-code-review` to frame the review.
- **Always:** dispatch `evelan:autopilot-reviewer` with the diff + `PLAN.md`. Fix every gap it
  reports that affects correctness, requirements, or safety — test-driven, then re-gate.
- **On demand:** if the prompt asks ("thorough review", "architecture review", "Code-Qualität") or
  the diff is large, additionally fan out **clean-code** and **reusability** lenses as parallel
  subagents. Prioritize findings (critical / important / nice-to-have); fix critical + important,
  record nice-to-have in `REPORT.md` with rationale.
- **On demand (cross-model via Codex):** if the prompt asks for it ("nutze Codex als Reviewer",
  "Codex als Reviewer", "use Codex as reviewer", "mit Codex reviewen", "Cross-Model-Review"),
  additionally run a Codex review via the `evelan:codex-review` skill (`codex review --base <base>`)
  on top of the standard `autopilot-reviewer`, and fix real gaps it reports like any other.
  **Fallback (required):** if Codex is rate-limited or unavailable (see that skill's limit
  signatures) or the Codex CLI is missing, do NOT fail the review - the standard
  `evelan:autopilot-reviewer` has already run, so proceed on its result and note in `REPORT.md`
  that the Codex cross-model pass was skipped and why. Never on a default run.
- Max 2 review cycles; unresolved real gaps → mark the package `[!]` and log it. **Any `[!]`
  package blocks the done claim:** surface it at the TOP of `REPORT.md` and in the PR
  description; in a defer-PR run, hand the session back as **incomplete**, never as done.

### 7. Docs + full gate + commit
Before committing the package, update documentation **directly affected** by this change —
inline docs / JSDoc / docstrings, and the doc file for the touched area if one exists. Treat
this as part of the gate: a package is not done if it left its own docs stale. Keep it
**proportionate** — skip for trivial bugfixes, internal refactors, or UI-only tweaks that
change no documented behavior. Then run the cheap gate + `build`; paste the summary. Only if
fully green: commit (Conventional Commits, referencing the topic/ticket).

### 8. Keep `PLAN.md` / `DECISIONS.md` current.

### At session end (topic fully implemented):

### 9. UI / E2E verification (when applicable)
Only when ALL hold: (a) it is a web UI, (b) a local dev server is startable (`npm run dev`),
(c) browser/preview tooling is available. Then: start the dev server, drive the acceptance
criteria, submit forms with valid AND invalid input, provoke error states, check console +
network for errors, work through browser-checkable `MANUAL_TESTING.md` items, fix findings
test-driven and re-verify, stop the server cleanly. If a precondition is missing → skip and
record WHICH precondition was missing in `REPORT.md`.

**Exception — a goal artifact makes this mandatory:** when the plan/spec defines a goal
artifact (a user-verifiable deliverable: the feature working in the running app, a generated
report, a finished document), exercising that artifact end to end is NOT skippable. A missing
precondition is then a blocker to resolve (start the server, stage the data), and a failing
exercise means the topic is **not done** — fix or report incomplete, never skip.

### 10. Documentation review (before the PR)
If the session added or changed user-facing functionality, behavior, config, or public API,
update the general project docs accordingly — README and any other top-level docs that mention
the affected area. If a **new feature** was built, add a doc entry under `docs/` following the
existing scheme/structure already used there. Proportionate — skip entirely when nothing
documented changed (small bugs, internal refactors, UI-only tweaks). This is the project's own
documentation, separate from the per-session `docs/autopilot/` artifacts.

### 11. PR + CI
**Defer-PR mode:** when the prompt says "defer PR" / "no push" / "kein Push" (mission-control
dispatches always do), SKIP this phase entirely — never push, never open a PR. Finish phases
10 and 12, then report the branch name and final state; the coordinator owns push, PR and CI
after its own verification.

Otherwise: push the branch and open **one PR** automatically (GitHub `gh pr create`, ticket
key in title; legacy Bitbucket deployments via API). The PR is for review — **never
auto-merge**. Then wait for CI (`gh run watch`); on red, read `gh run view --log-failed`,
fix, re-push, re-check until green and merge-ready.

**A green `review` check is NOT "review considered".** When a PR review bot runs on the
repo, its findings live in the PR comments, not in the check status. Before calling the PR
merge-ready, fetch and triage BOTH comment surfaces
(`gh api "repos/<owner>/<repo>/pulls/<n>/comments" --paginate` and the same under
`issues/<n>/comments`, filtered to the bot's login) — verify each finding, fix or rebut it
with evidence, never ignore it. Anchor fixes in named invariants or recorded decisions
(DECISIONS.md), not in review appeasement: a finding that reverses an earlier round's
change or contradicts a recorded decision is escalated (to the coordinator in a defer-PR
run, to the user otherwise), not implemented — repeated AI review rounds on the same code
otherwise oscillate. (Learned 2026-08-27, paul PR #117.)

### 12. Finalize artifacts
Write `REPORT.md`, prepend the session one-liner to `docs/autopilot/INDEX.md`, and remove
the Stop-hook sentinel (`.claude/.autopilot-active`) if you created it in phase 1.

## Stop conditions (abort the whole session, write `REPORT.md`)
- The gate cannot be made green without a destructive action or human input.
- The task would require anything on the never-list.
- No package remains implementable.

On EVERY abort: commit the session artifacts (`REPORT.md` with the blocker at the top) to the
session branch so nothing is lost, and remove the Stop-hook sentinel if you created it.

**Never fake completion.** A topic you can only *partially* finish — dormant, off by default,
verification punted for non-genuine reasons, or descoped for effort/size — is **not** committed
as done. Either finish it fully, or (if a genuine external blocker stops you) drop it, report the
blocker at the top of `REPORT.md`, and swap to a topic you CAN finish end to end. Shipping a
half-feature and marking it done is itself a session failure — do not do it.

## Artifacts — `docs/autopilot/` (committed, part of the PR)

```
docs/autopilot/
  INDEX.md                                # newest-first, one line + link per session
  sessions/YYYY-MM-DD-<slug>/
    PLAN.md          # spec + plan + verification criteria + per-package status
    DECISIONS.md     # conservative assumptions, each with rationale
    REPORT.md        # shipped work, test coverage, review findings (fixed + deferred), PR link, CI status, open items
    MANUAL_TESTING.md  # only when something cannot be auto-tested
```

`INDEX.md` uses an insert marker; prepend, never sort or rewrite:
```
<!-- NEW ENTRIES GO IMMEDIATELY BELOW THIS LINE -->
- **YYYY-MM-DD HH:MM** — <title> — <one-line summary> — [PR](<url>) [→](./sessions/<slug>/REPORT.md)
```
Create `docs/autopilot/` and seed `INDEX.md` with that header + marker if missing.

## Permissions
For unattended runs, `--permission-mode auto` is recommended (the user sets this at launch — you
cannot change it). When you run as a dispatched subagent (mission-control), you inherit the
coordinator session's permission mode — the coordinator must have been launched permissive.
The Stop-hook hard gate (via `/autopilot init`) is optional and complements your own gate runs.
