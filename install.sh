#!/usr/bin/env bash
# Installs the `kaneo-work-tracking` skill for Claude Code at user (system) level,
# syncs the always-on Kaneo instructions, and registers the Kaneo MCP server.
# Idempotent: re-run any time to resync with the repo; unchanged files are left alone.
#
#   curl -fsSL https://raw.githubusercontent.com/elvisgastelum/kaneo-work-tracking-skill/main/install.sh | bash
#
# Options (env vars):
#   CLAUDE_DIR=~/.claude   target Claude config directory
#   CLAUDE_JSON=...        Claude Code user config holding MCP servers
#                          (default ~/.claude.json, or $CLAUDE_DIR/.claude.json for a custom CLAUDE_DIR)
#   KANEO_URL=https://...  Kaneo base URL; skips the prompt and replaces the configured one
#   KANEO_RECONFIGURE=1    ask for the base URL again even when Kaneo MCP is already configured
#   KANEO_TUI=auto         prompt style: auto (gum, whiptail, dialog, then plain), gum, whiptail, dialog, plain
#   REPO=owner/name        GitHub repo to download from
#   REF=main               branch or tag to download from
#   SKIP_MCP=1             do not register the Kaneo MCP server
#
# Re-running updates the skill and instructions and keeps the configured Kaneo MCP endpoint;
# it only asks for the base URL when none is configured yet.
#
# Uninstall:
#   curl -fsSL .../install.sh | bash -s -- --uninstall
set -euo pipefail

REPO="${REPO:-elvisgastelum/kaneo-work-tracking-skill}"
REF="${REF:-main}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
RAW="https://raw.githubusercontent.com/$REPO/$REF"
if [ -z "${CLAUDE_JSON:-}" ]; then
  # Claude Code keeps user MCP servers in ~/.claude.json, or inside CLAUDE_CONFIG_DIR when one is set.
  if [ "$CLAUDE_DIR" = "$HOME/.claude" ]; then CLAUDE_JSON="$HOME/.claude.json"; else CLAUDE_JSON="$CLAUDE_DIR/.claude.json"; fi
fi
KANEO_TUI="${KANEO_TUI:-auto}"
KANEO_TTY="${KANEO_TTY:-/dev/tty}"
DEFAULT_KANEO_URL="https://kaneo.elvisgastelum.com"

SKILL_DIR="$CLAUDE_DIR/skills/kaneo-work-tracking"
MEMORY="$CLAUDE_DIR/CLAUDE.md"
BLOCK_BEGIN="<!-- BEGIN kaneo-work-tracking-skill: managed by install.sh, edits inside this block are overwritten -->"
BLOCK_END="<!-- END kaneo-work-tracking-skill -->"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kaneo-work-tracking-skill.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# Use local files when run from a clone, otherwise download them.
SRC_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/skills/kaneo-work-tracking/SKILL.md" ]; then
  SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

fetch() { # fetch <repo-relative-path> <dest>
  mkdir -p "$(dirname "$2")"
  if [ -n "$SRC_DIR" ]; then
    cp "$SRC_DIR/$1" "$2"
  else
    curl -fsSL "$RAW/$1" -o "$2" || die "failed to download $RAW/$1"
  fi
}

replace_if_changed() { # replace_if_changed <new> <dest>: back up and rewrite dest only when content differs
  if [ -f "$2" ] && cmp -s "$1" "$2"; then
    return 1
  fi
  [ -f "$2" ] && cp "$2" "$2.bak.$(date +%Y%m%d%H%M%S)"
  # Write through instead of mv so a symlinked dest (e.g. from a dotfiles repo) stays a symlink.
  cat "$1" > "$2" || die "failed to write $2"
}

check_block_markers() { # exits unless MEMORY has no block or exactly one well-formed block
  [ -f "$MEMORY" ] || return 0
  local b e
  b="$(grep -Fxc "$BLOCK_BEGIN" "$MEMORY" || true)"
  e="$(grep -Fxc "$BLOCK_END" "$MEMORY" || true)"
  [ "$b" = 0 ] && [ "$e" = 0 ] && return 0
  if [ "$b" = 1 ] && [ "$e" = 1 ] \
    && [ "$(grep -Fxn "$BLOCK_BEGIN" "$MEMORY" | cut -d: -f1)" -lt "$(grep -Fxn "$BLOCK_END" "$MEMORY" | cut -d: -f1)" ]; then
    return 0
  fi
  die "$MEMORY has a damaged kaneo-work-tracking-skill block; fix the BEGIN/END markers and re-run."
}

sync_instructions() { # writes instructions/kaneo.md into a managed block of ~/.claude/CLAUDE.md
  local src="$TMP_DIR/kaneo.md" tmp="$TMP_DIR/CLAUDE.md"
  check_block_markers
  fetch instructions/kaneo.md "$src"
  [ -z "$(tail -c 1 "$src")" ] || echo >> "$src"
  if [ -f "$MEMORY" ] && grep -Fxq "$BLOCK_BEGIN" "$MEMORY"; then
    awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" -v src="$src" '
      $0 == b { print; while ((getline l < src) > 0) print l; skip = 1; next }
      $0 == e { skip = 0 }
      !skip   { print }' "$MEMORY" > "$tmp"
  else
    if [ -s "$MEMORY" ]; then
      cat "$MEMORY" > "$tmp"
      [ -z "$(tail -c 1 "$MEMORY")" ] || echo >> "$tmp"
      echo >> "$tmp"
    fi
    { echo "$BLOCK_BEGIN"; cat "$src"; echo "$BLOCK_END"; } >> "$tmp"
  fi
  mkdir -p "$CLAUDE_DIR"
  if replace_if_changed "$tmp" "$MEMORY"; then
    info "Synced Kaneo instructions into $MEMORY"
  else
    info "$MEMORY instructions already up to date"
  fi
}

remove_instructions() {
  [ -f "$MEMORY" ] && grep -Fxq "$BLOCK_BEGIN" "$MEMORY" || return 0
  local tmp="$TMP_DIR/CLAUDE.md"
  awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { line[++n] = $0 }
    END     { while (n > 0 && line[n] == "") n--; for (i = 1; i <= n; i++) print line[i] }' "$MEMORY" > "$tmp"
  replace_if_changed "$tmp" "$MEMORY" || true
  info "Removed Kaneo instructions from $MEMORY"
}

normalize_base_url() { # prints the base URL without whitespace, trailing slashes, or a pasted /api/mcp suffix
  local url
  url="$(printf '%s' "$1" | tr -d '[:space:]')"
  while [ "${url%/}" != "$url" ]; do url="${url%/}"; done
  url="${url%/api/mcp}"
  while [ "${url%/}" != "$url" ]; do url="${url%/}"; done
  printf '%s' "$url"
}

valid_base_url() {
  [[ "$1" =~ ^https?://[^[:space:]/?#]+(/[^[:space:]?#]*)?$ ]]
}

have_tty() { [ -r "$KANEO_TTY" ] && [ -w "$KANEO_TTY" ] && { : < "$KANEO_TTY"; } 2>/dev/null; }

pick_tui() {
  if [ "$KANEO_TUI" != auto ]; then
    command -v "$KANEO_TUI" >/dev/null 2>&1 || [ "$KANEO_TUI" = plain ] || die "KANEO_TUI=$KANEO_TUI is not installed"
    echo "$KANEO_TUI"; return
  fi
  local t
  for t in gum whiptail dialog; do
    command -v "$t" >/dev/null 2>&1 && { echo "$t"; return; }
  done
  echo plain
}

ask_base_url() { # ask_base_url <default> [error]: prints the answer; reads from the terminal even under curl | bash
  local title="Kaneo MCP server" text="Kaneo base URL (for example https://kaneo.example.com/)" answer
  [ -n "${2:-}" ] && text="$2"$'\n\n'"$text"
  case "$(pick_tui)" in
    gum)
      gum style --bold --foreground 212 "$title" "${2:-}" >> "$KANEO_TTY"
      answer="$(gum input --header "Kaneo base URL" --placeholder "https://kaneo.example.com/" --value "$1" < "$KANEO_TTY")" ;;
    whiptail|dialog)
      answer="$("$(pick_tui)" --title "$title" --inputbox "$text" 12 72 "$1" 3>&1 1>>"$KANEO_TTY" 2>&3 < "$KANEO_TTY")" ;;
    plain)
      printf '\n\033[1m%s\033[0m\n%s\n[%s]: ' "$title" "$text" "$1" >> "$KANEO_TTY"
      IFS= read -r answer < "$KANEO_TTY" || answer="" ;;
  esac || die "Kaneo MCP setup cancelled; re-run with SKIP_MCP=1 to skip it."
  [ -n "$answer" ] || answer="$1"
  printf '%s' "$answer"
}

current_kaneo_url() {
  [ -f "$CLAUDE_JSON" ] || return 0
  jq -r '.mcpServers.kaneo.url // empty' "$CLAUDE_JSON" 2>/dev/null || true
}

resolve_base_url() { # prints the base URL to use, or nothing to skip MCP setup
  local current default url error="" tries=0
  current="$(current_kaneo_url)"
  if [ -n "${KANEO_URL:-}" ]; then
    url="$(normalize_base_url "$KANEO_URL")"
    valid_base_url "$url" || die "invalid KANEO_URL: $KANEO_URL (expected https://host[/path])"
    printf '%s' "$url"; return
  fi
  if [ -n "$current" ] && [ "${KANEO_RECONFIGURE:-0}" != "1" ]; then
    normalize_base_url "$current"; return
  fi
  if ! have_tty; then
    if [ -n "$current" ]; then
      warn "No terminal to prompt on; keeping the configured Kaneo MCP endpoint $current"
      normalize_base_url "$current"
    else
      warn "No terminal to prompt on; skipped Kaneo MCP setup. Re-run with KANEO_URL=https://your-kaneo-host"
    fi
    return 0
  fi
  default="$(normalize_base_url "${current:-$DEFAULT_KANEO_URL}")"
  while :; do
    url="$(normalize_base_url "$(ask_base_url "$default" "$error")")"
    valid_base_url "$url" && { printf '%s' "$url"; return; }
    tries=$((tries + 1))
    [ "$tries" -lt 3 ] || die "invalid Kaneo base URL: $url"
    error="Not a valid URL: $url"
  done
}

update_claude_json() { # update_claude_json <jq filter> [jq args...]
  local tmp="$TMP_DIR/claude.json" filter="$1"
  shift
  jq "$filter" "$@" "$CLAUDE_JSON" > "$tmp" || die "failed to update $CLAUDE_JSON"
  replace_if_changed "$tmp" "$CLAUDE_JSON"
}

install_mcp() {
  if [ "${SKIP_MCP:-0}" = "1" ]; then
    info "SKIP_MCP=1: skipping Kaneo MCP setup."
    return
  fi
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found: skipped Kaneo MCP setup."
    warn "Register it with:  claude mcp add --transport http --scope user kaneo https://your-kaneo-host/api/mcp"
    return
  fi
  local base endpoint
  base="$(resolve_base_url)"
  [ -n "$base" ] || return 0
  endpoint="$base/api/mcp"
  # Leave the file alone when nothing changes: Claude Code rewrites it constantly, so a needless
  # jq round-trip would only reformat it and pile up backups.
  if [ "$(current_kaneo_url)" = "$endpoint" ] && [ "$(jq -r '.mcpServers.kaneo.type // empty' "$CLAUDE_JSON")" = http ]; then
    info "Kaneo MCP server already set to $endpoint (KANEO_RECONFIGURE=1 to change it)"
    return
  fi
  mkdir -p "$(dirname "$CLAUDE_JSON")"
  [ -f "$CLAUDE_JSON" ] || echo '{}' > "$CLAUDE_JSON"
  jq empty "$CLAUDE_JSON" 2>/dev/null || die "$CLAUDE_JSON is not valid JSON; fix it and re-run."
  if update_claude_json '.mcpServers = ((.mcpServers // {}) + {kaneo: {type: "http", url: $url}})' --arg url "$endpoint"; then
    info "Registered Kaneo MCP server $endpoint in $CLAUDE_JSON"
  else
    info "Kaneo MCP server already set to $endpoint"
  fi
}

remove_mcp() {
  [ -f "$CLAUDE_JSON" ] && command -v jq >/dev/null 2>&1 || return 0
  jq -e '.mcpServers.kaneo' "$CLAUDE_JSON" >/dev/null 2>&1 || return 0
  update_claude_json 'del(.mcpServers.kaneo)' || true
  info "Removed Kaneo MCP server from $CLAUDE_JSON"
}

uninstall() {
  check_block_markers # fail before removing anything, so a damaged block never leaves a partial uninstall
  info "Removing $SKILL_DIR"
  rm -rf "$SKILL_DIR"
  remove_instructions
  [ "${SKIP_MCP:-0}" = "1" ] || remove_mcp
  info "Uninstalled."
}

install() {
  fetch skills/kaneo-work-tracking/SKILL.md "$TMP_DIR/SKILL.md"
  mkdir -p "$SKILL_DIR"
  # The skill is owned by this repo, so it is updated in place without a backup.
  if [ -f "$SKILL_DIR/SKILL.md" ] && cmp -s "$TMP_DIR/SKILL.md" "$SKILL_DIR/SKILL.md"; then
    info "$SKILL_DIR/SKILL.md already up to date"
  else
    cat "$TMP_DIR/SKILL.md" > "$SKILL_DIR/SKILL.md" || die "failed to write $SKILL_DIR/SKILL.md"
    info "Installed kaneo-work-tracking skill to $SKILL_DIR"
  fi
  sync_instructions
  install_mcp
  info "Done. Restart Claude Code to load the skill and the MCP server; run /mcp to check the Kaneo connection."
}

case "${1:-}" in
  --uninstall|uninstall) uninstall ;;
  ""|--install|install) install ;;
  *) die "unknown argument: $1 (use --uninstall)" ;;
esac
