# `/autopilot init` — set up the per-project hooks

Goal: enable four deterministic hooks in the **current** project, safely and idempotently.
Never overwrite existing config.

1. **Stop-hook hard gate** (`autopilot-gate.sh`): blocks a standalone autopilot session from
   ending its turn while the gate is red. Sentinel-guarded, inert otherwise.
2. **Gate-output filter** (`autopilot-gate-filter.sh`, PreToolUse on Bash): rewrites
   test/lint/typecheck/build commands so the model sees failures plus the summary instead of
   the full runner output, keeps the exit status, and appends one evidence line per run to
   `.claude/autopilot-gate.log` (timestamp, HEAD, tree state, exit code, command). Active in
   every session of the project once `.claude/autopilot.json` exists; `# raw` in a command
   bypasses it. Measured motivation: autopilot subagents ran the gate 3-4 times per package
   with full output in context (267 vitest runs in one session).
3. **Context-budget hand-off** (`autopilot-context-budget.sh`, PostToolUse on every tool):
   reads the session's own transcript after each tool call, sums the context the next turn
   will carry, and once it exceeds the budget (default 250k tokens, `contextBudget` in
   `.claude/autopilot.json` or `AUTOPILOT_CONTEXT_BUDGET`) injects the instruction to write
   `HANDOFF.md`, commit, and return `STATUS: incomplete`. This replaces auto-compaction as
   the context limiter: deterministic, no lossy model summary.
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
- test: `test` script; else skip (run-mode bootstraps a missing runner — init wires only what is there).
Compose the **cheap gate** string (no build), e.g. `pnpm run typecheck && pnpm run lint && pnpm test`.
Prefer quiet reporters where the runner supports them and the project's scripts do not already
set one (vitest/jest: `-- --reporter=dot`; playwright: `--reporter=dot`). Check with the
runner's `--help` before adding a flag; never break an existing script.

### 3. Write `.claude/autopilot.json`
```json
{ "gate": "<composed cheap gate>" }
```
This is the single source of truth read by the hook and the run-mode orchestrator. If the
file exists with a different gate, show the diff and keep the existing one unless the detected
commands are clearly better — explain what you chose.

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
Run one filtered command end to end (e.g. the gate itself) and confirm the output starts with
`GATE GREEN` or `GATE RED` and that `.claude/autopilot-gate.log` gained a line. Run the
context-budget hook once by hand with a fake input whose transcript is the current session's
(`echo '{"transcript_path":"<path>","session_id":"init-check"}' | .claude/hooks/autopilot-context-budget.sh`)
and confirm it prints `{}` (below budget). Then print:
detected package manager, the resolved gate command, the files created/modified, whether each
merge was a no-op (already initialized), and whether `jq` is available.
