# `PLAN.md` template

Path: `docs/autopilot/sessions/YYYY-MM-DD-<slug>/PLAN.md` (slug lowercase, hyphenated; ticket
key first when there is one). One file, no length cap. Length comes from the Implementation
and Tests sections, never from narrative.

```
# PLAN - <ticket key or topic> - <YYYY-MM-DD>
Branch: <prefix>/<KEY>-<slug>   Base: <integration branch>   Ticket: <key or none>   (prefix per the project's branch convention, else feat)
Branch mode: session | feature-branch <name>     PR: per session | none (feature branch reviewed as a whole)
Effort: medium   (low | medium | high | xhigh | max; the runner passes it as --effort)
Options: none   (or, comma-separated: defer PR, no Codex; the run reads them here)
Planned with: <model of the planning session>   Reviewed: yes (<n> findings folded in) | no (<reason>)
Sources: <spec, ADRs, docs the packages point to>

## Destination
<one paragraph: what the user gets when this plan is done>

## Goal artifact
<the user-verifiable deliverable, binding for the end check: e.g. "feature works in the
locally running app at <route>", "report at <path>". Name the browser checks the run performs
with agent-browser (routes, viewport, what must be visible) and whether a login state file
is needed (`browserState` in .claude/autopilot.json)>

## Scope / Non-goals
- in: ...
- out: ...

## Decisions
- <decision> - <reason>

## Seams
- <public interface the tests hit> - <prior art: existing test that does the same>

## Packages (dependency order; status [ ] [~] [x] [!])
### P1 [ ] <title>
Delivers: <the end-to-end behaviour the user gets, not a layer list>
Blocked by: none
Files: <paths as of today, new files marked (new)>   Seams: <from the list above>
Implementation:
1. `<path>:<line>` after the line `<anchor line, quoted verbatim>`: add
   `export function <name>(<params with types>): <return type>` - <flow in pseudo-code, one
   line per branch; the existing helper it reuses (`<path>:<name>`) and why>
2. `<path>:<line>` replace `<old expression>` with `<new expression>` - <reason>
3. `<path>` (new): <what it exports, the signature of each export, the shape of the data>
4. <catalog / config / schema change with the exact key and value>
Tests: `<test file>` (<runner>, run with `<exact command>`)
- `<test name>`: <input> → <expected output or effect>; hits seam <name>
- `<test name>`: <invalid input> → <expected error>
Verify: <exact commands and the expected lines; browser check: route, viewport, what is visible;
screenshot name>
Edge cases: <...>
### P2 [ ] <title>
Blocked by: P1
...

## Manual steps (only what this environment cannot do)
```

Rules for the Implementation steps:

- Every `path:line` and every quoted anchor was opened and read by the planner, at the tip of
  the base branch, on the day the plan is written. A step that names a line the planner did
  not read is a defect.
- Signatures name real types that exist in the codebase or in an installed dependency
  (checked in the file or in `node_modules/<pkg>/*.d.ts`); a type the step introduces is
  defined in the same step.
- Pseudo-code is the flow, not the code: branches, loops, what is returned, what is thrown.
  The run writes the code. A step that is one line of real code may show it.
- One step per file edit. A package with more than ~8 steps or more than ~6 files is two
  packages.
- Tests name the assertion, not the intent: `returns 404 for an unknown slug`, with the input
  and the expected value. "Covers the error path" is not a test.
- Never repeat what an existing test file already proves; point to it under Seams.
