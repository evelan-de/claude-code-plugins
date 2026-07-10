---
name: reflect-on-changes
description: >-
  Runs a short self-reflection check after a round of code changes (edits, refactors, new features, bug fixes) is complete, before declaring the work done. Surfaces what Claude is least confident about and what it might be missing about the situation, so problems get caught before the user finds them. Use this whenever you've just finished writing or modifying code, wrapped up a multi-step implementation, or are about to hand control back to the user after making changes, even if the user didn't explicitly ask for a review. Trigger phrases include done, finished, that should do it, ready for review, let me know what you think, or any point where a batch of edits has just been applied.
---

# Reflect on Changes

Code that looks finished often isn't. The bugs that survive to production are rarely the ones you were unsure about while writing them — they're the ones you didn't think to question at all. This skill is a forcing function: before telling the user a round of code changes is done, stop and interrogate your own work honestly.

## When to run this

Trigger it right after you finish a meaningful round of code changes: a feature, a refactor, a bug fix, a multi-file edit, anything beyond a one-line tweak. Run it before your closing summary to the user, not after — the point is to catch issues before they're handed off, not to append an afterthought.

Don't run it for trivial changes (typo fixes, formatting, a single obvious one-line change) — save it for changes that involved real judgment calls or could plausibly break something.

## What to do

After the changes are in place, pause and answer these two questions honestly, in your own words, grounded in the actual diff and the actual task — not generic hedging:

**1. What are you least confident about right now?**

Point to something specific: a function whose edge-case behavior you didn't fully verify, an assumption about how an existing module works, a piece of logic you translated from unclear requirements, a dependency version you guessed at, a test you didn't write, a race condition you didn't rule out. If you're genuinely confident about everything, say so plainly rather than manufacturing doubt — but that should be rare for anything nontrivial.

**2. What's the biggest thing you might be missing about the situation? What don't you realize?**

This one is harder and matters more. Think about it from outside your own turn: what context did you not ask for that could change the right answer? What did the user say that you interpreted one way but could reasonably mean another? Is there a broader system, team convention, prior decision, or constraint you're not aware of? Would someone with more context on this codebase or this user's goals immediately spot something you can't see from here? If you truly can't think of anything, it's fine to say the gap you're most worried about is simply "unknown unknowns" — but try genuinely before defaulting to that.

## How to present it

Keep it short and direct, not padded with caveats. Present it as a distinct, clearly-labeled section after your summary of the changes, roughly like:

```
**Least confident about:** [specific thing]

**What I might be missing:** [specific thing]
```

Avoid vague hedge phrases like "there could be edge cases" or "further testing may be needed" — those aren't answers, they're evasions. If the honest answer is uncomfortable (e.g. "I'm not sure this matches how the rest of the team structures error handling, since I haven't seen the rest of the codebase"), say that. The value of this skill comes entirely from specificity and honesty, not from covering yourself.

If, on reflection, you realize one of these points is serious enough to change the approach (not just worth flagging), say so and propose a fix or ask the user before moving on — don't bury a real concern inside a routine-sounding checklist.
