## Kaneo work tracking

Kaneo is the work tracker on this machine, reached through the `kaneo` MCP server. Use the `kaneo-work-tracking` skill before planning, creating, estimating, splitting, or updating Kaneo tickets, and before creating a branch or PR for ticket work.

- A ticket identifier is the project slug plus the task number, such as `FEX-2`. Read both from Kaneo; never guess them.
- Name a branch for ticket work `<IDENTIFIER>/<short-kebab-description>`, such as `FEX-2/some-feature-getting-done`, created from the up-to-date default branch unless another base is named.
- A PR for ticket work starts its body with `Kaneo: [<IDENTIFIER> — <ticket title>](<ticket URL>)`, linking the ticket's Kaneo page, and links every other ticket it touches the same way. Build each URL from IDs read from Kaneo, as the `kaneo-work-tracking` skill describes; never guess them. After opening it, comment the PR URL on the Kaneo task.
