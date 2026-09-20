---
name: implement
description: "Implement a piece of work based on a spec or a ticket, test-first at the agreed seams, closing with a review. Triggers on \"/implement\", \"implement this spec\", \"implement ticket X\", \"setz das Ticket um\", \"implementiere die Spec\"."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Before the first edit: set the ticket to In Progress and assign it to the user, following `docs/agents/issue-tracker.md`.

Use /evelan:tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end. Typecheck and the full suite must be green before the review.

Verify the result in the running app. If you could not, say so plainly in the final report; do not describe it as done.

Once done, use /evelan:code-review to review the work.

Commit your work to the current branch.
