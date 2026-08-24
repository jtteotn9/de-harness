# de-harness

An AI-agent engineering harness for data engineering repositories — a shared
set of conventions, checks, and guardrails so agent-driven changes to
pipelines (dbt, Airflow/Dagster, and eventually Spark and streaming) are held
to the same bar as any other production change, plus the practices specific
to moving and transforming data: idempotency, schema contracts, data quality
gates, and safe backfills.

It's the data-engineering sibling of
[ai-harness](https://github.com/enfazz/stack-agnostic-ai-harness), meant to be
adopted as a team standard across multiple DE repos.

See [docs/GOALS.md](docs/GOALS.md) for the mission and v1 scope, and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it's structured.

## Status: early scaffolding

Only the conventions layer exists today (`base/CLAUDE.base.md`). Detection,
skills, agents, guardrail hooks, and self-verifying fixtures are planned but
not yet built — see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for what's
built versus planned.
