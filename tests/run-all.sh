#!/usr/bin/env bash
# run-all.sh — de-harness's own gate. Run before every commit to this repo.
#
# de-harness is Markdown + JSON (+ Bash/Python once later layers land), so this
# is the whole verification story: there is no install/lint/typecheck/build step.
# Checks degrade cleanly for layers that aren't built yet — a missing skills/ or
# scripts/ directory is reported as "none yet", not as a failure.
set -u
HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
HAVE_PY=1; command -v python3 >/dev/null 2>&1 || HAVE_PY=0
shopt -s nullglob

echo "### JSON manifests valid"
if [ "$HAVE_PY" = 1 ]; then
  for f in "$HARNESS"/.claude-plugin/*.json; do
    if python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
      echo "ok   ${f#"$HARNESS"/}"
    else
      echo "FAIL ${f#"$HARNESS"/} is not valid JSON"; FAIL=1
    fi
  done
  for req in plugin.json marketplace.json; do
    [ -f "$HARNESS/.claude-plugin/$req" ] || { echo "FAIL .claude-plugin/$req is missing"; FAIL=1; }
  done
else
  echo "SKIP python3 unavailable (JSON, frontmatter and manifest checks skipped)"
fi

echo
echo "### Plugin manifest agrees with marketplace entry"
if [ "$HAVE_PY" = 1 ] && [ -f "$HARNESS/.claude-plugin/marketplace.json" ]; then
  if python3 - "$HARNESS" <<'PY'
import json, sys
root = sys.argv[1]
plugin = json.load(open(f"{root}/.claude-plugin/plugin.json"))
market = json.load(open(f"{root}/.claude-plugin/marketplace.json"))
entries = [p for p in market.get("plugins", []) if p.get("name") == plugin.get("name")]
if not entries:
    print(f"   marketplace.json has no entry named {plugin.get('name')!r}"); sys.exit(1)
sys.exit(0)
PY
  then echo "ok   marketplace.json lists the plugin declared in plugin.json"
  else echo "FAIL marketplace.json and plugin.json disagree on the plugin name"; FAIL=1; fi
fi

echo
echo "### Skill & agent frontmatter"
if [ "$HAVE_PY" = 1 ]; then
python3 - "$HARNESS" <<'PY' || FAIL=1
import re, glob, sys
root = sys.argv[1]; bad = 0
files = sorted(glob.glob(f'{root}/skills/*/SKILL.md') + glob.glob(f'{root}/agents/*.md'))
if not files:
    print('ok   none yet (skills/ and agents/ are planned layers)')
for f in files:
    t = open(f).read()
    m = re.match(r'^---\n(.*?)\n---\n', t, re.S)
    rel = f[len(root)+1:]
    if not m or 'description:' not in m.group(1):
        print(f'FAIL {rel} — missing frontmatter or description'); bad = 1
    else:
        print(f'ok   {rel}')
sys.exit(bad)
PY
fi

echo
echo "### Convention invariants (DE rules baked into base/CLAUDE.base.md)"
BASE="$HARNESS/base/CLAUDE.base.md"
if [ ! -f "$BASE" ]; then
  echo "FAIL base/CLAUDE.base.md is missing — it is the whole conventions layer"; FAIL=1
else
  # Each heading is a load-bearing DE convention; losing one silently would gut
  # the harness's reason to exist.
  while IFS='|' read -r pattern label; do
    if grep -q "$pattern" "$BASE"; then echo "ok   base states: $label"
    else echo "FAIL base lost its rule on: $label"; FAIL=1; fi
  done <<'RULES'
^## Idempotency by default|idempotency
^## Schema contracts at every boundary|schema contracts
^## Data quality checks are part of the gate|data quality in the gate
^## No destructive SQL without explicit human confirmation|destructive SQL confirmation
^## Backfills are a first-class, reviewed operation|reviewed backfills
^## PII and sensitive data|PII handling
^## No AI co-author trailers|no AI co-author trailers
RULES
  if grep -qi 'user-triggered only' "$BASE"; then echo "ok   base gates push/PR to explicit user input"
  else echo "FAIL base missing the push/PR user-triggered rule"; FAIL=1; fi
  if grep -qi 'never commit secrets' "$BASE"; then echo "ok   base forbids committing secrets"
  else echo "FAIL base missing the no-secrets rule"; FAIL=1; fi
fi
if grep -rIlq 'trailer the harness configures\|co-author trailer to append' \
     "$HARNESS/base" "$HARNESS/skills" "$HARNESS/agents" 2>/dev/null; then
  echo "FAIL a rule instructs ADDING a co-author trailer"; FAIL=1
else
  echo "ok   no rule instructs adding a co-author trailer"
fi

echo
echo "### Docs honesty (README must not claim unbuilt layers)"
if [ "$HAVE_PY" = 1 ]; then
python3 - "$HARNESS" <<'PY' || FAIL=1
import glob, sys
root = sys.argv[1]
readme = open(f'{root}/README.md').read()
built = bool(glob.glob(f'{root}/skills/*/SKILL.md'))
claims_scaffolding = 'early scaffolding' in readme.lower()
if built and claims_scaffolding:
    print('FAIL skills/ now exist but README still says "early scaffolding" — update it')
    sys.exit(1)
if not built and not claims_scaffolding:
    print('FAIL no skills/ exist but README dropped its "early scaffolding" status')
    sys.exit(1)
print(f'ok   README status matches reality (skills built: {built})')
PY
fi

echo
echo "### Relative links in Markdown resolve"
if [ "$HAVE_PY" = 1 ]; then
python3 - "$HARNESS" <<'PY' || FAIL=1
import glob, os, re, sys
root = sys.argv[1]; bad = 0
files = sorted(glob.glob(f'{root}/*.md') + glob.glob(f'{root}/**/*.md', recursive=True))
for f in sorted(set(files)):
    if '/.harness/' in f or '/.claude/' in f:
        continue
    for link in re.findall(r'\]\(([^)]+)\)', open(f).read()):
        if link.startswith(('http://', 'https://', '#', 'mailto:')):
            continue
        target = os.path.normpath(os.path.join(os.path.dirname(f), link.split('#')[0]))
        if not os.path.exists(target):
            print(f'FAIL {f[len(root)+1:]} -> {link} (missing)'); bad = 1
if not bad:
    print('ok   all relative Markdown links resolve')
sys.exit(bad)
PY
fi

echo
echo "### Shell syntax (bash -n)"
SH=("$HARNESS"/scripts/*.sh "$HARNESS"/hooks/*.sh "$HARNESS"/tests/*.sh)
if [ ${#SH[@]} -eq 0 ]; then
  echo "ok   no shell scripts yet"
else
  for f in "${SH[@]}"; do
    if bash -n "$f" 2>/dev/null; then echo "ok   ${f#"$HARNESS"/}"
    else echo "FAIL ${f#"$HARNESS"/} has syntax errors"; FAIL=1; fi
  done
fi

echo
echo "### Python syntax (py_compile)"
PY_FILES=("$HARNESS"/scripts/*.py)
if [ ${#PY_FILES[@]} -eq 0 ]; then
  echo "ok   no Python scripts yet"
elif [ "$HAVE_PY" = 1 ]; then
  for f in "${PY_FILES[@]}"; do
    if python3 -m py_compile "$f" 2>/dev/null; then echo "ok   ${f#"$HARNESS"/}"
    else echo "FAIL ${f#"$HARNESS"/} has syntax errors"; FAIL=1; fi
  done
else
  echo "SKIP python3 not available"
fi

echo
echo "### Cross-tool bundle (AGENTS.md + Cursor rules)"
if [ -f "$HARNESS/tests/test-agent-rules.sh" ]; then
  bash "$HARNESS/tests/test-agent-rules.sh" || FAIL=1
else
  echo "ok   none yet"
fi

echo
if [ "$FAIL" -eq 0 ]; then echo "ALL SUITES GREEN"; else echo "SUITES FAILED"; fi
exit "$FAIL"
