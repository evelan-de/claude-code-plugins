# `PLAN.md` template

Path: `docs/autopilot/sessions/YYYY-MM-DD-<slug>/PLAN.md` (slug lowercase, hyphenated; ticket
key first when there is one). One file, under 200 lines.

```
# PLAN - <ticket key or topic> - <YYYY-MM-DD>
Branch: <prefix>/<KEY>-<slug>   Base: <integration branch>   Ticket: <key or none>   (prefix per the project's branch convention, else feat)
Branch mode: session | feature-branch <name>     PR: per session | none (feature branch reviewed as a whole)
Effort: medium   (low | medium | high | xhigh | max; the launch line passes it as --effort)
Sources: <spec, ADRs, docs the packages point to>

## Destination
<one paragraph: what the user gets when this plan is done>

## Goal artifact
<the user-verifiable deliverable, binding for the end check: e.g. "feature works in the
locally running app at <route>", "report at <path>">

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
Files: <paths as of today>   Seams: <from the list above>
Verify: <test cases with inputs and expected outputs; typecheck/lint/build expectation>
Edge cases: <...>
### P2 [ ] <title>
Blocked by: P1
...

## Manual steps (only what this environment cannot do)
```
