# `/autopilot init` - set up the per-project hooks

Goal: enable four deterministic hooks in the **current** project, safely and idempotently.
Never overwrite existing config.

1. **Stop-hook hard gate** (`autopilot-gate.sh`, Stop): blocks the turn from ending while
   the gate is red; after three consecutive blocks it allows the stop with the reason on stderr.
   Active while `.claude/.autopilot-active` exists.
   Needs the gate in `.claude/autopilot.json`; counts blocks in `.claude/.autopilot-gate-blocks`.
2. **Gate-output filter** (`autopilot-gate-filter.sh`, PreToolUse on Bash): rewrites
   test/lint/typecheck/build commands to show failures plus summary, keeps the exit status,
   appends one evidence line per run to `.claude/autopilot-gate.log`.
   Active in every session once `.claude/autopilot.json` exists; `# raw` in a command bypasses it.
   Needs `jq`.
3. **Context-budget hand-off** (`autopilot-context-budget.sh`, PostToolUse on every tool):
   measures the context the next turn will carry and, above the budget (default 500k tokens,
   `contextBudget` in `.claude/autopilot.json` or `AUTOPILOT_CONTEXT_BUDGET`), injects the
   instruction to write `HANDOFF.md`, commit and end the turn; rewrites
   `.claude/.autopilot-status` after every tool call (read by `mission-control status` and
   the watchdog).
   Active while `.claude/.autopilot-active` exists or inside a subagent; silent otherwise.
   Needs `jq` and the transcript of the agent it runs in (an instant hit in a fresh session
   means the wrong transcript was measured; do not raise the budget).
4. **Post-compaction pointer** (`autopilot-session-start.sh`, SessionStart, matcher `compact`):
   prints where the newest session's `PLAN.md` and `HANDOFF.md` live.
   Active only after a compaction.
   Needs `docs/autopilot/sessions/` to exist.

## Steps

### 1. Detect the package manager (first hit wins)
1. `packageManager` field in `package.json` (`pnpm@…` → pnpm, `yarn@…` → yarn, `bun@…` → bun, `npm@…` → npm).
2. Lockfile: `pnpm-lock.yaml` → pnpm; `yarn.lock` → yarn; `bun.lockb`/`bun.lock` → bun; `package-lock.json` → npm.
3. Fallback → `npm`.

Run verbs per package manager:

| PM   | script            | tests      |
| ---- | ----------------- | ---------- |
| npm  | `npm run <name>`  | `npm test` |
| pnpm | `pnpm run <name>` | `pnpm test`|
| yarn | `yarn <name>`     | `yarn test`|
| bun  | `bun run <name>`  | `bun test` |

When unsure (exotic setups), verify against the project's own CI/scripts; npm + pnpm are primary.

### 2. Select gate steps from `package.json` `scripts` (include only what exists)
Order: typecheck → lint → test (+ build for the full gate only).
- typecheck: `typecheck` or `type-check` script; else `tsc --noEmit` if `tsconfig.json` exists; else skip.
- lint: `lint` script; else skip.
- test: `test` script; else skip (run-mode bootstraps a missing runner - init wires only what is there).
Compose the **cheap gate** string (no build), e.g. `pnpm run typecheck && pnpm run lint && pnpm test`.
Prefer quiet reporters where the runner supports them and the project's scripts do not already
set one (vitest/jest: `-- --reporter=dot`; playwright: `--reporter=dot`). Check with the
runner's `--help` before adding a flag; never break an existing script.

### 3. Write `.claude/autopilot.json`
```json
{ "gate": "<composed cheap gate>" }
```
If the file exists with a different gate, show the diff and keep the existing one unless the
detected commands are clearly better - explain what you chose. Optional second key `gateFull`:
the project's full gate (e.g. `npm run gate:full` with integration tests), run once before
the push. Wire it only when the project already has such a script; never invent one.

### 4. Copy the hooks
Copy `autopilot-gate.sh`, `autopilot-gate-filter.sh`, `autopilot-context-budget.sh` and
`autopilot-session-start.sh` from `<plugin>/skills/autopilot/hooks/` to `.claude/hooks/` and
`chmod +x` all four. (Use `${CLAUDE_PLUGIN_ROOT}` to locate the plugin source.) If a copy already exists and
differs, show the diff and replace it only when the project copy is an older plugin version
(no local edits); otherwise keep it and say so.

### 5. Safe-merge the hooks into `.claude/settings.json`
- Read the existing `.claude/settings.json` (create `{}` if absent).
- Merge ONLY the `Stop`, `PreToolUse`, `PostToolUse` and `SessionStart` blocks from
  `references/settings-snippet.json`.
  Preserve every other key and any existing hooks (append, do not replace). If a block is
  already present, change nothing for it (idempotent).
- The filter and context-budget hooks need `jq` on the machine; without it they are no-ops
  (`{}`). Say so in the report when `jq` is missing.
- Use `jq` for the merge when available; otherwise edit carefully and re-validate with `jq .`.

### 6. Add the runtime files to `.gitignore`
Ensure `.claude/.autopilot-active` (transient sentinel), `.claude/.autopilot-gate-blocks`
(block counter), `.claude/.autopilot-status` (the run's status line) and
`.claude/autopilot-gate.log` (machine-local evidence log) are gitignored.

### 6b. Browser: `agent-browser`
Run `agent-browser --version`. Missing → print the two install lines and continue:
`npm install -g agent-browser` then `agent-browser install` (downloads Chrome for Testing).
Every headless run needs it for the goal-artifact check (`references/browser.md`); the
queue machine (office Mini) needs it too.

When the goal artifact of this project needs a logged-in session (a dashboard, an admin
area), the project gets a state file, saved once by hand and kept outside the repo:

```
mkdir -p ~/.claude/autopilot/<repo basename>
agent-browser --headed open <login url>       # log in by hand in the window that opens
agent-browser state save ~/.claude/autopilot/<repo basename>/state.json
agent-browser close
```

Then write `"browserState": "~/.claude/autopilot/<repo basename>/state.json"` into
`.claude/autopilot.json` (the run replaces the leading `~` with `$HOME`). Print this recipe when the project has a
login route (`grep -rl -m 1 "signIn\|/login\|/sign-in" app src 2>/dev/null` finds one) and
no `browserState` yet; do not create the file yourself. The state file must exist on every
machine that runs the queue for this project.

### 6c. Ticket updates: `jira`
A run sets the ticket In Progress and comments the result through the `jira` script (plugin
`bin/`), which reads `~/.claude/jira/env` (mode 600: `JIRA_SITE`, `JIRA_EMAIL`,
`JIRA_TOKEN`). The file must exist on every machine that runs the queue (the office Mini,
the MacBook), not only here. Run `jira doctor`; when it fails, print its output (it names
the file and the three variables) and continue: a run without the file skips the ticket
update and says so in `REPORT.md`.

### 7. Verify and report
Hooks merged into `settings.json` take effect at the next session start, so test the scripts
directly. Write the gate command into a temp file preceded by a `# CMD: <gate>` line, run
`bash .claude/hooks/autopilot-gate-filter.sh run <file>`, and confirm the output starts with
`GATE GREEN` or `GATE RED` and `.claude/autopilot-gate.log` gained a line whose `tree=` equals
`bash .claude/hooks/autopilot-gate-filter.sh tree`. Run the budget hook's own test suite from the plugin
(`bash "${CLAUDE_PLUGIN_ROOT}/skills/autopilot/hooks/autopilot-context-budget.test.sh"`) and
confirm `FAIL=0`; then write `{"transcript_path":"<this session's transcript>","agent_id":"init-check"}`
to a temp file, run `bash .claude/hooks/autopilot-context-budget.sh < <file>` and confirm it
prints `{}` (no such subagent transcript exists, so it must stay silent).

**Review bot check.** If `.github/workflows/claude-code-review.yml` exists, the run will wait
for its comments and request re-reviews with a label (autopilot skill, step 6). Confirm the
label exists: `gh label list --search claude-re-review`. Missing → create it
(`gh label create claude-re-review --description "Request one more full Claude review of this PR's current state" --color 5319E7`)
and say so; a missing label makes every re-review request fail silently. If the workflow
uses another label name (read the workflow file), report it: the run follows the project's
`CLAUDE.md`, which must name it.

**Queue labels.** Run `mission-control labels` in the project: it creates `autopilot-ready`,
`autopilot-done` and `autopilot-blocked` when missing (colours and descriptions live in the
script), so a developer's hand-over from `/autopilot-plan` and the nightly queue can label PRs.

Then print: detected package manager, the resolved gate command and `gateFull` when wired,
the files created/modified, whether each merge was a no-op (already initialized), whether `jq`
is available, whether `agent-browser` is installed and whether a `browserState` is set or
recommended, whether `jira doctor` passed, whether a review workflow and its label were
found, and that the hooks become active in the next session.
