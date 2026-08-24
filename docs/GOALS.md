# Goals

## Mission

de-harness is an AI-agent engineering harness for data engineering repositories.
It gives an AI coding agent (and the humans reviewing its work) a shared,
enforceable set of conventions, checks, and guardrails for building and
changing data pipelines — so agent-driven changes to a DE codebase are held to
the same bar as changes to any other production system, plus the practices
that are specific to moving and transforming data (idempotency, schema
contracts, data quality, backfill safety).

It is the data-engineering sibling of
[ai-harness](https://github.com/enfazz/stack-agnostic-ai-harness): same
layered shape (conventions, detection, execution, guardrails,
self-verification), re-specialized for DE work instead of general software
engineering. See [ARCHITECTURE.md](ARCHITECTURE.md) for how the layers map.

## v1 scope: target stack

de-harness is being built incrementally. v1 deliberately narrows scope to keep
the conventions coherent and testable, rather than trying to cover every DE
stack at once.

**v1 (in scope now):**
- Python + SQL pipelines
- dbt (transformations, tests, `schema.yml` contracts)
- Airflow / Dagster (orchestration)

**Planned, not yet built:**
- Spark / PySpark (large-scale batch processing)
- Streaming (Kafka, Flink)
- Cloud data warehouse specifics (Snowflake, BigQuery, Redshift) beyond what
  dbt already abstracts

These are real targets for de-harness, not rejected ideas — they're deferred so
v1 ships a harness that actually works end-to-end for one stack before
detection, gates, and guardrails are generalized to the others. A later phase
extends `detect-stack`-equivalent tooling and stack-specific gate commands to
cover them; nothing in v1 should claim support it doesn't have yet.

## Audience

de-harness is meant to be adopted as a **team standard**: installed into
multiple data engineering repositories across a team or org, not tied to one
person's project. Conventions and docs should read as generic and adoptable —
if a rule only makes sense for one specific pipeline, it belongs in that
repo's own `CLAUDE.md`, not here.

## Non-goals

- de-harness does not manage secrets, deploy infrastructure, or apply
  Terraform/IaC changes — those stay with a human and are explicitly denied by
  default (mirrors ai-harness's non-goal here).
- It does not replace a data catalog, orchestrator, or data quality tool — it
  encodes conventions for *using* dbt/Airflow/Dagster/Great
  Expectations/etc. well, it doesn't reimplement them.
- It does not hardcode any project's specific schema, warehouse, or business
  logic — the conventions are stack-level, not pipeline-level.
- It is not, in its current state, an installable plugin with working
  detection/skills/hooks — see [ARCHITECTURE.md](ARCHITECTURE.md) for what's
  built versus planned.
