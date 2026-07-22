# Report - Codex delegation skills

**Date:** 2026-07-23
**Branch:** `feat/codex-delegation-skills`
**Topic:** Let Claude Code delegate to the local Codex CLI - a focused cross-model code review and a general-purpose delegation.

Spec and plan (source of truth, already committed before this session):
- Spec: [../../../specs/2026-07-22-codex-delegation-skills-design.md](../../../specs/2026-07-22-codex-delegation-skills-design.md)
- Plan: [../../../plans/2026-07-22-codex-delegation-skills.md](../../../plans/2026-07-22-codex-delegation-skills.md)

## Shipped

| # | Deliverable | Commit |
|---|---|---|
| 1 | `bin/codex-cli` resolver wrapper + `bin/codex-cli.test.sh` (5 tests) | `cc55237` |
| 2 | `skills/codex-review/SKILL.md` (native `codex review`, raw passthrough) | `790dbd9` |
| 3 | `commands/codex-review.md` (`/codex-review`) | `3537546` |
| 4 | `skills/codex-ask/SKILL.md` (`codex exec`, workspace-write, stdin brief) | `8c4f873` |
| 5 | autopilot step 6 on-demand cross-model review bullet | `650307e` |
| 6 | README (codex-review, codex-ask + backfilled preview, codex-imagegen) | `239625b` |
| 6 | plugin.json version bump 1.2.1 -> 1.3.0 | `a1b1fea` |

## Verification (all run and green)

- `bash bin/codex-cli.test.sh` -> `PASS=5 FAIL=0` (resolution order incl. not-found/exit-127, verbatim arg forwarding).
- `bin/codex-cli --version` -> `codex-cli 0.144.0-alpha.4` (real binary resolves via Codex.app; not on PATH otherwise).
- `bash skills/autopilot/hooks/autopilot-gate.test.sh` -> `PASS=4 FAIL=0` (unchanged, still green after the one-bullet edit).
- `python3 -m json.tool` on `plugin.json` and `marketplace.json` -> both parse.
- Frontmatter sweep over all 8 skills + the command -> all valid.
- No em dash character in any new/edited content; German phrases use proper umlauts.
- Git records `bin/codex-cli` as mode `100755` (executable bit preserved).

## Review

`evelan:autopilot-reviewer` (fresh context) against `git diff main..HEAD` + plan + spec:
**VERDICT PASS, zero findings.** It independently re-ran the gate and confirmed the resolution
order, explicit-only triggering on both skills, the spec-exact `codex-ask` invocation
(`--sandbox workspace-write -c approval_policy=on-request -c approvals_reviewer=auto_review -o`,
brief on stdin via bare `-`), write-safety (pre-run snapshot, dirty-tree warning, post-run
status + diffstat), and the native `codex review` scope/empty-diff/raw-passthrough behaviour.

## Manual testing (genuinely not doable headless)

One check from the plan (Task 7, Step 3) is interactive and cannot run in this non-interactive
session: launching `claude --plugin-dir <repo>` and observing live that the trigger phrases fire
and that a generic "review my changes" does NOT invoke `codex-review`. The substance of it is
covered statically - the descriptions carry the explicit-only triggers and the reviewer verified
them - but the live in-session trigger behaviour should be eyeballed once in a fresh session.
See [MANUAL_TESTING.md](./MANUAL_TESTING.md).

## CI

No `.github/workflows` in this repo - there is no CI pipeline to watch. The gate is the local
shell test scripts + manifest/frontmatter validation, all green above.

## Open items

- PR link to be filled in after `gh pr create` (INDEX.md and this report reference it as PENDING).
- Merge is Andreas' call (PR flow, no auto-merge).
