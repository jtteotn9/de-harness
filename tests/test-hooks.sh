#!/usr/bin/env bash
# test-hooks.sh — the destructive-data guard.
#
# Two halves, equally important:
#   BLOCK  — destructive production operations must be refused.
#   ALLOW  — legitimate work must still run. A guard that cries wolf gets
#            switched off, so false positives are treated as failures here.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/hooks/guard-data-ops.sh"
FAIL=0

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export DE_AUDIT_LOG="$TMP/audit.jsonl"

# Feed a command to the guard as a PreToolUse payload; echo its exit code.
guard() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" \
    | bash "$GUARD" >/dev/null 2>&1
  echo $?
}

expect_block() {
  local rc; rc="$(guard "$1")"
  if [ "$rc" = "2" ]; then echo "ok   blocked: $1"
  else echo "FAIL not blocked (rc=$rc): $1"; FAIL=1; fi
}

expect_allow() {
  local rc; rc="$(guard "$1")"
  if [ "$rc" = "0" ]; then echo "ok   allowed: $1"
  else echo "FAIL wrongly blocked (rc=$rc): $1"; FAIL=1; fi
}

echo "-- destructive SQL through a database client"
expect_block 'psql -c "DROP TABLE users"'
expect_block 'snowsql -q "TRUNCATE TABLE analytics.fct_revenue"'
expect_block 'psql -h warehouse -c "DELETE FROM events"'
expect_block 'bq query --use_legacy_sql=false "DROP VIEW analytics.v_daily"'
expect_block 'duckdb warehouse.db -c "DROP SCHEMA staging CASCADE"'

echo
echo "-- warehouse CLIs that delete outside SQL"
expect_block 'bq rm -r -f analytics_staging'
expect_block 'bq --project_id acme rm mydataset.mytable'

echo
echo "-- orchestrator operations that reprocess or destroy state"
expect_block 'airflow dags backfill revenue_daily -s 2026-01-01 -e 2026-06-30'
expect_block 'airflow tasks clear revenue_daily'
expect_block 'airflow db reset'

echo
echo "-- dbt rebuilds outside an explicitly non-production target"
expect_block 'dbt build --full-refresh --target prod'
expect_block 'dbt run --full-refresh'
expect_block 'DBT_TARGET=production dbt run --full-refresh'

echo
echo "-- writing the overrides file from the shell"
expect_block 'echo "allow-command dbt run *" > .de-harness/guard-overrides.conf'
expect_block 'sed -i s/x/y/ .de-harness/guard-overrides.conf'

echo
echo "-- FALSE POSITIVES: searching or reading SQL is not executing it"
expect_allow 'grep -r "DROP TABLE" migrations/'
expect_allow 'rg TRUNCATE models/'
expect_allow 'cat drop_legacy_tables.sql'
expect_allow 'git commit -m "Add DROP TABLE migration for legacy events"'
expect_allow 'echo "DELETE FROM users" >> notes.md'
expect_allow 'cat .de-harness/guard-overrides.conf'
expect_allow 'grep allow-command .de-harness/guard-overrides.conf'

echo
echo "-- FALSE POSITIVES: legitimate data engineering work"
expect_allow 'psql -c "DELETE FROM events WHERE ts < timestamp 2020-01-01"'
expect_allow 'dbt run --full-refresh --target dev'
expect_allow 'dbt build --full-refresh --target ci'
expect_allow 'dbt test'
expect_allow 'dbt build --target prod'
expect_allow 'dbt run --select stg_drop_shipments'
expect_allow 'airflow dags list'
expect_allow 'airflow dags test revenue_daily 2026-01-01'
expect_allow 'python pipelines/etl.py --mode full'
expect_allow 'bq query --use_legacy_sql=false "SELECT count(*) FROM analytics.fct_revenue"'

echo
echo "-- a human-authored override permits a specific blocked command"
REPO="$TMP/repo"; mkdir -p "$REPO/.de-harness"
( cd "$REPO" && git init -q . )
printf '# reviewed by a human\nallow-command dbt run --full-refresh --target prod\n' \
  > "$REPO/.de-harness/guard-overrides.conf"
rc="$( cd "$REPO" && python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' \
        'dbt run --full-refresh --target prod' | bash "$GUARD" >/dev/null 2>&1; echo $? )"
if [ "$rc" = "0" ]; then echo "ok   override allows the exact command a human approved"
else echo "FAIL override did not take effect (rc=$rc)"; FAIL=1; fi

rc="$( cd "$REPO" && python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' \
        'dbt run --full-refresh --target other-prod' | bash "$GUARD" >/dev/null 2>&1; echo $? )"
if [ "$rc" = "2" ]; then echo "ok   override does not leak to other commands"
else echo "FAIL override was too broad (rc=$rc)"; FAIL=1; fi

echo
echo "-- non-Bash payloads and empty commands are ignored"
rc="$(printf '{"tool_name":"Read","tool_input":{"file_path":"a.sql"}}' | bash "$GUARD" >/dev/null 2>&1; echo $?)"
[ "$rc" = "0" ] && echo "ok   ignores payloads with no command" || { echo "FAIL rc=$rc on a non-Bash payload"; FAIL=1; }

echo
[ "$FAIL" -eq 0 ] && echo "hooks suite: PASS" || echo "hooks suite: FAIL"
exit "$FAIL"
