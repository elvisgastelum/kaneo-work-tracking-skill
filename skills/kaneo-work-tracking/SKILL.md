---
name: kaneo-work-tracking
description: Kaneo stories, tickets, estimates, labels, dependencies, or work splitting, plus branches and pull requests for Kaneo tickets. Use when planning, creating, estimating, or tracking work through the Kaneo MCP, or when creating a branch or PR for work on a Kaneo ticket such as FEX-2.
---

# Kaneo work tracking

Use the Kaneo MCP as the source of truth for work. Discover the target workspace, project, and project columns before creating or changing work; do not assume a Kaneo URL, ID, project, status, or assignee.

## Create a story

1. List workspaces, projects, and the target project's columns. When the request does not identify one clear destination, ask the user to choose.
2. Estimate the work before creating it. A new implementation story must be `P5` or smaller; split larger scope first.
3. List workspace labels. Ensure the required labels exist as workspace labels, then create the task and attach both labels.
4. Give the task a specific title, a description with the intended outcome and completion criteria, a selected project status, and an appropriate priority.
5. Report the created story and its estimate.

Every story created by an agent receives exactly these labels:

- `made_by_agent`, color `#3B82F6`.
- One point label in the `P<number>` format.

Create a missing label only after confirming it is absent from the selected workspace. Reuse the existing label when its name matches exactly.

## Point scale

Use Fibonacci-sized point labels: `P1`, `P2`, `P3`, `P5`, `P8`, `P13`, `P21`, then `P34`, `P55`, and so on. Create only labels needed by the work being tracked, using these colors:

| Label | Meaning | Color |
| --- | --- | --- |
| `P1` | Small change | `#22C55E` |
| `P2` | About two tickets can fit in one day | `#84CC16` |
| `P3` | Preferred size: one day with some free time | `#EAB308` |
| `P5` | One full day of focused work | `#F59E0B` |
| `P8` | Too large for one implementation story; split it | `#F97316` |
| `P13` | Too large for one implementation story; split it | `#EF4444` |
| `P21` | Too large for one implementation story; split it | `#B91C1C` |
| `P34` | Too large for one implementation story; split it | `#991B1B` |
| `P55` and larger | Too large for one implementation story; split it | `#7F1D1D` |

For an existing oversized story, record its honest `P8+` estimate before splitting it when the user asks for an estimate. For new work, split the scope before task creation, so every created implementation story is `P5` or smaller.

## Split oversized work

Split any `P8+` work into independently trackable stories with a clear outcome and an estimate of `P5` or less. Do not create an oversized parent story just to hold the split.

For each resulting story:

- Create it in the selected project, attach `made_by_agent` and its point label, and state its completion criteria.
- State its execution order and prerequisites in the description.
- For a dependency, create a `blocks` relation from the prerequisite task to the task that must wait.
- For work that can proceed simultaneously, create `related` relations and state the parallel group in every participating task description.

Use the dependency graph as the execution order. A task with no unresolved prerequisite may run in parallel with other ready tasks. Report the ordered sequence, parallel groups, and blocking edges after creating the split.

## Update existing work

Fetch the task and its relations before changing it. Preserve labels and project status unless the request calls for a change. When adding an estimate to an existing task, ensure exactly one point label is attached; replace an obsolete point label rather than accumulating multiple estimates.

## Ticket identifiers

A ticket's identifier is its project slug, a hyphen, and its task number: project slug `FEX` with task `number` 2 is `FEX-2`. Read both values from Kaneo (`get_project` or `list_tasks` for the slug, `get_task` or `list_tasks` for the number); never guess them from the task title or its position in a column.

When the user names a ticket by identifier, resolve it by listing the project's tasks and matching `number`, then work from that task's title and description.

## Branches for ticket work

Name a branch for work on a Kaneo ticket `<IDENTIFIER>/<short-description>`:

- `<IDENTIFIER>` is the ticket identifier exactly as Kaneo shows it, uppercase: `FEX-2`.
- `<short-description>` is a lowercase kebab-case summary of the ticket title, at most about five words, without the identifier, numbering prefixes such as `T01 ·`, or punctuation: `FEX-2/some-feature-getting-done`.

Create it from the up-to-date default branch unless the user names another base:

```bash
git fetch origin
git switch -c FEX-2/some-feature-getting-done origin/main
```

Work for one ticket stays on one branch. When work spans several tickets, name the branch after the ticket that owns the main outcome and mention the others in the PR. Never create a bare `FEX-2` branch: Git cannot hold both `FEX-2` and `FEX-2/...` as branch names. Work without a Kaneo ticket follows the repository's own branch convention.

## Pull requests for ticket work

When a PR delivers work attached to a Kaneo ticket, mention the ticket:

- Start the PR body with a ticket line that links the ticket's Kaneo page: `Kaneo: [FEX-2 — <ticket title>](<ticket URL>)`. A bare identifier without the link is not enough.
- Link every other ticket the PR touches the same way, on the same line or the next.

Build each ticket URL from values read from Kaneo, never from guesses:

```text
<base-url>/dashboard/workspace/<workspaceId>/project/<projectId>/task/<taskId>
```

- `<base-url>` is the `kaneo` MCP server URL without its trailing `/api/mcp`, such as `https://kaneo.example.com`.
- `<workspaceId>`, `<projectId>`, and `<taskId>` are the task's IDs from `get_task` or `list_tasks` (`workspaceId` from the project when the task omits it), not the project slug or task number.

A URL the user shared for the ticket works too. When the base URL or any ID cannot be read, stop and ask the user for the ticket URL instead of opening the PR with an unlinked ticket line.
- Keep the PR title in the repository's usual style; when the repository has no title convention, prefix it with the identifier: `FEX-2: Add guest RSVP form`.
- Derive the identifier from the branch name when it follows the convention above, and confirm it against Kaneo.

After the PR exists, add a comment to the Kaneo task with the PR URL, and move the task to the project's review column when one exists and the user has not asked to keep the status. Leave PRs for work without a ticket unchanged.
