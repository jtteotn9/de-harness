#!/usr/bin/env bash
# test-scan.sh — scripts/scan-de-repo.py against golden fixtures.
#
# The scanner contributes facts, not judgement, so its output is diffable and
# every claim here is exact. Three properties matter most:
#   - it degrades honestly when the dbt manifest is absent (confidence drops)
#   - it never emits warehouse credentials
#   - it never executes pipeline code
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$ROOT/scripts/scan-de-repo.py"
FAIL=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1"; FAIL=1; }

# fact <output-file> <key> -> value
fact(){ grep -m1 "^de\.$2=" "$1" 2>/dev/null | cut -d= -f2-; }

expect(){ # expect <file> <key> <value>
  local got; got="$(fact "$1" "$2")"
  if [ "$got" = "$3" ]; then ok "$2=$3"
  else bad "$2: expected '$3', got '$got'"; fi
}

echo "-- dbt project with a manifest (authoritative)"
OUT="$TMP/dbt.txt"
python3 "$SCAN" "$ROOT/fixtures/dbt-project" > "$OUT" 2>/dev/null
expect "$OUT" confidence high
expect "$OUT" stack dbt
expect "$OUT" models 4
expect "$OUT" tests 2
expect "$OUT" sources 2
expect "$OUT" exposures 1
expect "$OUT" dbt.adapter bigquery
expect "$OUT" materializations "incremental:1,table:1,view:2"
expect "$OUT" max_depth 1
expect "$OUT" models_described 2

echo
echo "-- the findings a newcomer actually needs"
expect "$OUT" models_untested 3
expect "$OUT" models_untested_sample "dim_customer,fct_revenue,stg_events"
expect "$OUT" sources_without_freshness 1
expect "$OUT" sources_without_freshness_sample "raw.charges"
expect "$OUT" exposed_models "fct_revenue"
# stg_charges feeds two models -> highest blast radius.
case "$(fact "$OUT" high_fanout)" in
  stg_charges:2*) ok "high_fanout ranks the most-depended-on model first" ;;
  *) bad "high_fanout did not rank stg_charges first: $(fact "$OUT" high_fanout)" ;;
esac

echo
echo "-- degrades honestly when the manifest is missing"
cp -r "$ROOT/fixtures/dbt-project" "$TMP/nomanifest"
rm -f "$TMP/nomanifest/target/manifest.json"
OUT2="$TMP/nomanifest.txt"
python3 "$SCAN" "$TMP/nomanifest" > "$OUT2" 2>/dev/null
expect "$OUT2" confidence low
expect "$OUT2" models 4          # counted from .sql files, not lineage
expect "$OUT2" dbt.project acme_warehouse
expect "$OUT2" dbt.profile acme
[ -z "$(fact "$OUT2" max_depth)" ] \
  && ok "no lineage facts claimed without a manifest" \
  || bad "shallow scan invented a lineage fact (max_depth)"

echo
echo "-- airflow DAGs are parsed, never imported"
OUT3="$TMP/dags.txt"
python3 "$SCAN" "$ROOT/fixtures/airflow-dags" > "$OUT3" 2>/dev/null
expect "$OUT3" stack airflow
expect "$OUT3" dag_ids "customer_sync,revenue_daily"
expect "$OUT3" dag_schedules "0 6 * * *,@hourly"
# One fixture DAG is deliberately unparseable: it must be skipped, not fatal.
expect "$OUT3" dag_files 3

MARKER="$TMP/executed"
mkdir -p "$TMP/exec/dags"
printf 'open("%s", "w").write("boom")\nfrom airflow import DAG\n' "$MARKER" > "$TMP/exec/dags/evil.py"
python3 "$SCAN" "$TMP/exec" >/dev/null 2>&1
[ -f "$MARKER" ] && bad "scanner EXECUTED dag code" || ok "top-level DAG code is never executed"

echo
echo "-- no data engineering markers: says nothing rather than inventing"
mkdir -p "$TMP/plain"; printf '# just a repo\n' > "$TMP/plain/README.md"
OUT4="$TMP/plain.txt"
python3 "$SCAN" "$TMP/plain" > "$OUT4" 2>/dev/null
expect "$OUT4" confidence none
expect "$OUT4" stack ""
[ "$(grep -c '^de\.models=' "$OUT4")" = "0" ] \
  && ok "no model counts invented for a non-DE repo" \
  || bad "invented model facts for a repo with no markers"

echo
echo "-- warehouse credentials never reach the output"
cp -r "$ROOT/fixtures/dbt-project" "$TMP/withcreds"
# Generated at runtime — never commit anything credential-shaped, even fake.
SECRET="pw_$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
printf 'acme:\n  outputs:\n    prod:\n      type: bigquery\n      password: %s\n' "$SECRET" \
  > "$TMP/withcreds/profiles.yml"
OUT5="$TMP/withcreds.txt"
python3 "$SCAN" "$TMP/withcreds" > "$OUT5" 2>&1
if grep -q "$SECRET" "$OUT5"; then bad "a credential value leaked into scanner output"
else ok "credential value never appears in output"; fi

echo
echo "-- deterministic: same input, byte-identical output"
python3 "$SCAN" "$ROOT/fixtures/dbt-project" > "$TMP/run1.txt" 2>/dev/null
python3 "$SCAN" "$ROOT/fixtures/dbt-project" > "$TMP/run2.txt" 2>/dev/null
diff -q "$TMP/run1.txt" "$TMP/run2.txt" >/dev/null \
  && ok "repeat runs are byte-identical" || bad "output is not deterministic"

echo
echo "-- a corrupt manifest degrades instead of crashing"
cp -r "$ROOT/fixtures/dbt-project" "$TMP/corrupt"
printf '{not json' > "$TMP/corrupt/target/manifest.json"
if python3 "$SCAN" "$TMP/corrupt" > "$TMP/corrupt.txt" 2>/dev/null; then
  expect "$TMP/corrupt.txt" confidence low
else
  bad "scanner crashed on a corrupt manifest"
fi

echo
[ "$FAIL" -eq 0 ] && echo "scan suite: PASS" || echo "scan suite: FAIL"
exit "$FAIL"
