# `/autopilot init` — set up the per-project hard gate

Goal: enable the deterministic Stop-hook gate in the **current** project, safely and
idempotently. Never overwrite existing config.

## Steps

### 1. Detect the package manager (first hit wins)
1. `packageManager` field in `package.json` (`pnpm@…` → pnpm, `yarn@…` → yarn, `bun@…` → bun, `npm@…` → npm).
2. Lockfile: `pnpm-lock.yaml` → pnpm; `yarn.lock` → yarn; `bun.lockb`/`bun.lock` → bun; `package-lock.json` → npm.
3. Fallback → `npm`.

Run verbs: npm/pnpm/yarn use `<pm> run <script>` (npm/pnpm) — for scripts; tests run as
`<pm> test`. (yarn/bun verb edge cases: verify against the project; npm + pnpm are primary.)

### 2. Select gate steps from `package.json` `scripts` (include only what exists)
Order: typecheck → lint → test (+ build for the full gate only).
- typecheck: `typecheck` or `type-check` script; else `tsc --noEmit` if `tsconfig.json` exists; else skip.
- lint: `lint` script; else skip.
- test: `test` script; else skip (run-mode bootstraps a missing runner — init wires only what is there).
Compose the **cheap gate** string (no build), e.g. `pnpm run typecheck && pnpm run lint && pnpm test`.

### 3. Write `.claude/autopilot.json`
```json
{ "gate": "<composed cheap gate>" }
```
This is the single source of truth read by the hook and the run-mode orchestrator. If the
file exists with a different gate, show the diff and keep the existing one unless the detected
commands are clearly better — explain what you chose.

### 4. Copy the hook
Copy `<plugin>/skills/autopilot/hooks/autopilot-gate.sh` to `.claude/hooks/autopilot-gate.sh`
and `chmod +x` it. (Use `${CLAUDE_PLUGIN_ROOT}` to locate the plugin source.)

### 5. Safe-merge the Stop hook into `.claude/settings.json`
- Read the existing `.claude/settings.json` (create `{}` if absent).
- Merge ONLY the `Stop` block from `references/settings-snippet.json`. Preserve every other key
  and any existing hooks (append, do not replace). If the autopilot Stop hook is already
  present, change nothing (idempotent).
- Use `jq` for the merge when available; otherwise edit carefully and re-validate with `jq .`.

### 6. Add the sentinel to `.gitignore`
Ensure `.claude/.autopilot-active` is gitignored (it is a transient runtime flag).

### 7. Report
Print: detected package manager, the resolved gate command, the files created/modified, and
whether the merge was a no-op (already initialized).
