#!/usr/bin/env bash
# test-agent-rules.sh — the generated cross-tool bundle under dist/.
#
# The load-bearing check is drift: dist/ must be exactly what the generator
# produces from base/CLAUDE.base.md right now. Without it the conventions
# silently fork into three divergent copies.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1"; FAIL=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "-- dist/ is in sync with base/CLAUDE.base.md (drift check)"
if bash "$ROOT/scripts/build-agent-rules.sh" "$TMP/dist" >/dev/null 2>&1; then
  if diff -r "$ROOT/dist" "$TMP/dist" >/dev/null 2>&1; then
    ok "dist/ matches generator output"
  else
    bad "dist/ is stale — run scripts/build-agent-rules.sh and commit the result"
    diff -r "$ROOT/dist" "$TMP/dist" | head -20
  fi
else
  bad "scripts/build-agent-rules.sh failed to run"
fi

echo "-- every convention reaches AGENTS.md, and exactly one .mdc"
python3 - "$ROOT" <<'PY' || FAIL=1
import glob, re, sys
root = sys.argv[1]; bad = 0
heads = [l.rstrip('\n') for l in open(f'{root}/base/CLAUDE.base.md') if l.startswith('## ')]
agents = open(f'{root}/dist/AGENTS.md').read()
mdcs = {f: open(f).read() for f in sorted(glob.glob(f'{root}/dist/.cursor/rules/*.mdc'))}
for h in heads:
    if h not in agents:
        print(f'   AGENTS.md is missing: {h}'); bad = 1
    n = sum(1 for t in mdcs.values() if h in t)
    if n == 0:
        print(f'   no .mdc carries: {h}'); bad = 1
    elif n > 1:
        print(f'   duplicated across {n} .mdc files: {h}'); bad = 1
if not bad:
    print(f'   all {len(heads)} conventions present, each in exactly one .mdc')
sys.exit(bad)
PY

echo "-- .mdc frontmatter is valid for Cursor"
python3 - "$ROOT" <<'PY' || FAIL=1
import glob, json, re, sys
root = sys.argv[1]; bad = 0
for f in sorted(glob.glob(f'{root}/dist/.cursor/rules/*.mdc')):
    name = f.split('/')[-1]
    t = open(f).read()
    m = re.match(r'^---\n(.*?)\n---\n', t, re.S)
    if not m:
        print(f'   {name}: no frontmatter'); bad = 1; continue
    fm = dict(re.findall(r'^(\w+):\s*(.*)$', m.group(1), re.M))
    if not fm.get('description'):
        print(f'   {name}: missing description'); bad = 1
    if fm.get('alwaysApply') not in ('true', 'false'):
        print(f'   {name}: alwaysApply must be true/false'); bad = 1
    if fm.get('alwaysApply') == 'false':
        try:
            globs = json.loads(fm.get('globs', ''))
            assert isinstance(globs, list) and globs
        except Exception:
            print(f'   {name}: scoped rule needs a non-empty globs list'); bad = 1
    if not name.startswith('de-harness-'):
        print(f'   {name}: must be namespaced de-harness-* to avoid collisions'); bad = 1
if not bad:
    print('   frontmatter valid and namespaced')
sys.exit(bad)
PY

echo "-- legacy .cursorrules is never emitted (ignored in Cursor Agent mode)"
if find "$ROOT/dist" -name '.cursorrules' | grep -q .; then
  bad "dist/ contains a .cursorrules"
else
  ok "no .cursorrules emitted"
fi

echo "-- generated files are marked do-not-edit"
MISSING=0
for f in "$ROOT"/dist/AGENTS.md "$ROOT"/dist/.cursor/rules/*.mdc; do
  grep -q 'do not edit by hand' "$f" || { echo "   ${f#"$ROOT"/} lacks the generated marker"; MISSING=1; }
done
[ "$MISSING" = 0 ] && ok "all generated files carry a do-not-edit marker" || bad "a generated file lacks its marker"

echo "-- installer: fresh repo, re-run, and an existing AGENTS.md"
REPO="$TMP/repo"; mkdir -p "$REPO"
bash "$ROOT/scripts/install-into-repo.sh" "$REPO" >/dev/null 2>&1 \
  && ok "installs into an empty repo" || bad "install failed on an empty repo"
[ -f "$REPO/AGENTS.md" ] && [ -f "$REPO/.cursor/rules/de-harness-base.mdc" ] \
  && ok "wrote AGENTS.md and namespaced Cursor rules" || bad "expected files missing after install"

cp "$REPO/AGENTS.md" "$TMP/first"
bash "$ROOT/scripts/install-into-repo.sh" "$REPO" >/dev/null 2>&1
diff -q "$TMP/first" "$REPO/AGENTS.md" >/dev/null \
  && ok "re-running is idempotent" || bad "re-running changed AGENTS.md"

REPO2="$TMP/repo2"; mkdir -p "$REPO2"
printf '# Our own agent rules\n\nAlways run make check.\n' > "$REPO2/AGENTS.md"
bash "$ROOT/scripts/install-into-repo.sh" "$REPO2" >/dev/null 2>&1
grep -q 'Always run make check' "$REPO2/AGENTS.md" \
  && ok "preserves a repo's existing AGENTS.md content" || bad "clobbered existing AGENTS.md"
grep -q 'Idempotency by default' "$REPO2/AGENTS.md" \
  && ok "appends de-harness conventions alongside it" || bad "did not append conventions"

# Update an already-installed repo: block replaced, repo content still intact.
bash "$ROOT/scripts/install-into-repo.sh" "$REPO2" >/dev/null 2>&1
[ "$(grep -c 'BEGIN de-harness conventions' "$REPO2/AGENTS.md")" = 1 ] \
  && ok "update replaces the block rather than stacking duplicates" || bad "duplicate de-harness blocks after re-run"
grep -q 'Always run make check' "$REPO2/AGENTS.md" \
  && ok "repo content survives an update" || bad "update destroyed repo content"

[ "$FAIL" -eq 0 ] && echo "agent-rules suite: PASS" || echo "agent-rules suite: FAIL"
exit "$FAIL"
