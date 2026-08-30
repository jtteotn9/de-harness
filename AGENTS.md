# AGENTS.md — working on de-harness itself

This file is for agents contributing **to this repository**. It is hand-written.

If you are looking for the data engineering conventions de-harness *ships*, they
are generated into [`dist/AGENTS.md`](dist/AGENTS.md) from
[`base/CLAUDE.base.md`](base/CLAUDE.base.md). Install them into a data
engineering repo with `scripts/install-into-repo.sh <target-repo>`.

## What this repo is

An AI-agent engineering harness for data engineering repositories. It is adopted
as a team standard across many DE repos, so everything here must read as generic
and stack-level — never tied to one pipeline, warehouse, or company.

Status: early scaffolding. Only the conventions layer exists. Detection, skills,
agents, and guardrail hooks are planned but not built. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for built vs. planned, and never
describe the repo as if the later layers already work.

## Gate

```bash
bash tests/run-all.sh
```

Green before every commit. No build step, no dependencies — Markdown and JSON,
checked by Bash and the Python 3 standard library.

## The one rule that bites

`base/CLAUDE.base.md` is the **single source of truth** for the conventions.
Everything under `dist/` is generated from it:

```bash
scripts/build-agent-rules.sh    # regenerate, then commit the result
```

Never hand-edit a file under `dist/` — the gate regenerates and diffs, so a
manual edit fails. Change the base file and regenerate instead.

## Conventions

Work on a branch and open a pull request; nothing here auto-merges. Commit under
your own git identity with a clear, human-style message and **no AI co-author
trailer** — no `Co-Authored-By: Claude`/`Codex`/`Copilot`, no "Generated with"
lines.
