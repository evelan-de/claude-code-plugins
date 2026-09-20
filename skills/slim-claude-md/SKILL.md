---
name: slim-claude-md
description: Slim a project's CLAUDE.md into a short always-loaded core plus path-scoped rules in .claude/rules/, deleting what the code already says. Triggers on "slim CLAUDE.md", "split CLAUDE.md", "CLAUDE.md eindampfen", "CLAUDE.md aufsplitten", "CLAUDE.md aufräumen", "CLAUDE.md zu groß", "/slim-claude-md".
user-invocable: true
argument-hint: "[project directory, default: the current one]"
---

# Slim CLAUDE.md

**Input:** `$ARGUMENTS` (project directory; default: the current one).

## 1. Inventory

1. List every instruction file: `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`,
   `AGENTS.md`, `.claude/rules/**/*.md`, nested `CLAUDE.md` in subdirectories. Skip
   `node_modules/` and `.claude/worktrees/`.
2. For each file: lines, characters, tokens (characters / 4).
3. Outline the main file: one row per `##` and `###` block with its line span and line count.
4. Confirm the working tree is clean and create the branch `chore/slim-claude-md`.

Done when the table of files and the outline of blocks are in front of you.

## 2. Classify every block

Each `##`/`###` block goes into exactly one bucket. Split a block when its parts belong to
different buckets. The tests, in order; the first that fits wins:

| Bucket | Test | Goes to |
| --- | --- | --- |
| **DELETE** | Claude can read it off the repo (directory listings, package and app lists, tech stack, file-by-file descriptions, "what this app does"), it is a standard language or framework convention, a self-evident practice, history or narrative ("before X existed", "it was untracked before"), a duplicate, or it names files, scripts or commands that no longer exist (check with `git ls-files` and `package.json`). | nowhere; listed in the mapping with the reason |
| **POINTER** | The same content already lives in `docs/`, a README or an ADR (open the target and confirm). | one line in the core: what it is and when to read it |
| **SKILL** | A multi-step procedure or a long reference reached at a moment ("how to add a page with an id", a 10+ item checklist, reference implementations). | `.claude/skills/<name>/SKILL.md` with a description that names the trigger |
| **RULE** | A constraint that applies only while editing one part of the tree; you can name the glob. | `.claude/rules/<topic>.md` with `paths:` frontmatter |
| **CORE** | Needed in every session and not derivable: commands Claude cannot guess (gate, dev setup quirks, required env vars), repo etiquette (branch names, PR base, ticket workflow), project-wide gotchas, one line per binding architectural decision. | `CLAUDE.md` |

Rules of thumb:

- "Would removing this line cause a mistake in a session that touches no particular area?"
  No → not CORE.
- A rule whose glob would be `**/*` is CORE, not RULE. A RULE whose glob matches the whole
  app is a smell: narrow it to the files the rule is about (`apps/web/**/page.tsx`,
  `**/*Table*.tsx`), not the app.
- Ticket references stay as short tags `(PAUL-2636)`; the story behind them goes.
- The project file serves the whole team. A project rule that also exists in one person's
  `~/.claude/CLAUDE.md` stays.
- Nested `CLAUDE.md` files in subdirectories already load on demand; keep one only when its
  content is RULE-like for that directory, otherwise fold it into the mapping like any block.

Done when every block of every file has a bucket and a target, and the mapping table
(format below) is complete.

## 3. Condense what stays

Rewrite every kept block, whichever bucket:

- One rule = one imperative line, concrete enough to verify ("`npm run gate` before every
  push", not "test your changes").
- Rationale: at most half a sentence, and only where the rule would otherwise be argued away.
- Tables stay when they carry facts (CI step vs. gate coverage). Prose that explains a table goes.
- Code examples only when the shape cannot be said in a line; then the shortest one.
- Keep exact commands, paths, names, thresholds. Never paraphrase a command.
- No emphasis markers except one `IMPORTANT` for the single rule that is most often skipped.
- Same language as the original file.

Done when every target file exists as a draft and the core draft is under 150 lines.

## 4. Checkpoint with the user

Show, before writing into the repo:

1. The mapping table.
2. The DELETE list, one line per block with the reason.
3. Sizes: main file before/after in lines and tokens; per rules file its glob and size; what a
   session loads when it touches nothing, and when it touches each rules glob.

Wait for the go or for corrections. Never write on a silent assumption.

## 5. Write

1. `CLAUDE.md`: the core. Hard limit 200 lines, target under 150.
2. `.claude/rules/<topic>.md`, one topic per file, frontmatter:
   ```markdown
   ---
   paths:
     - "apps/web/**/*.{ts,tsx}"
   ---
   ```
   Every glob must match at least one tracked file (`git ls-files | grep`), or the rule never
   loads.
3. `.claude/skills/<name>/SKILL.md` for SKILL blocks: `name`, a `description` that names when
   to reach it, the procedure as steps.
4. Replace POINTER blocks by their one line in the core.
5. Delete the DELETE blocks. Remove nested files that were folded in.

## 6. Verify

- Every `##`/`###` heading of the old file appears in the mapping (list any that do not).
- Take 15 distinctive strings from the old file (commands, paths, ticket keys, thresholds) and
  `grep` the new files: each is found in its target, or is on the DELETE list.
- Line counts: core under 200; each rules file under 200.
- Every rules file parses (`---` fences, `paths:` list) and every glob matches a tracked file.
- No two kept rules contradict each other; no kept rule contradicts a rules file.
- Report tokens per session: before; after, touching nothing; after, touching each glob.

Done when all six checks are green and printed.

## 7. Commit and hand over

One PR per project on `chore/slim-claude-md`, the mapping table and the sizes in the
description. Merge follows the project's phase policy. Tell the user to run `/context` in a
fresh session of the project and confirm the core loads and the rules do not.

## Mapping table format

```
| # | Old block (lines) | Bucket | Target | Lines before → after | Note |
| 1 | ## Common Development Commands (5-201) | CORE | CLAUDE.md | 197 → 22 | commands only; the gate/CI table stays, the history goes |
| 2 | ### Monorepo Structure (217-255) | DELETE | - | 39 → 0 | `ls apps packages` says the same |
| 3 | ## Web App Conventions (535-1320) | RULE | .claude/rules/web-ui.md `apps/web/**/*.{ts,tsx}` | 786 → 140 | five sub-blocks become skills, see 4-8 |
```
