---
name: port-from-repo
description: >
  Port a component, style, layout or feature from a reference repo into the
  current project, in one of two modes: EXACT (look and behaviour verbatim) or
  STRUCTURE-ONLY (logic and structure, restyled with this project's design
  system). Trigger on "take this from repo X", "port from X", "copy it from X",
  "make it like X", "übernimm das aus X", "wie in X/Jexity", "1:1", "build the
  same as the other project", "take the logic/structure/idea from X", or a
  pasted screenshot of a UI from another repo with "build the same here".
user-invocable: true
argument-hint: "[exact | structure-only]  <what to port + source repo>"
---

# Port From Reference Repo

Read the source, copy the layers asked for, verify the result. Never write a
class, token, prop or structure that was not just read in the source.

## Step 0: Pick the mode

Two layers: behaviour/structure (logic, component API, data flow, state, file
layout) and appearance (classes, tokens, colors, spacing, animations).

- EXACT (default for "1:1", "exactly like X", "übernimm das genau", "make it
  look identical", a screenshot with "same as X"): copy both layers verbatim.
- STRUCTURE-ONLY ("just the functionality / logic / idea / structure", "nur
  die Struktur/Funktion", "adapt it to our design", "same behaviour but our
  look"): copy behaviour and structure verbatim, restyle with this project's
  tokens, primitives and conventions. Do not paste the source's raw classes.

Unclear which: ask one short question.

## Step 1: Read the source in full

- The source component file, completely.
- The primitives it composes (`button-variants.ts`, `command.tsx`,
  `input.tsx`, `popover.tsx`, the data hook, the context provider).
- EXACT mode: the design tokens and CSS it depends on (`globals.css`, theme,
  `@layer base` resets).

EXACT: copy class strings and token values verbatim; no paraphrased utility,
no "similar" token, no rounded gradient. STRUCTURE-ONLY: copy props, state
transitions, effects, routing and data logic verbatim; map each visual class
to the local design system.

## Step 2: Delta-check the target

- Token or primitive already exists here: import it, do not duplicate it.
  (This is also where STRUCTURE-ONLY finds its local equivalents.)
- Global CSS differences that make a verbatim copy look off: a global
  `:focus-visible` outline the source lacks, a different Tailwind border-color
  default (v4 defaults to `currentColor` without a `@layer base` border reset),
  an extra preflight, a different font scale or `--radius`. Diff the two theme
  files when in doubt.

## Step 3: A defect everywhere is a global cause

Same defect in every row, border or input: a token or base rule, not a
component. Measure in the running app
(`getComputedStyle(el).borderBottomColor`,
`getComputedStyle(document.documentElement).getPropertyValue('--border')`)
and compare with the source's value.

## Step 4: Verify before saying done

- Behaviour (both modes): click through the ported flow or run its test;
  confirm it does what the source does.
- Appearance (EXACT): open the page in the user's logged-in Chrome via the
  browser MCP (localhost or the real domain; a `*.vercel.app` preview
  bounces to login). The dev server is usually already running; check before
  starting a second one. Zoom in and compare side by side with the source:
  padding, height, icon and avatar size, border color and weight, focus and
  hover states, radius, row spacing.
- Appearance (STRUCTURE-ONLY): consistent with the target's sibling
  components.

Report what was seen or run, not "it's in the code".

## Definition of done

Source read in full (component, primitives, tokens where relevant); copied
verbatim (EXACT) or re-expressed in the local design system
(STRUCTURE-ONLY); target globals delta-checked; behaviour exercised;
appearance seen in-browser for EXACT ports.
