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
