#!/usr/bin/env bash
# Shared helpers for de-harness hooks. Hooks receive the event as JSON on stdin.
#
# de-harness is standalone: these helpers deliberately do not depend on
# ai-harness being installed. Both can run side by side.

de_read_stdin() { DE_INPUT="$(cat)"; }

# de_json <leaf-key-under-tool_input>  -> prints the value, or empty
de_json() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$DE_INPUT" | jq -r ".tool_input.${key} // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$DE_INPUT" | python3 -c "import sys,json
try:
    d = json.load(sys.stdin); print(d.get('tool_input', {}).get('$key', '') or '')
except Exception:
    pass" 2>/dev/null
  else
    printf '%s' "$DE_INPUT" \
      | grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
      | sed -E "s/.*:[[:space:]]*\"([^\"]*)\"/\1/"
  fi
}

# de_audit <event> <detail> — one JSONL line; never fails the caller.
de_audit() {
  local log="${DE_AUDIT_LOG:-$HOME/.de-harness/audit.jsonl}"
  mkdir -p "$(dirname "$log")" 2>/dev/null || return 0
  local repo detail
  repo="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  detail="$(printf '%s' "$2" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"ts":"%s","repo":"%s","event":"%s","detail":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$repo" "$1" "$detail" >> "$log" 2>/dev/null || true
}

# de_deny <message> -> block the tool call (exit 2), feeding the reason back.
de_deny() {
  de_audit "deny" "$1"
  printf '🛑 de-harness blocked this: %s\n' "$1" >&2
  exit 2
}

# de_override <type> <target> -> 0 if a human-authored override matches.
# Overrides live in <repo>/.de-harness/<the overrides file named in the README>,
# one rule per line:
#   allow-command <glob>    e.g.  allow-command dbt run --full-refresh --target ci
# HUMAN-ONLY by design: the guard refuses shell edits to that file, so every
# override implies a human decided to make it.
de_override() {
  local type="$1" target="$2" conf line pat
  conf="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/${DE_OVERRIDES_REL:-.de-harness/guard-overrides.conf}"
  [ -f "$conf" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      "#"*|"") continue ;;
      "$type "*) pat="${line#"$type" }" ;;
      *) continue ;;
    esac
    # shellcheck disable=SC2254  # unquoted $pat is intentional: glob match
    case "$target" in $pat) return 0 ;; esac
  done < "$conf"
  return 1
}
