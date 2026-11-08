#!/usr/bin/env bash
# Vérifications statiques, mêmes règles que la CI amont, plus quelques garde-fous du bundle. Aucun réseau.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/env.sh"
need_venv
fail=0

say "lint : ruff check . (règles de pyproject.toml, identiques à la CI)"
ruff check . || fail=1

say "lint : fins de ligne Windows (CRLF) dans les fichiers modifiés (règle de la CI, hors .ci)"
base="${BASE:-HEAD}"
changed="$( { git diff --name-only "$base" -- ':!.ci' 2>/dev/null; git ls-files -o --exclude-standard -- ':!.ci'; } | sort -u)"
for f in $changed; do
  if [ -f "$f" ] && file "$f" | grep -q text && grep -qU $'\r$' "$f"; then
    say "  CRLF détecté : $f"; fail=1
  fi
done

say "lint : syntaxe des scripts shell et JSON d'exemple"
for f in setup.sh scripts/sandbox/*.sh; do bash -n "$f" || fail=1; done
for f in sandbox/samples/workflows/*.json default_workflow.json; do python -m json.tool "$f" >/dev/null || { say "  JSON invalide : $f"; fail=1; }; done

say "lint : intégrité du wheelhouse (empreintes)"
if compgen -G "vendor/wheels/*.whl" >/dev/null; then python scripts/sandbox/vendor.py --verify || fail=1; else say "  wheelhouse absent (ignoré)"; fi

[ "$fail" = "0" ] && say "lint : OK" || { say "lint : ÉCHEC"; exit 1; }
