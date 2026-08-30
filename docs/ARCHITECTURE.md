# Architecture

de-harness follows the same five-layer shape as
[ai-harness](https://github.com/enfazz/stack-agnostic-ai-harness), re-specialized
for data engineering repos. Each layer is meant to be independently useful —
the conventions should be worth adopting even before detection, skills, or
guardrails exist.

```
┌── Conventions ─────────────────────────────────────────────┐  BUILT
│  base/CLAUDE.base.md — DE-specific working rules:           │
│  idempotency, schema contracts, data quality as part of     │
│  the gate, destructive-SQL confirmation, backfill review,   │
│  observability, cost awareness, PII handling.                │
├── Detection ───────────────────────────────────────────────┤  PLANNED
│  A detect-stack equivalent that maps DE marker files         │
│  (dbt_project.yml, dags/, great_expectations.yml,            │
│  pyspark/spark-submit usage, Kafka/Flink config) to gate      │
│  commands: `dbt build`, `dbt test`, pytest, Great             │
│  Expectations checkpoints, sqlfluff lint, etc.                │
├── Execution ───────────────────────────────────────────────┤  PLANNED
│  Skills (procedures) and agents (delegated specialists) for  │
│  DE workflows: adapting the harness into a DE repo, running   │
│  its DE-aware gate, planning/shipping pipeline changes,       │
│  writing dbt/pytest/Great-Expectations tests, reviewing a     │
│  pipeline PR for the conventions above.                       │
├── Guardrails & autonomy ───────────────────────────────────┤  PLANNED
│  Hooks enforcing the non-negotiables from CLAUDE.base.md:     │
│  block destructive SQL without confirmation, block committing │
│  connection strings / warehouse credentials, block            │
│  unattended backfills against production. Autonomy profiles   │
│  (readonly / supervised / autonomous) tune how much a DE       │
│  agent can do unattended.                                     │
├── Self-verification ───────────────────────────────────────┤  PARTIAL
│  tests/run-all.sh is the repo's own gate: manifests, skill    │
│  frontmatter, DE convention invariants, doc links. Fixture    │
│  DE repos (a dbt project, an Airflow DAG repo) remain to do.  │
└─────────────────────────────────────────────────────────────┘
```

## Current state

The **Conventions** layer exists (`base/CLAUDE.base.md`, `docs/GOALS.md`), and
the repo is now an installable plugin (`.claude-plugin/marketplace.json`) with
its own gate (`tests/run-all.sh`). There is still no detection script, no
skills, no agents, no hooks, and no fixtures — `README.md` reflects this as
"early scaffolding." Nothing in this repo should be described or installed as
if the later layers already work.

## Relationship to ai-harness

de-harness is **standalone** — it does not require ai-harness to be installed
and doesn't depend on its scripts or plugin machinery. The two are
conventions-compatible in spirit: de-harness's base file assumes the same
general engineering baseline ai-harness's `CLAUDE.base.md` states (smallest
correct change, verification before "done", PR-by-default, no secrets, no AI
co-author trailers) and adds data-engineering-specific rules on top, so a repo
could in principle layer both without contradiction. A future phase may
revisit whether de-harness should literally import ai-harness's generic base
file rather than restating those rules, once de-harness has enough of its own
layers built to make that call meaningfully.

## Non-goals

(See [GOALS.md](GOALS.md#non-goals) for the authoritative list.) In
particular: de-harness does not manage secrets, deploy infrastructure, or
apply IaC changes, and it does not reimplement dbt/Airflow/Dagster/data
quality tools — it encodes conventions for using them well.

## Extending (once later layers exist)

This section will be filled in as each planned layer is built — for now, the
pattern to follow is ai-harness's own `docs/ARCHITECTURE.md#extending`:
detection additions go in one script keyed by marker files, each skill is a
single `SKILL.md` with a numbered procedure, each guard is a `PreToolUse` hook
with a test case, and autonomy is tuned via a settings profile rather than by
hardcoding behavior into a skill.
