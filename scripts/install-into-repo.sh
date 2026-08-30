#!/usr/bin/env bash
# install-into-repo.sh — install de-harness conventions into a data engineering
# repository for Codex / Cursor / and the ~20 other tools that read AGENTS.md.
#
# Claude Code users do NOT need this — install the plugin instead:
#   /plugin marketplace add jtteotn9/de-harness && /plugin install de-harness
#
# Safe to re-run: it is how you pick up updated conventions. An existing
# AGENTS.md is preserved — de-harness content lives between markers and only
# that block is rewritten. Cursor rules are namespaced de-harness-*.mdc so they
# never collide with rules the repo already has.
#
# Usage: scripts/install-into-repo.sh <target-repo>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"
DIST="$ROOT/dist"

[ -n "$TARGET" ] || { echo "usage: $(basename "$0") <target-repo>" >&2; exit 2; }
[ -d "$TARGET" ] || { echo "error: $TARGET is not a directory" >&2; exit 2; }
[ -f "$DIST/AGENTS.md" ] || { echo "error: $DIST/AGENTS.md missing — run scripts/build-agent-rules.sh first" >&2; exit 1; }

BEGIN='<!-- BEGIN de-harness conventions (generated — do not edit inside this block) -->'
END='<!-- END de-harness conventions -->'
AGENTS="$TARGET/AGENTS.md"
BLOCK="$(mktemp)"; trap 'rm -f "$BLOCK"' EXIT
{ printf '%s\n' "$BEGIN"; cat "$DIST/AGENTS.md"; printf '%s\n' "$END"; } > "$BLOCK"

if [ ! -f "$AGENTS" ]; then
  cp "$BLOCK" "$AGENTS"
  echo "  created  AGENTS.md"
elif grep -qF "$BEGIN" "$AGENTS"; then
  # Replace only the de-harness block, leaving the repo's own content intact.
  awk -v b="$BEGIN" -v e="$END" -v blockfile="$BLOCK" '
    index($0, b) == 1 { skip = 1; while ((getline line < blockfile) > 0) print line; next }
    index($0, e) == 1 { skip = 0; next }
    !skip { print }
  ' "$AGENTS" > "$AGENTS.tmp" && mv "$AGENTS.tmp" "$AGENTS"
  echo "  updated  AGENTS.md (de-harness block)"
else
  # Repo has its own AGENTS.md and no de-harness block yet — append, don't clobber.
  { printf '\n'; cat "$BLOCK"; } >> "$AGENTS"
  echo "  appended AGENTS.md (kept existing content)"
fi

mkdir -p "$TARGET/.cursor/rules"
for f in "$DIST"/.cursor/rules/de-harness-*.mdc; do
  cp "$f" "$TARGET/.cursor/rules/$(basename "$f")"
  echo "  wrote    .cursor/rules/$(basename "$f")"
done

echo
echo "Done. Re-run after updating de-harness to pick up new conventions."
