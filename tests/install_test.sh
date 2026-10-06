#!/usr/bin/env bash
# Exercises install.sh against throwaway CLAUDE_DIRs. Requires jq.
#   ./tests/install_test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BEGIN_RE='^<!-- BEGIN kaneo-work-tracking-skill'
URL='https://kaneo.example.com'
FAILS=0

pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

# Never prompt on the real terminal: no tty unless a test passes KANEO_TTY.
run() { KANEO_TTY="${KANEO_TTY:-$WORK/no-tty}" CLAUDE_DIR="$1" "$ROOT/install.sh" "${@:2}" >/dev/null 2>&1; }
fresh() { rm -rf "$WORK/$1"; mkdir -p "$WORK/$1"; echo "$WORK/$1"; }
backups() { find "$1" -maxdepth 1 -name '*.bak.*' | wc -l | tr -d ' '; }
mcp_url() { jq -r '.mcpServers.kaneo.url // empty' "$1/.claude.json"; }

# Fresh install into an empty dir.
d="$(fresh empty)"
KANEO_URL="$URL/" run "$d"
check "fresh install copies the skill" "[ -f '$d/skills/kaneo-work-tracking/SKILL.md' ]"
check "fresh install creates the managed block" "grep -q '$BEGIN_RE' '$d/CLAUDE.md'"
check "fresh install registers the MCP endpoint" "[ \"\$(mcp_url '$d')\" = '$URL/api/mcp' ]"
check "MCP server uses http transport" "[ \"\$(jq -r .mcpServers.kaneo.type '$d/.claude.json')\" = http ]"

# A pasted /api/mcp suffix and trailing slashes are normalized.
d="$(fresh normalize)"
KANEO_URL=" $URL/api/mcp// " run "$d"
check "pasted /api/mcp suffix is not doubled" "[ \"\$(mcp_url '$d')\" = '$URL/api/mcp' ]"

# Invalid URLs are refused before writing MCP config.
d="$(fresh invalid)"
check "invalid KANEO_URL fails the install" "! KANEO_URL='kaneo.example.com' run '$d'"
check "invalid KANEO_URL writes no MCP config" "[ ! -e '$d/.claude.json' ]"

# Re-run is a no-op.
d="$(fresh rerun)"
printf '# my rules\nkeep me\n' > "$d/CLAUDE.md"
echo '{"numStartups":3,"mcpServers":{"other":{"type":"http","url":"https://x.test/mcp"}}}' > "$d/.claude.json"
KANEO_URL="$URL" run "$d"
before="$(cat "$d/CLAUDE.md" "$d/.claude.json" | cksum)"
n="$(backups "$d")"
KANEO_URL="$URL" run "$d"
check "re-run leaves files unchanged" "[ \"\$(cat '$d/CLAUDE.md' '$d/.claude.json' | cksum)\" = '$before' ]"
check "re-run makes no new backups" "[ \"\$(backups '$d')\" = '$n' ]"
check "existing content and MCP servers are kept" "grep -qx 'keep me' '$d/CLAUDE.md' && [ \"\$(jq -r .mcpServers.other.url '$d/.claude.json')\" = https://x.test/mcp ] && [ \"\$(jq -r .numStartups '$d/.claude.json')\" = 3 ]"
check "exactly one managed block" "[ \"\$(grep -c '$BEGIN_RE' '$d/CLAUDE.md')\" = 1 ]"

# A config formatted unlike jq output is not rewritten when Kaneo is already current.
d="$(fresh compact)"
printf '{"a":1,"mcpServers":{"kaneo":{"type":"http","url":"%s/api/mcp"}}}' "$URL" > "$d/.claude.json"
cp "$d/.claude.json" "$WORK/compact.json"
run "$d"
check "current Kaneo config is not reformatted" "cmp -s '$WORK/compact.json' '$d/.claude.json' && [ \"\$(backups '$d')\" = 0 ]"

# Updating the skill replaces it in place without leaving backups in the skills directory.
echo 'stale' > "$d/skills/kaneo-work-tracking/SKILL.md"
run "$d"
check "stale skill is updated" "cmp -s '$ROOT/skills/kaneo-work-tracking/SKILL.md' '$d/skills/kaneo-work-tracking/SKILL.md'"
check "skill update leaves no backups" "[ \"\$(ls '$d/skills/kaneo-work-tracking')\" = SKILL.md ]"

d="$WORK/rerun"
# Without a terminal or KANEO_URL, the configured endpoint is kept.
run "$d"
check "no tty keeps the configured endpoint" "[ \"\$(cat '$d/CLAUDE.md' '$d/.claude.json' | cksum)\" = '$before' ]"

# Without a terminal, KANEO_URL, or prior config, MCP setup is skipped and the skill still installs.
d="$(fresh notty)"
check "no tty and no URL still succeeds" "run '$d'"
check "no tty and no URL skips MCP config" "[ ! -e '$d/.claude.json' ] && [ -f '$d/skills/kaneo-work-tracking/SKILL.md' ]"

# The plain prompt reads the answer from the terminal.
d="$(fresh prompt)"
printf 'https://kaneo.prompted.test/\n' > "$WORK/tty"
KANEO_TTY="$WORK/tty" KANEO_TUI=plain run "$d"
check "prompted URL is registered" "[ \"\$(mcp_url '$d')\" = 'https://kaneo.prompted.test/api/mcp' ]"
check "prompt is shown on the terminal" "grep -q 'Kaneo base URL' '$WORK/tty'"

# Re-running with a terminal updates silently: no prompt once Kaneo is configured.
printf 'https://kaneo.other.test/\n' > "$WORK/tty"
KANEO_TTY="$WORK/tty" KANEO_TUI=plain run "$d"
check "re-run with a terminal does not prompt" "! grep -q 'Kaneo base URL' '$WORK/tty'"
check "re-run with a terminal keeps the configured URL" "[ \"\$(mcp_url '$d')\" = 'https://kaneo.prompted.test/api/mcp' ]"

# KANEO_RECONFIGURE asks again; an empty answer accepts the configured base URL as the default.
printf '\n' > "$WORK/tty"
KANEO_RECONFIGURE=1 KANEO_TTY="$WORK/tty" KANEO_TUI=plain run "$d"
check "KANEO_RECONFIGURE prompts again" "grep -q 'Kaneo base URL' '$WORK/tty'"
check "empty answer keeps the configured base URL" "[ \"\$(mcp_url '$d')\" = 'https://kaneo.prompted.test/api/mcp' ]"

# KANEO_URL replaces the configured endpoint.
KANEO_URL='https://kaneo.moved.test' run "$d"
check "KANEO_URL replaces the configured endpoint" "[ \"\$(mcp_url '$d')\" = 'https://kaneo.moved.test/api/mcp' ]"

# Repeated invalid answers stop the install.
d="$(fresh badprompt)"
printf 'not a url\n' > "$WORK/tty"
check "three invalid answers fail the install" "! KANEO_TTY='$WORK/tty' KANEO_TUI=plain run '$d'"

# SKIP_MCP leaves the Claude config alone.
d="$(fresh skipmcp)"
SKIP_MCP=1 KANEO_URL="$URL" run "$d"
check "SKIP_MCP writes no MCP config" "[ ! -e '$d/.claude.json' ]"

# Edits inside the block are resynced.
d="$(fresh tamper)"
KANEO_URL="$URL" run "$d"
before="$(cksum < "$d/CLAUDE.md")"
sed -i.tmp 's/never guess them/guess them/' "$d/CLAUDE.md" && rm -f "$d/CLAUDE.md.tmp"
check "tamper edit landed inside the block" "! grep -q 'never guess them' '$d/CLAUDE.md'"
KANEO_URL="$URL" run "$d"
check "edits inside the block are overwritten" "[ \"\$(cksum < '$d/CLAUDE.md')\" = '$before' ]"

# Install then uninstall restores the original files.
d="$(fresh roundtrip)"
printf '# my rules\nkeep me\n' > "$d/CLAUDE.md"
echo '{"mcpServers":{"other":{"type":"http","url":"https://x.test/mcp"}}}' | jq . > "$d/.claude.json"
cp "$d/CLAUDE.md" "$WORK/orig.md"
cp "$d/.claude.json" "$WORK/orig.json"
KANEO_URL="$URL" run "$d" && run "$d" --uninstall
check "install + uninstall restores CLAUDE.md" "cmp -s '$WORK/orig.md' '$d/CLAUDE.md'"
check "install + uninstall restores .claude.json" "cmp -s '$WORK/orig.json' '$d/.claude.json'"
check "uninstall removes the skill" "[ ! -e '$d/skills/kaneo-work-tracking' ]"

# A file without a trailing newline gets the block on its own lines.
d="$(fresh nonewline)"
printf 'no newline' > "$d/CLAUDE.md"
SKIP_MCP=1 run "$d"
check "unterminated file keeps its last line intact" "grep -qx 'no newline' '$d/CLAUDE.md'"

# Symlinked files stay symlinks.
d="$(fresh symlink)"
mkdir -p "$WORK/dotfiles"
printf '# dotfiles\n' > "$WORK/dotfiles/CLAUDE.md"
echo '{}' > "$WORK/dotfiles/claude.json"
ln -s "$WORK/dotfiles/CLAUDE.md" "$d/CLAUDE.md"
ln -s "$WORK/dotfiles/claude.json" "$d/.claude.json"
KANEO_URL="$URL" run "$d"
check "symlinked CLAUDE.md stays a symlink" "[ -L '$d/CLAUDE.md' ] && grep -q '$BEGIN_RE' '$WORK/dotfiles/CLAUDE.md'"
check "symlinked .claude.json stays a symlink" "[ -L '$d/.claude.json' ] && [ \"\$(jq -r .mcpServers.kaneo.url '$WORK/dotfiles/claude.json')\" = '$URL/api/mcp' ]"

# Invalid JSON is never overwritten.
d="$(fresh badjson)"
echo '{not json' > "$d/.claude.json"
check "invalid .claude.json fails the install" "! KANEO_URL='$URL' run '$d'"
check "invalid .claude.json is left as is" "[ \"\$(cat '$d/.claude.json')\" = '{not json' ]"

# Damaged markers stop install and uninstall before any change.
B='<!-- BEGIN kaneo-work-tracking-skill: managed by install.sh, edits inside this block are overwritten -->'
E='<!-- END kaneo-work-tracking-skill -->'
for name in missing-end reversed; do
  d="$(fresh "damaged-$name")"
  KANEO_URL="$URL" run "$d"
  case "$name" in
    missing-end) printf '%s\nx\n' "$B" > "$d/CLAUDE.md" ;;
    reversed)    printf '%s\nx\n%s\n' "$E" "$B" > "$d/CLAUDE.md" ;;
  esac
  cp "$d/CLAUDE.md" "$WORK/damaged.md"
  check "$name markers: install refuses" "! KANEO_URL='$URL' run '$d'"
  check "$name markers: uninstall refuses" "! run '$d' --uninstall"
  check "$name markers: nothing removed" "[ -f '$d/skills/kaneo-work-tracking/SKILL.md' ] && [ -n \"\$(mcp_url '$d')\" ] && cmp -s '$WORK/damaged.md' '$d/CLAUDE.md'"
done

# No temp files leak, on success or failure.
mkdir -p "$WORK/tmp"
TMPDIR="$WORK/tmp" KANEO_URL="$URL" run "$(fresh tmpcheck)"
TMPDIR="$WORK/tmp" run "$WORK/damaged-missing-end"
check "no temp files left behind" "[ -z \"\$(ls -A '$WORK/tmp')\" ]"

echo
[ "$FAILS" = 0 ] && echo "all tests passed" || { echo "$FAILS test(s) failed"; exit 1; }
