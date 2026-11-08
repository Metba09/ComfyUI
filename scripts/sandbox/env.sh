# Sourcé par les autres scripts de scripts/sandbox/. Ne lance rien lui-même.
# shellcheck shell=bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
VENV="${COMFY_VENV:-$ROOT/.venv}"

# .env local (copie de .env.example) : surcharge les valeurs par défaut ci-dessous.
if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/.env"
  set +a
fi

# Les tests lancent `python main.py` via le PATH : le venv doit passer devant.
export PATH="$VENV/bin:$PATH"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

# Aucune bibliothèque ne doit tenter de joindre Hugging Face.
export HF_HUB_OFFLINE="${HF_HUB_OFFLINE:-1}"
export TRANSFORMERS_OFFLINE="${TRANSFORMERS_OFFLINE:-1}"
export HF_DATASETS_OFFLINE="${HF_DATASETS_OFFLINE:-1}"
export DO_NOT_TRACK=1

say() { printf '%s\n' "$*"; }
die() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }

need_venv() {
  [ -x "$VENV/bin/python" ] || die "environnement absent : lancer 'make setup' d'abord"
}

# run_cmd cmd args... : exécute la commande, dans un espace réseau coupé si NETOFF=1.
run_cmd() {
  if [ "${NETOFF:-0}" = "1" ]; then
    python "$ROOT/scripts/sandbox/netoff.py" -- "$@"
  else
    "$@"
  fi
}
