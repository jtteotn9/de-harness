#!/usr/bin/env bash
# PreToolUse(Bash): refuse destructive operations against production data.
#
# Enforces the non-negotiables already written in base/CLAUDE.base.md:
#   - no DROP / TRUNCATE / unscoped DELETE without explicit human confirmation
#   - no full-table rebuilds outside an explicitly non-production target
#   - backfills are a reviewed operation, never a side effect
#
# DESIGN NOTE — precision over breadth.
# A guard that blocks legitimate work is worse than no guard: people disable it.
# So SQL keywords are only treated as dangerous when a database client is
# actually being invoked. Searching, reading or writing SQL that happens to
# contain the word DROP is not an execution and is never blocked:
#
#   grep -r "DROP TABLE" migrations/     -> allowed (no client invoked)
#   cat drop_legacy.sql                  -> allowed
#   psql -c "DROP TABLE users"           -> BLOCKED
#
# Escape hatch: a human can add an `allow-command <glob>` line to the overrides
# file under .de-harness/ (see README). The guard refuses shell edits to that
# file, so every override implies a human made it deliberately.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/_lib.sh"

de_read_stdin
cmd="$(de_json command)"
[ -n "$cmd" ] || exit 0

# Collapse newlines so multi-line commands match as one string.
norm="$(printf '%s' "$cmd" | tr '\n\t' '  ')"
has() { printf '%s' "$norm" | grep -Eqi "$1"; }

# A human-authored override wins over everything below.
de_override allow-command "$cmd" && exit 0

# --- tamper check ------------------------------------------------------------
# Reading or grepping the overrides file is fine; only writing it is refused.
# (Blocking every mention produces false positives on documentation and search.)
if has 'guard-overrides'; then
  if has '(>>?|[[:space:]]tee[[:space:]]|sed[[:space:]]+-i|(^|[[:space:]])(rm|mv|cp|truncate|install|dd)[[:space:]])'; then
    de_deny "writing the guard overrides file from the shell is not allowed — overrides are human-authored by design. Reading it is fine."
  fi
fi

# --- destructive SQL, but only when a client is actually invoked -------------
DB_CLIENT='(^|[;&|(`[:space:]])(psql|mysql|mariadb|snowsql|bq|clickhouse-client|duckdb|sqlite3|athena|spark-sql|trino|presto|sqlcmd|dbt)([[:space:]]|$)'

if has "$DB_CLIENT"; then
  if has 'DROP[[:space:]]+(TABLE|SCHEMA|DATABASE|VIEW|MATERIALIZED[[:space:]]+VIEW)'; then
    de_deny "DROP against a database is irreversible and needs explicit human confirmation. Prefer a reversible path (write to a new table, then swap). A human can allow this with an 'allow-command' override."
  fi
  if has 'TRUNCATE([[:space:]]+TABLE)?[[:space:]]+[a-z_\"`.]'; then
    de_deny "TRUNCATE empties a table irreversibly and needs explicit human confirmation. Prefer a scoped DELETE ... WHERE, or write-then-swap."
  fi
  if has 'DELETE[[:space:]]+FROM' && ! has '[[:space:]]WHERE[[:space:]]'; then
    de_deny "DELETE FROM without a WHERE clause removes every row. Scope it with WHERE, or get explicit human confirmation."
  fi
fi

# --- warehouse CLIs that delete outside SQL ----------------------------------
# Flags may carry values ("bq --project_id acme rm ..."), so skip any run of
# flag/value tokens before the subcommand rather than bare flags only.
BQ_FLAG='--?[a-zA-Z_][a-zA-Z0-9_-]*(=[^[:space:]]+)?([[:space:]]+[^-[:space:]][^[:space:]]*)?'
if has "(^|[;&|[:space:]])bq([[:space:]]+$BQ_FLAG)*[[:space:]]+rm([[:space:]]|$)"; then
  de_deny "'bq rm' deletes a BigQuery table or dataset irreversibly. A human should run this directly if it is really intended."
fi

# --- orchestrator operations that reprocess or destroy state -----------------
if has 'airflow[[:space:]]+dags[[:space:]]+backfill'; then
  de_deny "a backfill is a first-class, reviewed operation — never run one unattended. State the partition range, the rows affected, the downstream consumers and the expected cost, and get human sign-off first."
fi
if has 'airflow[[:space:]]+tasks[[:space:]]+clear'; then
  de_deny "'airflow tasks clear' re-runs historical task instances, which silently reprocesses data. Treat it as a backfill: state the range and impact, and get human sign-off."
fi
if has 'airflow[[:space:]]+db[[:space:]]+(reset|clean|downgrade)'; then
  de_deny "this destroys Airflow metadata (history, task state). A human should do it directly."
fi

# --- dbt full rebuilds -------------------------------------------------------
# --full-refresh drops and recreates incremental models. Safe targets are
# allow-listed rather than production being deny-listed: if the target is not
# demonstrably non-production, fail toward asking.
if has 'dbt[[:space:]]+(run|build|seed)' && has '[[:space:]]--full-refresh([[:space:]]|$)'; then
  if ! has '([[:space:]]--target[[:space:]]+|[[:space:]]-t[[:space:]]+|DBT_TARGET=)(dev|local|ci|test|sandbox|staging)([[:space:]]|$)'; then
    de_deny "--full-refresh drops and rebuilds incremental models. Run it against an explicitly non-production target (e.g. --target dev), or get human sign-off for a production rebuild."
  fi
fi

exit 0
