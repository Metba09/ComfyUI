#!/usr/bin/env bash
# Installation idempotente, sans aucune saisie. Se relance sans risque : si rien n'a changé, elle ne fait rien.
#   bash scripts/sandbox/setup.sh            # équivalent de `make setup`
#   MEDIA=0 bash scripts/sandbox/setup.sh    # sans les templates médias (~530 Mo)
#   OFFLINE_STRICT=1 ...                     # échoue au lieu de contacter PyPI si le wheelhouse manque
# Réseau : uniquement PyPI, et seulement si vendor/wheels* est absent (re-téléchargement exact, empreintes vérifiées).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/env.sh"

MEDIA="${MEDIA:-1}"
PY="${PYTHON:-python3}"

[ -f vendor/requirements.lock.txt ] || die "vendor/requirements.lock.txt manquant : le bundle est incomplet"
want="$(tr -d '[:space:]' < vendor/PYTHON_VERSION)"
have="$("$PY" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
[ "$want" = "$have" ] || die "wheelhouse figé pour Python $want, ici Python $have. Relancer 'make vendor' avec ce Python (accès PyPI requis)."

groups="wheels wheels-cuda"
[ "$MEDIA" = "1" ] && groups="$groups wheels-media"

stamp="$( { cat vendor/requirements*.lock.txt vendor/PYTHON_VERSION; echo "MEDIA=$MEDIA"; } | sha256sum | cut -d' ' -f1)"

installed_ok() {
  [ -x "$VENV/bin/python" ] && [ "$(cat "$VENV/.sandbox-stamp" 2>/dev/null)" = "$stamp" ] \
    && "$VENV/bin/python" -c 'import torch, aiohttp, yaml, sqlalchemy, alembic, PIL, numpy, safetensors' >/dev/null 2>&1
}

if installed_ok; then
  say "setup : environnement déjà à jour ($VENV)"
else
  # 1. wheelhouse : présent, sinon re-téléchargement exact depuis les lockfiles.
  missing=0
  for d in $groups; do
    compgen -G "vendor/$d/*.whl" >/dev/null || missing=1
  done
  if [ "$missing" = "1" ]; then
    [ "${OFFLINE_STRICT:-0}" = "1" ] && die "wheelhouse absent et OFFLINE_STRICT=1"
    say "setup : wheelhouse absent, re-téléchargement exact depuis PyPI (empreintes vérifiées)"
    extra=""
    [ "$MEDIA" = "1" ] || extra="--no-media"
    "$PY" scripts/sandbox/vendor.py --fetch $extra
  fi
  # 2. intégrité
  "$PY" scripts/sandbox/vendor.py --verify

  # 3. venv neuf : jamais de mélange entre deux jeux de versions
  rm -rf "$VENV"
  "$PY" -m venv "$VENV"
  for d in $groups; do
    case "$d" in
      wheels) lock=requirements.lock.txt ;;
      wheels-cuda) lock=requirements.cuda.lock.txt ;;
      wheels-media) lock=requirements.media.lock.txt ;;
    esac
    say "setup : installation hors-ligne de $d"
    "$VENV/bin/pip" install --quiet --no-index --find-links "vendor/$d" --no-deps --require-hashes -r "vendor/$lock"
  done
  "$VENV/bin/python" -c 'import torch, aiohttp, yaml, sqlalchemy, alembic, PIL, numpy, safetensors' \
    || die "l'environnement installé ne s'importe pas"
  printf '%s' "$stamp" > "$VENV/.sandbox-stamp"
fi

[ -f .env ] || { cp .env.example .env; say "setup : .env créé depuis .env.example"; }
say "setup : OK  (python $("$VENV/bin/python" -c 'import sys; print(sys.version.split()[0])'), torch $("$VENV/bin/python" -c 'import torch; print(torch.__version__)'))"
