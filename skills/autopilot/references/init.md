# `/autopilot init` - set up the per-project hooks

Goal: enable four deterministic hooks in the **current** project, safely and idempotently.
Never overwrite existing config.

1. **Stop-hook hard gate** (`autopilot-gate.sh`): blocks a standalone autopilot session from
   ending its turn while the gate is red. Sentinel-guarded, inert otherwise.
2. **Gate-output filter** (`autopilot-gate-filter.sh`, PreToolUse on Bash): rewrites
   test/lint/typecheck/build commands so the model sees failures plus the summary instead of
   the full runner output, keeps the exit status, and appends one evidence line per run to
   `.claude/autopilot-gate.log` (timestamp, HEAD, tree state, exit code, command). Active in
   every session of the project once `.claude/autopilot.json` exists; `# raw` in a command
   bypasses it.
3. **Context-budget hand-off** (`autopilot-context-budget.sh`, PostToolUse on every tool):
   reads the transcript of the agent it runs in after each tool call (inside a subagent:
   `<session>/subagents/agent-<agent_id>.jsonl`; the `transcript_path` in the hook input is
   always the main session's file and is only used in a standalone run), takes the context
   the next turn will carry, and once it exceeds the budget (default 250k tokens,
   `contextBudget` in `.claude/autopilot.json` or `AUTOPILOT_CONTEXT_BUDGET`) injects the
   instruction to write `HANDOFF.md`, commit, and return `STATUS: incomplete`. The reminder
   names the measured file. Active only inside subagents (hook input carries `agent_id`) or
   while the `.claude/.autopilot-active` sentinel exists; silent in interactive sessions.
   Do not raise the budget when a fresh lead hits it within minutes: a fresh lead starts at
   roughly 50-80k tokens, so an instant hit means the wrong transcript was measured.
4. **Post-compaction pointer** (`autopilot-session-start.sh`, SessionStart with matcher
   `compact`): if compaction happens anyway, re-injects where the session artifacts live.

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
If the
file exists with a different gate, show the diff and keep the existing one unless the detected
commands are clearly better - explain what you chose.

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
Ensure `.claude/.autopilot-active` (transient sentinel) and `.claude/autopilot-gate.log`
(machine-local evidence log) are gitignored.

### 7. Verify and report
Hooks merged into `settings.json` take effect at the next session start, so test the scripts
directly. Write the gate command into a temp file preceded by a `# CMD: <gate>` line, run
`bash .claude/hooks/autopilot-gate-filter.sh run <file>`, and confirm the output starts with
`GATE GREEN` or `GATE RED` and `.claude/autopilot-gate.log` gained a line whose `tree=` equals
`bash .claude/hooks/autopilot-gate-filter.sh tree`. Run the budget hook's own test suite from the plugin
(`bash "${CLAUDE_PLUGIN_ROOT}/skills/autopilot/hooks/autopilot-context-budget.test.sh"`) and
confirm `FAIL=0`; then run the project copy once with a fake input
(`echo '{"transcript_path":"<this session's transcript>","agent_id":"init-check"}' | bash .claude/hooks/autopilot-context-budget.sh`)
and confirm it prints `{}` (no such subagent transcript exists, so it must stay silent). Then print: detected package manager, the resolved gate command,
the files created/modified, whether each merge was a no-op (already initialized), whether `jq`
is available, and that the hooks become active in the next session.
