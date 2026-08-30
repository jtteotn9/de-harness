---
name: investigate
description: Build a first-task orientation for a data engineering repository — what it does, where things live, how to run it, what is fragile, and what a safe first change looks like. Use when arriving at an unfamiliar dbt/Airflow/Dagster repo, when asked to "investigate this repo", "explain this project", "what does this pipeline do", or before making a first change to a pipeline you did not write.
argument-hint: "[output path; default: docs/REPO-MODEL.md]"
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
---

You are answering one question for someone who has never seen this repository:

> **"I know nothing about this project. Tell me what I need in order to do my
> first task safely."**

That is the whole scope. This is orientation for a first change, **not** an
exhaustive audit. A fact earns its place only if it would change how someone
makes their first edit. Resist the urge to inventory everything.

## Procedure

1. **Collect the facts.** Prefer the vendored copy so this works without the
   plugin:

   ```
   S=.de-harness/scan-de-repo.py; [ -f "$S" ] || S="${CLAUDE_PLUGIN_ROOT}/scripts/scan-de-repo.py"
   python3 "$S" .
   ```

   Read `de.confidence` first and let it set your tone:

   - `high` — a dbt `manifest.json` was parsed. Lineage, tests and sources are
     authoritative. Report them plainly.
   - `low` — no manifest, or orchestration only. Counts come from a shallow
     file scan. Say so: "37 model files (no manifest — run `dbt parse` for
     accurate lineage)". Never present a shallow count as a lineage fact.
   - `none` — no DE markers. Say that plainly and stop; do not pad the report
     with generic repository description.

   `de.dbt.manifest_generated_at` is when the manifest was built, not now. If
   it is more than a day or two old, say so — it reflects the last `dbt parse`,
   not the working tree.

2. **Read what the facts point at.** The scan tells you where to look; it does
   not tell you what the pipeline is *for*. Read the README, any
   `CONTRIBUTING`/`AGENTS.md`/`CLAUDE.md`, and two or three of the models named
   in `de.high_fanout` — the ones most depended upon are the ones a newcomer is
   most likely to break.

   **Never read `profiles.yml`** or any credentials file. If you need to
   describe how to run things locally, take the target names from
   `dbt_project.yml` and the README, or say that a human should supply them.

   **Never import or execute** DAG or model code. Read it.

3. **Write the model** to `$ARGUMENTS` (default `docs/REPO-MODEL.md`). Lead
   with a provenance line so a stale report is obvious in review:

   ```markdown
   # Repo model — <project>
   _Generated from commit <sha> · dbt manifest <age> · de-harness <version>_
   ```

   Then, in this order — each section is at most a short paragraph or a small
   list:

   - **What this does** — the business purpose, in two lines. From the README
     and model descriptions, not invented.
   - **Stack** — dbt version/adapter, orchestrator, warehouse.
   - **Where things live** — the directories that matter.
   - **Running it locally** — the dev target and how to run one model plus its
     tests. If you could not determine this, say so; do not guess a command.
   - **Shape** — sources → models → exposures, depth, materialization mix.
     Call out incremental models explicitly: they are where idempotency bugs
     live.
   - **Before you change anything** — the high-fanout models and what they
     feed. This is the section that prevents the first mistake.
   - **Fragile** — untested models, sources without freshness. Name them.
   - **Conventions in force** — what the repo already asks of contributors.

4. **Report** three or four lines to the human: where the file was written, the
   confidence level, and the single most important thing they should know
   before touching this repo. Do not paste the whole document back.

## Honesty rules

These matter more than completeness:

- Distinguish what you **measured** from what you **inferred**. "12 models have
  no test" is measured; "the staging layer looks well maintained" is a
  judgement — mark it as one or leave it out.
- If the manifest is absent or stale, the lineage numbers are estimates. Say it
  once, plainly, near the top.
- If you could not determine how to run the project locally, that is a finding
  worth reporting, not a gap to paper over with a plausible-looking command.
