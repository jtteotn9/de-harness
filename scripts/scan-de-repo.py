#!/usr/bin/env python3
"""scan-de-repo.py — deterministic facts about a data engineering repository.

Emits `de.KEY=VALUE` lines, the way detect-stack.sh emits `harness.*`. The
`investigate` skill turns these into a repo model; this script contributes no
judgment, only facts, so its output can be diffed against golden fixtures.

Two constraints shape the design:

1. NO YAML PARSER. de-harness is Python-3-stdlib-only, and there is no YAML
   module in the stdlib. dbt's target/manifest.json is therefore the preferred
   source: it is the authoritative model/source/test/lineage graph AND it is
   JSON. Without it we fall back to a deliberately shallow line scan and say so
   via de.confidence -- a thin scan must never read as authoritative.

2. NOTHING IS EXECUTED. Airflow DAGs are parsed with `ast`, never imported.
   Importing a DAG module runs top-level code, which in a DE repo may open
   warehouse connections.

Secrets: this script never reads profiles.yml. It reports the *profile name*
from dbt_project.yml (harmless) and nothing else, so warehouse credentials
cannot reach the output. tests/test-scan.sh guards that this stays true.

Usage: scan-de-repo.py [repo-root]        (default: .)
"""
import ast
import json
import os
import re
import sys

MAX_LISTED = 5  # keep emitted lists short and stable


def emit(key, value):
    print(f"de.{key}={value}")


# --------------------------------------------------------------- dbt: manifest
def read_manifest(root):
    """Return the parsed manifest and its path, or (None, None)."""
    for rel in ("target/manifest.json", "manifest.json"):
        path = os.path.join(root, rel)
        if os.path.isfile(path):
            try:
                with open(path, encoding="utf-8") as fh:
                    return json.load(fh), rel
            except (ValueError, OSError):
                return None, rel  # present but unreadable — caller degrades
    return None, None


def longest_depth(model_ids, parents):
    """Longest ancestor chain within the model graph. Cycle-safe."""
    memo, visiting = {}, set()

    def depth(node):
        if node in memo:
            return memo[node]
        if node in visiting:  # dbt forbids cycles, but never loop on bad input
            return 0
        visiting.add(node)
        best = 0
        for parent in parents.get(node, []):
            if parent in model_ids:
                best = max(best, 1 + depth(parent))
        visiting.discard(node)
        memo[node] = best
        return best

    return max((depth(m) for m in model_ids), default=0)


def scan_manifest(manifest, rel_path):
    nodes = manifest.get("nodes", {})
    sources = manifest.get("sources", {})
    exposures = manifest.get("exposures", {})
    parents = manifest.get("parent_map", {})
    children = manifest.get("child_map", {})
    meta = manifest.get("metadata", {})

    emit("dbt.manifest", rel_path)
    # generated_at, not an age in days: keeps output stable across runs so it
    # can be diffed. The skill turns it into "N days old" when reporting.
    emit("dbt.manifest_generated_at", meta.get("generated_at", ""))
    emit("dbt.schema_version", meta.get("dbt_schema_version", ""))
    emit("dbt.project", meta.get("project_name", ""))
    emit("dbt.adapter", meta.get("adapter_type", ""))

    models = {k: v for k, v in nodes.items() if v.get("resource_type") == "model"}
    tests = {k: v for k, v in nodes.items() if v.get("resource_type") == "test"}
    seeds = {k: v for k, v in nodes.items() if v.get("resource_type") == "seed"}
    snapshots = {k: v for k, v in nodes.items() if v.get("resource_type") == "snapshot"}

    emit("models", len(models))
    emit("tests", len(tests))
    emit("seeds", len(seeds))
    emit("snapshots", len(snapshots))
    emit("sources", len(sources))
    emit("exposures", len(exposures))

    # Materialization mix — the idempotency-relevant fact.
    mats = {}
    for node in models.values():
        mat = (node.get("config") or {}).get("materialized", "view")
        mats[mat] = mats.get(mat, 0) + 1
    emit("materializations", ",".join(f"{k}:{mats[k]}" for k in sorted(mats)))

    # Models with no test attached anywhere in their test's dependencies.
    tested = set()
    for test in tests.values():
        for dep in (test.get("depends_on") or {}).get("nodes", []):
            tested.add(dep)
    untested = sorted(
        models[m].get("name", m) for m in models if m not in tested
    )
    emit("models_untested", len(untested))
    emit("models_untested_sample", ",".join(untested[:MAX_LISTED]))

    # Sources with no freshness block — a boundary-input risk.
    stale_risk = sorted(
        f"{v.get('source_name', '?')}.{v.get('name', '?')}"
        for v in sources.values()
        if not v.get("freshness")
    )
    emit("sources_without_freshness", len(stale_risk))
    emit("sources_without_freshness_sample", ",".join(stale_risk[:MAX_LISTED]))

    # Blast radius: models the most other things depend on.
    fanout = sorted(
        ((len([c for c in children.get(m, []) if c in models or c in exposures]),
          models[m].get("name", m)) for m in models),
        key=lambda pair: (-pair[0], pair[1]),
    )
    emit("high_fanout", ",".join(f"{name}:{n}" for n, name in fanout[:MAX_LISTED] if n > 0))
    emit("max_depth", longest_depth(set(models), parents))

    # Description coverage — how much of the repo documents itself.
    described = sum(1 for v in models.values() if (v.get("description") or "").strip())
    emit("models_described", described)

    # Which models feed something a human looks at.
    exposed = sorted(
        {nodes[d].get("name", d)
         for e in exposures.values()
         for d in (e.get("depends_on") or {}).get("nodes", [])
         if d in nodes}
    )
    emit("exposed_models", ",".join(exposed[:MAX_LISTED]))
    return True


# ------------------------------------------------------- dbt: shallow fallback
def scan_dbt_shallow(root, project_yml):
    """Line scan used when no manifest exists. Deliberately minimal."""
    emit("dbt.manifest", "")
    name = profile = ""
    try:
        with open(project_yml, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"^name:\s*['\"]?([\w-]+)", line)
                if m and not name:
                    name = m.group(1)
                m = re.match(r"^profile:\s*['\"]?([\w-]+)", line)
                if m and not profile:
                    profile = m.group(1)
    except OSError:
        pass
    emit("dbt.project", name)
    # The profile NAME only. profiles.yml itself is never read: it holds
    # warehouse credentials and has no place in this output.
    emit("dbt.profile", profile)

    sql = sorted(relpaths(root, "models", ".sql"))
    emit("models", len(sql))
    schemas = sorted(relpaths(root, "models", ".yml") + relpaths(root, "models", ".yaml"))
    emit("dbt.schema_files", len(schemas))
    emit("tests", len(sorted(relpaths(root, "tests", ".sql"))))


def relpaths(root, subdir, suffix):
    base = os.path.join(root, subdir)
    found = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for fn in sorted(filenames):
            if fn.endswith(suffix):
                found.append(os.path.relpath(os.path.join(dirpath, fn), root))
    return found


# ------------------------------------------------------------ orchestration
DAG_DIRS = ("dags", "airflow/dags", "orchestration/dags")


def scan_dags(root):
    """Find DAG ids and schedules by parsing, never importing."""
    files, dag_ids, schedules = [], [], []
    for rel in DAG_DIRS:
        base = os.path.join(root, rel)
        if os.path.isdir(base):
            files.extend(relpaths(root, rel, ".py"))
    files = sorted(set(files))
    if not files:
        return []

    for rel in files:
        try:
            with open(os.path.join(root, rel), encoding="utf-8") as fh:
                tree = ast.parse(fh.read(), filename=rel)
        except (SyntaxError, OSError, ValueError):
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            func = node.func
            fname = getattr(func, "id", None) or getattr(func, "attr", None)
            if fname not in ("DAG", "dag"):
                continue
            for kw in node.keywords:
                if kw.arg in ("dag_id",) and isinstance(kw.value, ast.Constant):
                    if isinstance(kw.value.value, str):
                        dag_ids.append(kw.value.value)
                if kw.arg in ("schedule", "schedule_interval") and isinstance(kw.value, ast.Constant):
                    if isinstance(kw.value.value, str):
                        schedules.append(kw.value.value)
    emit("dag_files", len(files))
    emit("dag_ids", ",".join(sorted(set(dag_ids))[:MAX_LISTED]))
    emit("dag_schedules", ",".join(sorted(set(schedules))[:MAX_LISTED]))
    return files


# ------------------------------------------------------------------- docs
def scan_docs(root):
    found = []
    for name in ("README.md", "CONTRIBUTING.md", "AGENTS.md", "CLAUDE.md"):
        if os.path.isfile(os.path.join(root, name)):
            found.append(name)
    docs_dir = os.path.join(root, "docs")
    if os.path.isdir(docs_dir):
        found.extend(sorted(
            os.path.relpath(os.path.join(docs_dir, f), root)
            for f in os.listdir(docs_dir) if f.endswith(".md")
        )[:MAX_LISTED])
    emit("docs", ",".join(found))


# ------------------------------------------------------------------- main
def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    if not os.path.isdir(root):
        sys.stderr.write(f"error: {root} is not a directory\n")
        return 2

    stack, confidence = [], "none"
    project_yml = os.path.join(root, "dbt_project.yml")

    if os.path.isfile(project_yml):
        stack.append("dbt")
        manifest, rel = read_manifest(root)
        if manifest:
            confidence = "high"
        else:
            confidence = "low"
    dag_files_present = any(os.path.isdir(os.path.join(root, d)) for d in DAG_DIRS)
    if dag_files_present:
        stack.append("airflow")
        if confidence == "none":
            confidence = "low"

    for marker, label in (("great_expectations.yml", "great_expectations"),
                          ("soda", "soda")):
        if os.path.exists(os.path.join(root, marker)):
            stack.append(label)

    emit("root", os.path.basename(root))
    emit("stack", ",".join(stack))
    emit("confidence", confidence)

    if "dbt" in stack:
        manifest, rel = read_manifest(root)
        if manifest:
            scan_manifest(manifest, rel)
        else:
            scan_dbt_shallow(root, project_yml)
    if dag_files_present:
        scan_dags(root)
    scan_docs(root)

    if confidence == "none":
        sys.stderr.write(
            "note: no data engineering markers found "
            "(no dbt_project.yml, no dags/) — nothing to report\n"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
