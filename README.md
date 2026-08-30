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

## Status: early, but usable

Three layers work today: the conventions (`base/CLAUDE.base.md`), a guardrail
hook that refuses destructive production operations, and the first command,
`/de-harness:investigate`. Detection (`detect-de-stack.sh`), the remaining
skills, and agents are still to come — see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for what's built versus planned.

## Commands

### `/de-harness:investigate`

Answers one question for someone arriving at an unfamiliar pipeline repo:
*"I know nothing about this project — what do I need in order to do my first
task safely?"*

It reads dbt's `target/manifest.json` when present (authoritative lineage,
tests and sources) and writes `docs/REPO-MODEL.md`: what the project does,
where things live, how to run it, its shape, **which models have the largest
blast radius**, and which are untested. Orientation for a first change, not an
exhaustive audit.

Two things it will not do: read `profiles.yml` or any credentials file, and
import or execute DAG code — Airflow DAGs are parsed with `ast`, never run.
Without a manifest it falls back to a shallow file scan and says so rather than
presenting estimates as lineage.

## Installing

Today de-harness ships its **conventions layer**. There are no skills or
commands yet.

### Claude Code

```
/plugin marketplace add jtteotn9/de-harness
/plugin install de-harness
```

### Codex, Cursor, and other AGENTS.md tools

Run the installer against your data engineering repository:

```bash
scripts/install-into-repo.sh ~/work/your-de-repo
```

It writes `AGENTS.md` — read by Codex, Cursor, Copilot, Gemini CLI, Zed and
[~20 other tools](https://agents.md) — plus namespaced `de-harness-*.mdc` rules
under `.cursor/rules/` that scope the SQL conventions to `*.sql`/`schema.yml`
and the orchestration conventions to `dags/`.

Re-run it to pick up updated conventions. It is non-destructive: an `AGENTS.md`
you already have is preserved, and only the de-harness block between markers is
rewritten.

## Guardrails (Claude Code)

Installing the plugin activates `hooks/guard-data-ops.sh`, which refuses
destructive operations against production data before they run:

| Refused | |
|---|---|
| `DROP` / `TRUNCATE` / `DELETE` with no `WHERE` | only when a database client is actually invoked |
| `bq rm` | deletes a table or dataset outright |
| `airflow dags backfill`, `airflow tasks clear` | reprocessing is a reviewed operation |
| `dbt run/build --full-refresh` | unless the target is explicitly non-production |

It is deliberately narrow. Searching or reading SQL is not executing it, so
`grep -r "DROP TABLE" migrations/` and `cat drop_legacy.sql` run normally — a
guard that blocks ordinary work gets switched off, and `tests/test-hooks.sh`
treats a false positive as a failure.

When a block is wrong, a human can add an `allow-command <glob>` line to
`.de-harness/guard-overrides.conf` in the target repo. The guard refuses shell
edits to that file, so every override reflects a human decision. Reading it is
always allowed.

### What does not port

The conventions layer ports at full fidelity. The planned **guardrail hooks**
(blocking destructive SQL, unattended production backfills, secrets reaching a
commit) rely on Claude Code's hook API and have **no equivalent in Codex or
Cursor** — they will be Claude Code only. Cursor and Codex users get the
conventions, not the enforcement.

## Development

No build step and no dependencies — the repo is Markdown and JSON, checked by
Bash and the Python 3 standard library. Run the gate before every commit:

```bash
bash tests/run-all.sh
```

It validates the plugin manifests, any skill/agent frontmatter, the DE
convention invariants in `base/CLAUDE.base.md`, that relative Markdown links
resolve, and that the generated `dist/` bundle is in sync with its source.
Checks for layers that don't exist yet report "none yet" instead of failing, so
the gate stays green as the harness grows.

`base/CLAUDE.base.md` is the single source of truth for the conventions.
Everything under `dist/` is generated from it by `scripts/build-agent-rules.sh`
and must never be hand-edited — the gate regenerates and diffs, so a manual edit
fails.

Work on a branch and open a pull request; nothing here auto-merges. Commit under
your own git identity with a clear message and **no AI co-author trailer** — a
rule `tests/run-all.sh` asserts is still documented in `base/CLAUDE.base.md`.
