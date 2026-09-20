---
name: codex-imagegen
description: >-
  Generate raster image files (hero shots, product mockups, illustrations,
  textures, icons, social/OG cards, backgrounds) by delegating to the Codex
  CLI's built-in imagegen skill, which runs OpenAI's gpt-image-2 model. This is
  a manually-invoked skill: use it only when the user explicitly asks for it,
  by name (codex-imagegen / "the codex imagegen skill") or by asking to
  generate images "with Codex" / "through the Codex CLI" / "using gpt-image-2".
  Without that signal, do not auto-trigger it on a generic image request.
---

# Codex Imagegen

Brief Codex's built-in imagegen skill, let it save the file, wire the file
into the project. Shared procedure (preflight, model, background run,
reporting): `${CLAUDE_PLUGIN_ROOT}/skills/codex-review/references/codex-common.md`.
References in this folder: `brief-schema.md` (spec and sizing),
`reference-images.md` (`--image` compositing), `copy-out.md` (where the
file lands, Windows).

## Before the run

1. Preflight per codex-common.md. Add `--skip-git-repo-check` (the cwd need
   not be a repo).
2. Output path: the user's path when given; otherwise propose one under
   `public/` for web projects (e.g. `public/marketing/hero.png`) and confirm
   before generating. `mkdir -p` the destination folder.
3. Write the brief (brief-schema.md) to a file from `mktemp /tmp/codex-XXXXXX`.
   The brief must name the imagegen skill, the full spec, and the exact
   absolute output path with an instruction to print it back.

## Run

Log file from `mktemp /tmp/codex-XXXXXX`, then in the background:

```bash
codex-cli exec --sandbox workspace-write -c approval_policy=on-request -c approvals_reviewer=auto_review --skip-git-repo-check - < /tmp/codex-<brief> > /tmp/codex-<log> 2>&1
```

- The brief goes in on stdin (trailing `-`), never as a positional argument.
- `approval_policy=on-request` with `approvals_reviewer=auto_review` routes
  escalations to Codex's reviewer agent, so the run completes unattended.
  Do not use `--dangerously-bypass-approvals-and-sandbox`; the permission
  layer denies it. `--sandbox danger-full-access` only when a write must
  leave the workspace and the copy-out in copy-out.md will not do.
- Reference images: one `--image <FILE>` per file (reference-images.md).
- Several assets: one run per asset, each with its own brief and output
  path; runs are independent and may run in parallel.
- Wait for the completion notification (high quality on a large canvas takes
  minutes).

## After the run

1. `ls -l <ABS_PATH>`. Missing: follow copy-out.md.
2. Read the image: subject, style, text spelled correctly, negative space as
   asked, no stray watermark or logo.
3. Wire it in when project-bound: `<Image>`/`<img>`, alt text, remove the
   placeholder it replaces.
4. Iterate one change at a time, same brief plus one targeted edit, saved to
   a versioned filename (`hero-v2.png`) unless the user asked to replace.
5. Report the saved path(s), the final brief, the log path, the `model:`
   line, and what was wired up.

## Not here

- Existing SVG or vector icon set: edit the vector.
- Charts, graphs, architecture diagrams: build in code or SVG.
- Layout, spacing or CSS changes without a new bitmap: do the code.
