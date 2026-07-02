---
name: codex-imagegen
description: >-
  Generate raster image files (hero shots, product mockups, illustrations,
  textures, icons, social/OG cards, backgrounds) by delegating to the Codex
  CLI's built-in imagegen skill, which runs OpenAI's gpt-image-2 model. This is
  a manually-invoked skill: use it only when the user explicitly asks for it —
  by name (codex-imagegen / "the codex imagegen skill"), or by clearly asking to
  generate images "with Codex" / "through the Codex CLI" / "using gpt-image-2".
  Do not reach for this on a generic image request unless the user has tied it to
  Codex or named the skill; without that signal, do not auto-trigger it.
---

# Codex Imagegen — generating images through the Codex CLI

You (Claude) can't render bitmaps. But the Codex CLI installed on this machine
ships a built-in `imagegen` skill backed by OpenAI's **gpt-image-2** model. This
skill is the bridge: you write a strong prompt, hand it to `codex exec`, Codex
generates the image and saves the file, and you wire it into the project.

Think of Codex here as a specialist you're briefing. The quality of what comes
back is almost entirely determined by how well you brief it — so the bulk of
this skill is about writing the brief, not about the shell command.

## Preflight (do this once per task, fast)

1. **Confirm Codex is available:** `codex --version`. If it errors, tell the user
   the Codex CLI isn't installed/on PATH and stop — this skill can't work without it.
2. **Decide the output path.** Default for Next.js / web projects is the
   `public/` folder (e.g. `public/marketing/hero.png`) so the asset is servable
   at `/marketing/hero.png`. **If the user already named a path, use it.
   Otherwise propose the `public/...` path and confirm before generating** —
   regenerating to a different location wastes a model call. Create the
   destination folder first (`mkdir -p`) so Codex has somewhere to write.
3. **Gather the spec** (see "Writing the brief"). Don't fire off a vague prompt;
   a 20-second spec is the difference between a usable asset and a throwaway.

If your session denies the `codex exec` call outright (some permission setups
block any `codex` Bash command), the fix is a one-time allow rule for `codex
exec` in `.claude/settings.json` — not the bypass flag, which gets denied harder.
Tell the user that rather than trying to route around the denial.

## The invocation

Run Codex headless with `exec`, in **Auto-review mode**: Codex runs in the
`workspace-write` sandbox, and whenever it hits something that would normally
need *your* approval (writing outside the workspace, network, side-effecting
tools), a Codex reviewer agent decides instead of blocking on a prompt you can't
answer in a headless run. This is the closest analog to Claude Code's own auto
mode — supervised autonomy, not a free-for-all. It's the recommended default
because it both (a) never deadlocks waiting on an approval, and (b) keeps a
guardrail in place.

```bash
codex exec \
  --sandbox workspace-write \
  -c approval_policy=on-request \
  -c approvals_reviewer=auto_review \
  --skip-git-repo-check \
  "<BRIEF>"
```

- `exec` = headless, one-shot, no TUI.
- `--sandbox workspace-write` lets Codex read/edit/run inside the working dir.
- `-c approval_policy=on-request` — escalations *can* be requested (required for
  auto-review to engage; in `exec` you set this via `-c`, not `--ask-for-approval`,
  which `exec` doesn't accept).
- `-c approvals_reviewer=auto_review` routes those escalations to Codex's
  reviewer agent instead of to a human prompt — so the run completes unattended.
- `--skip-git-repo-check` lets Codex run even when the cwd isn't a git repo.

**Why not `--dangerously-bypass-approvals-and-sandbox` (alias `--yolo`)?** It
removes the sandbox *and* all approvals, and the Claude Code permission layer
flags it as an "unsafe agent" in non-interactive sessions — the call gets denied
and produces nothing. Auto-review gives you the unattended behavior you want
without that. Only reach for `--sandbox danger-full-access` if a write genuinely
must escape the workspace and the copy-out fallback below won't do.

**The `<BRIEF>` must explicitly tell Codex three things**, or it may render an
image inline and never save a file:

1. To **use its imagegen skill**.
2. The **full spec** of the image (the brief below).
3. The **exact absolute output path** to save the final PNG to, and to confirm
   that path back.

### Where the file actually lands (and the Windows gotcha)

Codex's built-in image tool always writes first to
`~/.codex/generated_images/<session-id>/...`, then copies to the destination you
named. On Windows the native sandbox can block that copy step (you'll see
`windows sandbox: ... apply deny-read ACLs`) even though the image generated
fine. The robust pattern, which works on every OS:

- **Tell Codex the destination anyway** — when its own copy succeeds, you're done.
- **Always be ready to copy it out yourself.** Claude's own Bash is *not* under
  Codex's sandbox, so if Codex couldn't move the file, copy it out manually. But
  be precise about *which* file — `~/.codex/generated_images/` also contains
  bundled skill sample images and PNGs from earlier sessions, so a naive
  "newest PNG anywhere under that tree" can grab the wrong image (a real failure
  we hit: it picked up a stock coffee-bag sample instead of the card just made).
  Target the **newest session directory**, and the generated files are named
  with an `ig_` prefix:

  ```bash
  # newest session dir, then its newest ig_* image → your destination
  sess=$(ls -td ~/.codex/generated_images/*/ | head -1)
  src=$(ls -t "$sess"ig_*.png 2>/dev/null | head -1)
  src=${src:-$(ls -t "$sess"*.png | head -1)}   # fall back to any png in that session
  mkdir -p "$(dirname '<ABS_PATH>')" && cp "$src" '<ABS_PATH>'
  ```

  Then **look at the copied file** to confirm it's the image you just described,
  not a leftover. This is a reliable finish step, not a workaround to feel bad
  about — gpt-image-2 did the expensive part; you're just relocating its output.

### Invocation template

```bash
codex exec \
  --sandbox workspace-write \
  -c approval_policy=on-request \
  -c approvals_reviewer=auto_review \
  --skip-git-repo-check \
"Use your imagegen skill to generate an image.

<BRIEF — see schema below>

Save the final PNG to the absolute path: <ABS_PATH>
Create the folder if needed. After saving, print the absolute path you wrote.
Do not ask me anything; proceed end to end."
```

Use a long timeout — gpt-image-2 at `high` quality on a large canvas can take a
few minutes. Run the command **blocking** with a generous timeout (e.g. 300s)
and wait for it to return; don't fire it off in the background and then pause
hoping for a notification — a generation that's still running just looks like
nothing happened, and you'll stall. One blocking call per image.

**Exact pixel sizes:** gpt-image-2 picks the *nearest valid* size to what you
ask, so it often returns something close but not exact (e.g. ~1730×909 when you
wanted 1200×630). For assets with a hard size contract — OG/social cards,
favicons, fixed ad slots — generate at the right *aspect*, then resample to the
exact dimensions afterward with a one-liner (Pillow `Image.open(...).resize(
(1200,630), Image.LANCZOS).save(...)`). For heroes/backgrounds/photos where the
CSS will cover/scale the image anyway, the near-match size is fine as-is.

## Writing the brief (this is where quality comes from)

Codex's own imagegen skill thinks in a labeled spec. Mirror it. Fill only the
lines that matter for the asset — a clean short spec beats a padded one. Keep the
user's intent intact; add concrete detail only where it genuinely sharpens the
result, never invent brands, slogans, extra subjects, or palettes they didn't ask for.

```text
Use case: <one of: photorealistic-natural | product-mockup | ui-mockup |
  infographic-diagram | ads-marketing | logo-brand | illustration-story |
  stylized-concept | background-texture | social-og-card>
Asset type: <where it's used, e.g. "landing page hero", "1200x630 OG card">
Primary request: <the user's actual ask, in plain language>
Subject: <the main thing in frame>
Scene/backdrop: <environment / setting>
Style/medium: <photo | 3D render | flat illustration | etc.>
Composition/framing: <wide | close | top-down; where the subject sits; leave
  negative space here if page copy overlays it>
Lighting/mood: <e.g. soft studio light, golden hour, moody>
Color palette: <match the product's palette when it's a project asset>
Text (verbatim): "<exact text, letter for letter>" — or "none"
Constraints: <must-keep items>
Avoid: <no logos, no watermark, no text unless requested, no extra UI chrome…>
```

### Sizing

gpt-image-2 accepts `auto` or `WIDTHxHEIGHT` (edges multiples of 16, max edge
≤3840, ratio ≤3:1). You can't pass size as a CLI flag to the built-in tool —
**state the dimensions and aspect inside the brief** and let Codex pick a valid
size. Useful targets:

- Hero / wide banner → `1536x1024` (or 4K `3840x2160` for a showcase hero)
- Square / avatar / icon → `1024x1024`
- Portrait / mobile → `1024x1536`
- Social / OpenGraph card → describe as **1200×630** (Codex maps to nearest valid)

Mention `low` quality in the brief for quick drafts/iterations; `high` for final
assets, dense text, or anything with legible typography.

### Why detail matters

gpt-image-2 is literal and capable. "a coffee mug" gives you a random mug; "a
matte charcoal ceramic mug, three-quarter view, on a pale oak surface, soft
window light from the left, generous empty space on the right for headline copy,
no text, no logo" gives you something you can ship. For project assets, look at
the actual page/palette first (read the relevant component or DESIGN.md) so the
image belongs there instead of fighting the design.

## Reference images: compositing and edits (`--image`)

`codex exec` accepts one or more reference images via `--image <FILE>` (repeat
the flag per image). gpt-image-2 uses them as visual input, so you can **edit or
composite real assets** instead of describing everything from scratch. This is
the reliable way to put a real UI on a device screen, restyle a photo, or blend
elements — far better than hoping the model draws your UI correctly, and far
simpler than CSS-perspective overlays in the page.

The killer use case: **put a real screenshot on a device screen.** Screenshot
your actual app (e.g. render a component to a temp route and capture it), then:

```bash
codex exec --sandbox workspace-write \
  -c approval_policy=on-request -c approvals_reviewer=auto_review \
  --skip-git-repo-check \
  --image "public/marketing/device-photo.png" \
  --image "/tmp/app-ui.png" \
  - < /tmp/brief.txt
```

**Two arg-parsing gotchas that will silently break the run:**

- `--image` (alias `-i`) is **variadic** — `--image a b "PROMPT"` swallows the
  prompt as a third image, and Codex then reports *"No prompt provided via
  stdin."* Use a **separate `--image` flag per file**, and don't leave the
  prompt as a trailing positional after them.
- The robust pattern is to pass the **prompt on stdin**: end the args with a
  bare `-` and pipe a heredoc/file into it (`- < /tmp/brief.txt`). That keeps the
  prompt cleanly separated from the image flags regardless of ordering.

Brief tips for compositing (name the images so the model can refer to them):

- Label each input in the brief ("IMAGE 1 is the device photo, IMAGE 2 is the UI
  screenshot") and state exactly what to do with each.
- For "UI on a screen": say *map IMAGE 2 onto the screen with correct
  perspective, fill edge-to-edge inside the bezel, keep the UI crisp and legible,
  do not redraw or garble its text*, and *add a subtle screen-glow spill onto the
  scene*. gpt-image-2 reproduces provided UI far more faithfully than text it
  invents, but it can still soften small labels — check legibility after.
- Keeping most of a photo unchanged: say *keep IMAGE 1's composition, lighting,
  and background essentially unchanged* so it edits rather than reinvents.

A baked-in composite like this is usually better than compositing in the page
(CSS `transform`/`perspective` over a photo): it's one flat asset, it can't drift
across breakpoints, and the glow/reflection reads as real light.

## After Codex returns

1. **Verify the file exists** at the path you specified (`ls`/stat it). If it's
   missing, the most likely cause on Windows is the sandbox blocking Codex's
   copy — the image is still in `~/.codex/generated_images/`. Copy the newest PNG
   out yourself (see the copy-out snippet above) rather than regenerating. Only
   re-run the whole thing if no image was generated at all.
2. **Look at the image.** Read it back and check: right subject, right style,
   text spelled correctly (gpt-image-2 can still botch text), composition leaves
   the negative space you asked for, no stray watermark/logo.
3. **Wire it in** if it's project-bound — add the `<Image>`/`<img>` reference,
   update alt text, remove the placeholder it replaces.
4. **Iterate with one change at a time.** If something's off, re-run the same
   brief with a single targeted edit ("same image but warmer lighting and more
   headroom") rather than rewriting the whole prompt. Save iterations to
   versioned filenames (`hero-v2.png`) instead of overwriting, unless the user
   asked to replace.
5. **Report** the saved path(s), the final brief, and what you wired up.

## Multiple assets

For several distinct images (e.g. three feature thumbnails), issue **one
`codex exec` call per asset** with its own brief and its own output path. Don't
ask one call to produce many unrelated images — separate calls give each asset
a focused prompt and a clean save. These calls are independent, so run them in
parallel if your harness allows.

## Transparency

gpt-image-2 doesn't do native transparent backgrounds. If the user needs a
cutout (logo, sprite with alpha), the cleanest path is to ask Codex to generate
the subject on a flat `#00ff00` chroma-key background, then remove the key —
Codex's imagegen skill bundles a `remove_chroma_key.py` helper for exactly this.
Put "on a perfectly flat solid #00ff00 background, crisp edges, generous padding,
no shadows or reflections, #00ff00 used nowhere on the subject" in the brief and
tell Codex to run its chroma-key removal helper and save an alpha PNG. For hard
cases (hair, glass, smoke) tell the user true transparency needs Codex's
`gpt-image-1.5` CLI fallback and let them decide.

## What not to route here

- Editing/extending an existing repo SVG or vector icon set → edit the vector directly.
- Charts, graphs, architecture diagrams → usually better built in code/SVG.
- Pure layout, spacing, or CSS changes with no new bitmap → just do the code.
