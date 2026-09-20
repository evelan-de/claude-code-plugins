---
name: setup-workflow-skills
description: "Configure this repo for the engineering skills: set up its issue tracker and domain doc layout. Run once before first use of the other engineering skills."
disable-model-invocation: true
---

# Setup the Evelan workflow skills

Scaffold the per-repo configuration that the engineering skills assume:

- **Issue tracker**: where issues live (Jira via the Atlassian MCP, GitHub Issues, or local markdown)
- **Domain docs**: where `CONTEXT.md` and ADRs live, and the consumer rules for reading them

Explore, present what you found, confirm with the user, then write.

## Process

### 1. Explore

Read whatever exists; don't assume:

- `git remote -v` and `.git/config`: which host, which repo?
- Jira signals: `atlassian.net` or "Jira" in `CLAUDE.md`/`README.md`, ticket keys like `ABC-123` in recent commit subjects or branch names (`git log --oneline -50`, `git branch -a`). Note the key prefix and the site host when found. A GitHub remote alone is not a signal either way.
- `AGENTS.md` and `CLAUDE.md` at the repo root: does either exist? Is there already an `## Agent skills` section?
- `CONTEXT.md` and `CONTEXT-MAP.md` at the repo root
- `docs/adr/` and any `src/*/docs/adr/` directories
- `docs/agents/`: does this skill's prior output already exist?
- `docs/issues/`: a sign that the local-markdown tracker is already in use
- Monorepo signals: `pnpm-workspace.yaml`, a `workspaces` field in `package.json`, or a populated `packages/*` with its own `src/`. Absent in almost every repo; absence means single-context.

### 2. Present findings and ask

Summarise what's present and what's missing. Take the sections in order: one section, one answer, then the next. Lead each section with the recommended answer so the user can accept it in a word. Skip a section when exploration already settled it.

**Section A: Issue tracker.** Skills like `evelan:to-tasks`, `evelan:to-spec`, `evelan:implement` and `evelan:code-review` read from and write to it.

If exploration found Jira signals, propose **Jira** with the detected project key and site, name GitHub Issues as the alternative in the same breath, and ask for confirmation plus the In-Progress and merge status names. Without Jira signals and with a GitHub remote, propose **GitHub Issues**. Otherwise offer:

- **Jira**: issues live in a Jira project, operated through the Atlassian MCP tools (no CLI)
- **GitHub**: issues live in the repo's GitHub Issues (uses the `gh` CLI)
- **Local markdown**: issues live as files under `docs/issues/<feature>/` in this repo (solo projects or repos without a remote)
- **Other** (Linear, Asana, ...): ask the user to describe the workflow in one paragraph; record it as freeform prose

Record the choice in `docs/agents/issue-tracker.md`.

**Section B: Domain docs.** Default to **single-context** (one `CONTEXT.md` + `docs/adr/` at the repo root); write it without asking. Offer **multi-context** (a root `CONTEXT-MAP.md` pointing to per-context `CONTEXT.md` files) only when exploration found monorepo signals.

### 3. Confirm and edit

Show the user a draft of:

- The `## Agent skills` block for whichever of `CLAUDE.md` / `AGENTS.md` is being edited (selection rules in step 4)
- The contents of `docs/agents/issue-tracker.md` and `docs/agents/domain.md`

Let them edit before writing.

### 4. Write

**Pick the file to edit:** `CLAUDE.md` if it exists, else `AGENTS.md` if it exists. If neither exists, ask the user which one to create. Never create one when the other already exists.

If an `## Agent skills` block already exists, update it in place rather than appending a duplicate. Don't overwrite user edits to the surrounding sections.

The block:

```markdown
## Agent skills

### Issue tracker

[one-line summary of where issues are tracked]. See `docs/agents/issue-tracker.md`.

### Domain docs

[one-line summary of layout: "single-context" or "multi-context"]. See `docs/agents/domain.md`.
```

Then write the docs files from the seed templates in this skill folder:

- [issue-tracker-jira.md](./issue-tracker-jira.md): Jira via the Atlassian MCP; replace `<PROJECT>` and `<site>`, fill in the In-Progress and merge status names
- [issue-tracker-github.md](./issue-tracker-github.md): GitHub Issues
- [issue-tracker-local.md](./issue-tracker-local.md): local markdown
- [domain.md](./domain.md): domain doc consumer rules + layout

For "other" trackers, write `docs/agents/issue-tracker.md` from the user's description.

### 5. Done

Tell the user the setup is complete and which engineering skills now read from these files. They can edit `docs/agents/*.md` directly later; re-run this skill only to switch trackers or restart from scratch.
