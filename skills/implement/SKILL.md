---
name: implement
description: "Implement a piece of work based on a spec or a ticket, test-first at the agreed seams, closing with a review. Triggers on \"/implement\", \"implement this spec\", \"implement ticket X\", \"setz das Ticket um\", \"implementiere die Spec\"."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Use /evelan:tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, use /evelan:code-review to review the work.

Commit your work to the current branch.
