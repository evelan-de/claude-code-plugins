# Issue tracker: Jira (Atlassian MCP)

Issues and specs for this repo live in Jira, project key **`<PROJECT>`** on
`https://<site>.atlassian.net`. Use the Atlassian MCP tools for every operation; there is no
CLI in the loop. Resolve `cloudId` once per session with `getAccessibleAtlassianResources`.

## Conventions

- **Create an issue**: `createJiraIssue` with `projectKey`, `issueTypeName` (`Task` for tracer-bullet
  tickets, `Story` for user-facing scope, `Bug` for triage bugs, `Epic` for a wayfinder map),
  `summary`, `description`. Assignee via `lookupJiraAccountId` by email.
- **Read an issue**: `getJiraIssue` with the key; comments come with the issue.
- **List / search**: `searchJiraIssuesUsingJql`, always scoped: `project = <PROJECT> AND ...`.
- **Comment**: `addCommentToJiraIssue`.
- **Labels**: `editJiraIssue` on the `labels` field (add or remove; send the full resulting list).
- **Status**: `getTransitionsForJiraIssue` then `transitionJiraIssue`. Never assume transition ids.
- **Link**: `createIssueLink` with the link type from `getIssueLinkTypes` ("Blocks" for
  dependencies, "Relates" otherwise).

## Description format (binding)

Descriptions and comments are **Markdown**. Headings `## Heading`, numbered lists `1.` `2.`,
bullets `-`, `code`, **bold**. Never `h2.` and never a bare `#` as a list marker (both destroy
the layout). After every create or edit that carries structure, read the description back
and check that no line starts with `h1.`/`h2.`/`h3.` or a bare `#`.

## Status and ownership rules

- **Before the first change for a ticket**: transition it to the project's In-Progress status
  and set the assignee to the person the agent works for (look up the account id; never leave
  it unassigned). A ticket without owner and status looks like free work to the team.
- **After the merge into the integration branch**: transition to the project's merge status
  (e.g. `MERGED TO PREVIEW`) and stop there. Manual test, acceptance and production install
  follow; only the human moves it to Done.
- **Verification results** (commands, outcomes, screenshots) go into a comment, never into a
  status change.
- **Ticket key in branch names and commit subjects** (`<PROJECT>-123`), so Jira links the work.

## When a skill says "publish to the issue tracker"

Create a Jira issue in `<PROJECT>` with the Markdown description; return its key and URL.

## When a skill says "fetch the relevant ticket"

`getJiraIssue` with the key; read description, acceptance criteria, comments and labels.

## Triage labels

Jira labels carry the five triage roles; the strings live in `docs/agents/triage-labels.md`.
Triage queue: `project = <PROJECT> AND labels = needs-triage AND statusCategory != Done ORDER BY created ASC`.

## Wayfinding operations

Used by `/evelan:wayfinder`. The **map** is an Epic; its **child** tickets are issues in that
Epic.

- **Map**: `createJiraIssue` with `issueTypeName: "Epic"`, label `wayfinder-map`, the
  Notes / Decisions-so-far / Fog body as Markdown.
- **Child ticket**: an issue with the Epic as parent (`parent` field on create, or
  `editJiraIssue`). Label `wayfinder-<type>` (`research`, `prototype`, `questioning`, `task`).
  Once claimed, assign it to the driving dev.
- **Blocking**: native "Blocks" links via `createIssueLink` (blocker → child). A ticket is
  unblocked when every blocker is resolved (`statusCategory = Done`).
- **Frontier query**: `parent = <MAP> AND statusCategory != Done AND assignee IS EMPTY ORDER BY rank ASC`,
  then drop every result that still has an unresolved inward "is blocked by" link (read the
  `issuelinks` on each candidate); first remaining wins.
- **Claim**: set the assignee, the session's first write.
- **Resolve**: comment the answer, transition to Done, append a context pointer (commit or
  document link) to the map's Decisions-so-far.
