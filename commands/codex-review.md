---
description: "Cross-model code review via the Codex CLI"
argument-hint: "[--uncommitted | --base <branch> | --commit <sha>] [focus instructions]"
---

Invoke the `codex-review` skill from the evelan plugin and follow it exactly.

Arguments to forward verbatim to the skill: $ARGUMENTS

An explicit scope flag in the arguments always wins over the skill's
auto-detection. Any remaining text is the focus prompt for the review.
