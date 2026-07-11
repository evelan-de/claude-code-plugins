---
name: port-from-repo
description: >
  Controlled workflow for porting a component, style, layout, or feature from a
  reference repo into the current project. Use this WHENEVER the task is to
  reproduce something that already exists in another codebase - trigger on
  "take this from repo X", "port from X", "copy it from X", "make it like X",
  "übernimm das aus X", "wie in X/Jexity", "1:1", "build the same as the other
  project", "take the logic/structure/idea from X", or when a screenshot of a UI
  that lives in another repo is pasted with "build the same here". Two modes it
  makes explicit and separable by instruction: EXACT (reproduce look AND
  behaviour verbatim) vs STRUCTURE-ONLY (take the logic/structure/ideas but
  restyle with THIS project's own design system). The point is to never
  approximate the layer you were asked to copy: read the source first and, for
  visual ports, verify in-browser. Prefer this skill over improvising even when
  the port looks trivial - "it's just a button" is exactly when things get
  approximated and go wrong.
user-invocable: true
argument-hint: "[exact | structure-only]  <what to port + source repo>"
---

# Port From Reference Repo

Reproduce something from a source repo the way it was asked for. There is a
working source - use it. The failure this skill exists to kill is approximating
from memory (typing a class, token, prop, or structure that "looks about right")
instead of reading and copying the real thing. That wastes time and tokens and
produces work that is visibly or behaviourally off.

## Step 0: Pick the mode - what am I actually copying?

Porting has two independent layers: **behaviour/structure** (logic, component
API, data flow, state machine, file layout) and **appearance** (classes, tokens,
colors, spacing, animations). Decide which layers to copy from the instruction
before writing anything. When unsure which the user wants, ask one short
question - do not assume.

- **EXACT** (default when the user says "1:1", "exactly like X", "übernimm das
  genau", "make it look identical", or pastes a screenshot and says "same as
  X"): copy **both** layers verbatim - behaviour AND the exact styling/tokens.
- **STRUCTURE-ONLY** (when the user says "just the functionality / logic / idea
  / structure", "nur die Struktur/Funktion", "adapt it to our design", "same
  behaviour but our look"): copy the behaviour and structure faithfully, but
  **restyle using THIS project's own design system** - its tokens, its
  component primitives, its conventions. Do NOT paste the source's raw classes;
  translate them to the local equivalents.

The exactness discipline below applies to **whichever layers you are copying**.
Structure-only does not mean sloppy - the behaviour must still be reproduced
faithfully; it just means the visual layer is deliberately re-expressed in the
target's design language.

If you ever catch yourself writing a class, token, prop, or structure that you
did **not** just read in the source (in whichever layer you are copying), stop.
That is the guessing this skill forbids. Go read it.

## Step 1: Read the source first, in full

Before writing a line in the target:

- Read the **source component file** completely.
- Read the **base primitives it composes** - the underlying `button-variants.ts`,
  `command.tsx`, `input.tsx`, `popover.tsx`, the data hook, the context provider,
  etc. A component that looks simple usually gets its real appearance and
  behaviour from the primitive underneath; reading only the top-level file misses
  where it actually lives.
- For a visual layer (EXACT mode), also read the **design tokens / CSS it
  depends on** - the `globals.css` / theme that defines colors, radii, borders,
  gradients, and any `@layer base` resets the source relies on.

In EXACT mode, copy class strings and token values **verbatim** - do not
paraphrase a Tailwind utility, swap one token for a "similar" one, or round a
gradient. In STRUCTURE-ONLY mode, copy the **behaviour and structure** verbatim
(the props, the state transitions, the effects, the routing/data logic) and map
each visual class to the local design system.

## Step 2: Delta-check the target repo

A faithful copy can still land wrong because the target's environment differs.
Before assuming it is faithful:

- **Does the token / primitive already exist here?** Reuse it - do not duplicate
  a `.btn-gold`, a `--border`, or a `command.tsx` that is already in the target.
  Import the existing one so there is a single source of truth. (This is also how
  STRUCTURE-ONLY finds the right local equivalents to restyle with.)
- **Where does the target's GLOBAL css diverge from the source?** For EXACT
  ports this is the usual reason a verbatim copy still looks off. Common culprits:
  - a global `:focus-visible { outline: ... }` the source does not have (drops a
    hard rectangle over a self-styled input pill),
  - a different Tailwind border-color default (v4 defaults borders to
    `currentColor` - black in light, white in dark - unless a
    `@layer base { * { border-color: ... } }` reset is present),
  - an extra preflight/reset, a different font scale, a different `--radius`.
  Diff the two theme files if in doubt.

## Step 3: "Looks wrong everywhere" = a global / token cause

If the same defect shows up across many components (every table row, every
border, every input), the cause is global - a token or a base rule - not a
per-component bug. Do not hunt inside one component. Measure the resolved value
in the running app:

- `getComputedStyle(el).borderBottomColor`, or
- `getComputedStyle(document.documentElement).getPropertyValue('--border')`.

Compare to the source's value; where they differ you have found the global. One
`getComputedStyle` call ends debates that pages of static reasoning cannot.

## Step 4: Verify before saying done

- **Behaviour** (both modes): exercise the ported flow - click through it, run
  the relevant test - and confirm it does what the source does.
- **Appearance** (EXACT mode): design work is done when it has been **seen** and
  matches the source, not when it compiles or the commit lands. The dev server
  is usually **already running** - check for it (or ask) rather than spinning up
  a duplicate on the same port. Open the page in the user's logged-in Chrome via
  the browser MCP (the user is typically logged in on `localhost` / the real
  domain, not a `*.vercel.app` preview - cookies do not cross origins, so a
  preview bounces to login while localhost works). Zoom in and compare side by
  side against the source component or reference screenshot: exact
  padding/height, icon/avatar size, border color and weight, focus/hover states,
  radius, row spacing.
- **Appearance** (STRUCTURE-ONLY mode): verify it is consistent with the
  target's own sibling components, not with the source.

Report what you actually saw or ran, not "it's in the code".

## Definition of done

For the layers you were asked to copy: source read in full (component +
primitives + tokens where relevant), copied verbatim (EXACT) or faithfully
re-expressed in the local design system (STRUCTURE-ONLY), target globals
delta-checked, and the result verified - behaviour exercised, and appearance
seen in-browser for EXACT ports. If any is missing, it is not done yet.
