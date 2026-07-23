---
description: "Cross-model code review via the Codex CLI"
argument-hint: "[--uncommitted | --base <branch> | --commit <sha>] [--model <name>] [focus instructions]"
---

Invoke the `codex-review` skill from the evelan plugin and follow it exactly.

Arguments to forward verbatim to the skill: $ARGUMENTS

An explicit scope flag in the arguments always wins over the skill's
auto-detection. Any remaining text is the focus prompt for the review.

`--model <name>` (or a plain "mit Sol" / "nutze Luna" in the text) selects the
review model: resolve it with `codex-model resolve <name>` and pass it as
`-c model="<slug>"`, per the skill's model-selection section. Without it,
Codex's default model reviews.
