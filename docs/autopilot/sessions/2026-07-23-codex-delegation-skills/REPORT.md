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

### Live Codex cross-model review (the skill reviewing its own PR)

Ran `codex-review` against the PR (`codex review --base origin/main`, model `gpt-5.6-sol`).
This dogfooding surfaced three real defects in the just-shipped skills, all fixed test-first
(each mechanism verified with a direct probe / scratch-repo experiment before the prose was
written):

1. **`codex-review` scope-vs-prompt (`a6a1970`)** - the CLI rejects a scope flag combined with a
   positional PROMPT (`--base`/`--uncommitted`/`--commit` each error "cannot be used with
   [PROMPT]"; confirmed by direct probe). The skill's Execution example did exactly that. Rewrote
   to document the two valid forms (scoped review, or focused review via stdin `-` with no scope
   flag). The focused form was then verified live (`codex review -` exit 0, real review; Codex
   confirmed the PROMPT-only description matches its behaviour).
2. **`codex-ask` change isolation (`8692fc3`)** - Codex flagged (P2) that the pre-run snapshot
   only recorded status + HEAD, so a dirty tree would mix the user's edits into "what Codex
   touched". A first fix (`git stash create` + untracked-name list) was itself reviewed by Codex,
   which found two further gaps (edits to pre-existing untracked files invisible; clean-tree +
   Codex-commit loses the baseline). Final fix: snapshot the full worktree into a tree object via
   a temp index outside the repo (`git add -A` + `git write-tree`) before and after, then diff the
   two trees. Verified in a scratch repo against exactly the flagged cases.
3. **Portable `mktemp` (both skills)** - the documented template `...-XXXXXX.log` is not
   randomized on macOS/BSD `mktemp` (X's must end the template), producing a literal filename that
   collided and actually broke the first review run. Fixed to X's-at-end in both skills.

### Second live Codex review (re-run on request)

A second `codex review --base origin/main` over the final PR surfaced two more issues in the
temp-index snapshot, both handled:

4. **[P1] empty-index-file claim (`4248c39`)** - Codex said a pre-created `mktemp` file as
   `GIT_INDEX_FILE` makes `git read-tree` fail "index file smaller than expected". **Did not
   reproduce** on git 2.50.1 (an empty index is treated as empty and repopulated - verified
   directly). Hardened anyway by switching to `mktemp -d` with a non-existent index path
   (`$SNAP_DIR/index`), which removes the fragility across git versions.
5. **[P2] ignored files (`4248c39`)** - valid: `git add -A` excludes `.gitignore`'d files, so the
   snapshot cannot cover them. Force-adding all ignored files (node_modules, build output) would be
   catastrophic, so the honest fix is to **narrow the documented guarantee** to git-visible files,
   with a note to check ignored artifacts separately.

Both verified in a scratch repo (isolation still correct: pre-existing untracked edits and Codex
commits handled; only Codex's changes reported).

### Follow-up feature: Codex-limit fallback (requested mid-session)

Added on Andreas' request (`71753b5`):
- `codex-review` skill gained a **fallback** section: when Codex exits non-zero with no usable
  review and the log matches a limit/availability signature (rate limit, quota, 429, auth, missing
  binary), report why and **review with Claude instead**, labelled as the fallback - never leave the
  user with no review. A benign line (e.g. `failed to renew cache TTL`) with a real review present
  is not treated as a limit.
- `autopilot` step 6 bullet now takes explicit "use Codex as reviewer" / "Codex als Reviewer"
  triggers and, on a Codex limit/unavailability, falls back to the standard `autopilot-reviewer`
  that already ran (noting the skip in `REPORT.md`).

The `codex-review` skill has now reviewed its own PR twice and every finding is resolved or
explicitly, evidence-backed rejected. No third round run; the two latest fixes are covered by the
scratch-repo verification above.

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

- PR: https://github.com/evelan-de/claude-code-plugins/pull/5
- Merge is Andreas' call (PR flow, no auto-merge).
