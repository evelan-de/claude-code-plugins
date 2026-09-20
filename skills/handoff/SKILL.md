---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up. Triggers on "/handoff", "write a handoff", "hand this over", "Übergabe schreiben", "Handoff für die nächste Session".
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the path the user names; by default, save to the session scratchpad directory, not the current workspace.

Include a "suggested skills" section in the document, naming which skills the next agent should call the Skill tool for.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
