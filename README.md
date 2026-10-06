# kaneo-work-tracking-skill

A user-level [Claude Code](https://claude.com/claude-code) skill for working with [Kaneo](https://kaneo.app): it plans, estimates, splits, and tracks tickets through the Kaneo MCP server, names branches after ticket identifiers, and mentions the ticket in pull requests.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/elvisgastelum/kaneo-work-tracking-skill/main/install.sh | bash
```

The installer asks for your Kaneo base URL, for example `https://kaneo.elvisgastelum.com/`, and registers `<base-url>/api/mcp` as the `kaneo` MCP server. It reads the answer from your terminal even when piped from `curl`. The prompt uses [`gum`](https://github.com/charmbracelet/gum), `whiptail`, or `dialog` when one is installed, and a plain prompt otherwise. It only asks when Kaneo is not configured yet; pressing Enter accepts the suggested URL.

Restart Claude Code afterwards and run `/mcp` to check the Kaneo connection.

## Update

Re-run the same one-liner any time to update the installed skill and instructions to the latest version. Re-runs are safe and quiet: once Kaneo is configured they keep its endpoint without asking again, files whose content already matches are left untouched, and `~/.claude.json` is not rewritten unless the Kaneo entry changes. To change the endpoint, pass `KANEO_URL=...` or `KANEO_RECONFIGURE=1` to be asked again.

## What it installs

| Piece | Location | Purpose |
| --- | --- | --- |
| `kaneo-work-tracking` skill | `~/.claude/skills/kaneo-work-tracking/SKILL.md` | The full workflow: stories, point labels, splitting, dependencies, ticket identifiers, branch names, and PR ticket mentions. |
| Kaneo instructions | `~/.claude/CLAUDE.md` | A managed block (between `BEGIN/END kaneo-work-tracking-skill` markers) synced from `instructions/kaneo.md`: always-on rules for branch names and PR ticket mentions. Re-runs replace the block in place; the rest of the file is kept. |
| Kaneo MCP server | `~/.claude.json` | Sets `mcpServers.kaneo` to `{"type": "http", "url": "<base-url>/api/mcp"}` at user scope. Other servers and settings are kept, and a timestamped backup is written first. |

## Conventions it teaches

- **Ticket identifier**: project slug plus task number, such as `FEX-2`.
- **Branch**: `<IDENTIFIER>/<short-kebab-description>`, such as `FEX-2/some-feature-getting-done`, created from the up-to-date default branch.
- **Pull request**: the body starts with a linked ticket line, `Kaneo: [FEX-2 — <ticket title>](<base-url>/dashboard/workspace/<workspaceId>/project/<projectId>/task/<taskId>)`, and the PR URL is commented back on the Kaneo task.
- **Stories**: every agent-created story gets `made_by_agent` and one Fibonacci point label; anything `P8` or larger is split first.

## Options

```bash
# Non-interactive: pass the base URL instead of being asked
curl -fsSL .../install.sh | KANEO_URL=https://kaneo.example.com bash

# Ask for the base URL again on a machine that already has Kaneo configured
curl -fsSL .../install.sh | KANEO_RECONFIGURE=1 bash

# Force a prompt style: gum, whiptail, dialog, or plain
curl -fsSL .../install.sh | KANEO_TUI=plain bash

# Skill and instructions only, leave the MCP configuration untouched
curl -fsSL .../install.sh | SKIP_MCP=1 bash

# Install from a fork or tag
curl -fsSL .../install.sh | REPO=you/kaneo-work-tracking-skill REF=v1.0.0 bash

# Custom Claude config directory (MCP config goes to $CLAUDE_DIR/.claude.json)
curl -fsSL .../install.sh | CLAUDE_DIR=/path/to/.claude bash
```

Requires `bash` and `curl`; `jq` is needed for the MCP setup (without it, only the skill and instructions are installed). Without a terminal and without `KANEO_URL`, the MCP step keeps any existing configuration and otherwise is skipped with a warning.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/elvisgastelum/kaneo-work-tracking-skill/main/install.sh | bash -s -- --uninstall
```

Removes the skill, the managed block in `~/.claude/CLAUDE.md`, and the `kaneo` MCP server entry.

## Local development

```bash
git clone https://github.com/elvisgastelum/kaneo-work-tracking-skill
cd kaneo-work-tracking-skill
./install.sh   # copies local files instead of downloading
./tests/install_test.sh   # installs into throwaway dirs and checks idempotency (needs jq)
```
