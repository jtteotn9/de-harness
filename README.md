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

## Installing

de-harness is a Claude Code plugin. Add this repo as a marketplace and install
it:

```
/plugin marketplace add jtteotn9/de-harness
/plugin install de-harness
```

Today that gives you the conventions layer — `base/CLAUDE.base.md`, imported
into a target repo's `CLAUDE.md`. There are no skills or commands yet.

## Development

No build step and no dependencies — the repo is Markdown and JSON, checked by
Bash and the Python 3 standard library. Run the gate before every commit:

```bash
bash tests/run-all.sh
```

It validates the plugin manifests, any skill/agent frontmatter, the DE
convention invariants in `base/CLAUDE.base.md`, and that relative Markdown links
resolve. Checks for layers that don't exist yet report "none yet" instead of
failing, so the gate stays green as the harness grows.

Work on a branch and open a pull request; nothing here auto-merges. Commit under
your own git identity with a clear message and **no AI co-author trailer** — a
rule `tests/run-all.sh` asserts is still documented in `base/CLAUDE.base.md`.
