# Issue tracker: Local Markdown

Issues and specs for this repo live as markdown files in `docs/issues/`.

## Conventions

- One feature per directory: `docs/issues/<feature-slug>/`
- The spec is `docs/issues/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `docs/issues/<feature-slug>/<NN>-<slug>.md`, numbered from `01`, never a single combined tickets file
- State is recorded as a `Status:` line near the top of each issue file (`open`, `in-progress`, `resolved`), with an `Assignee:` line next to it
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

## When a skill says "publish to the issue tracker"

Create a new file under `docs/issues/<feature-slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## When a skill says "set the ticket In Progress and assign it"

Set `Status: in-progress` and `Assignee: <user>` in the file before the first code change.
