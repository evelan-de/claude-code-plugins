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
   measures the context the next turn will carry and, above the budget (default 250k tokens,
   `contextBudget` in `.claude/autopilot.json` or `AUTOPILOT_CONTEXT_BUDGET`), injects the
   instruction to write `HANDOFF.md`, commit and end the turn.
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
(block counter) and `.claude/autopilot-gate.log` (machine-local evidence log) are gitignored.

### 7. Verify and report
Hooks merged into `settings.json` take effect at the next session start, so test the scripts
directly. Write the gate command into a temp file preceded by a `# CMD: <gate>` line, run
`bash .claude/hooks/autopilot-gate-filter.sh run <file>`, and confirm the output starts with
`GATE GREEN` or `GATE RED` and `.claude/autopilot-gate.log` gained a line whose `tree=` equals
`bash .claude/hooks/autopilot-gate-filter.sh tree`. Run the budget hook's own test suite from the plugin
(`bash "${CLAUDE_PLUGIN_ROOT}/skills/autopilot/hooks/autopilot-context-budget.test.sh"`) and
confirm `FAIL=0`; then run the project copy once with a fake input
(`echo '{"transcript_path":"<this session's transcript>","agent_id":"init-check"}' | bash .claude/hooks/autopilot-context-budget.sh`)
and confirm it prints `{}` (no such subagent transcript exists, so it must stay silent).

**Review bot check.** If `.github/workflows/claude-code-review.yml` exists, the run will wait
for its comments and request re-reviews with a label (autopilot skill, step 6). Confirm the
label exists: `gh label list --search claude-re-review`. Missing → create it
(`gh label create claude-re-review --description "Request one more full Claude review of this PR's current state" --color 5319E7`)
and say so; a missing label makes every re-review request fail silently. If the workflow
uses another label name (read the workflow file), report it: the run follows the project's
`CLAUDE.md`, which must name it.

Then print: detected package manager, the resolved gate command and `gateFull` when wired,
the files created/modified, whether each merge was a no-op (already initialized), whether `jq`
is available, whether a review workflow and its label were found, and that the hooks become
active in the next session.
