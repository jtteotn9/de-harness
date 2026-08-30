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
├── Guardrails & autonomy ───────────────────────────────────┤  PARTIAL
│  hooks/guard-data-ops.sh refuses destructive production       │
│  operations: DROP/TRUNCATE/unscoped DELETE through a DB       │
│  client, bq rm, unattended backfills, and --full-refresh      │
│  outside a non-prod target. Human-authored overrides. Still   │
│  to do: forcing DQ checks at Stop, secret-in-profiles guard,  │
│  autonomy profiles.                                           │
├── Self-verification ───────────────────────────────────────┤  PARTIAL
│  tests/run-all.sh is the repo's own gate: manifests, skill    │
│  frontmatter, DE convention invariants, doc links. Fixture    │
│  DE repos (a dbt project, an Airflow DAG repo) remain to do.  │
└─────────────────────────────────────────────────────────────┘
```

## Current state

The **Conventions** layer exists (`base/CLAUDE.base.md`, `docs/GOALS.md`), and
the repo is now an installable plugin (`.claude-plugin/marketplace.json`) with
its own gate (`tests/run-all.sh`). The first guardrail hook is in place
(`hooks/guard-data-ops.sh`, refusing destructive production operations). There
is still no detection script, no skills, no agents, and no fixtures —
`README.md` reflects this as "early scaffolding." Nothing in this repo should be
described or installed as if the later layers already work.

## Distribution across agent tools

`base/CLAUDE.base.md` is the single source of truth. Everything under `dist/` is
generated from it by `scripts/build-agent-rules.sh`, and the gate regenerates
and diffs so the copies cannot drift:

```
base/CLAUDE.base.md ──┬──▶ .claude-plugin/          Claude Code plugin
   (source of truth)  ├──▶ dist/AGENTS.md           Codex, Cursor, +20 tools
                      └──▶ dist/.cursor/rules/*.mdc Cursor, scoped by globs
```

`AGENTS.md` is a neutral format stewarded by the Agentic AI Foundation, so one
file reaches Codex, Cursor, Copilot, Gemini CLI, Zed and others. Cursor
additionally gets `.mdc` rules, which support `globs` — that lets the SQL
conventions attach to `*.sql`/`schema.yml` and the orchestration conventions to
`dags/`, rather than loading everything on every file. Each convention section
appears in exactly one `.mdc` (asserted by `tests/test-agent-rules.sh`). Legacy
`.cursorrules` is deliberately not emitted: it is silently ignored in Cursor
Agent mode.

`scripts/install-into-repo.sh` installs the bundle into a target DE repo and is
safe to re-run — that is how a repo picks up updated conventions.

**Portability limit.** Conventions port at full fidelity; skills will port
partially (Cursor commands, Codex prompts) once they exist. The guardrail hooks
depend on Claude Code's hook API and have no Codex/Cursor equivalent — a Cursor
user reads "never DROP against production" as a rule, where a Claude Code user
has it refused before it runs. Enforcement stays Claude Code only, and the docs
must keep saying so rather than implying parity.

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
