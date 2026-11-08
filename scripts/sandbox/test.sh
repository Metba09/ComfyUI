#!/usr/bin/env bash
# Tests avec les bons réglages du sandbox. Usage : test.sh [unit|fast|exec|all] [arguments pytest...]
#   unit : tests-unit complet (~5 min)           fast : sous-ensemble rapide (~1,5 min)
#   exec : tests/execution (~3 min, serveur local) all  : unit + exec
# NETOFF=1 : exécute dans un espace réseau coupé (preuve hors-ligne).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/env.sh"
need_venv

mode="${1:-unit}"
[ $# -gt 0 ] && shift

PYTEST=(python -m pytest -q -o addopts="" -p no:cacheprovider -p sandbox.pytest_force_cpu -W ignore)
FAST_DIRS=(tests-unit/comfy_test tests-unit/comfy_api_test tests-unit/execution_test tests-unit/folder_paths_test
           tests-unit/nodes_test tests-unit/utils tests-unit/server_test tests-unit/prompt_server_test tests-unit/server
           tests-unit/comfy_extras_test tests-unit/comfy_quant tests-unit/security_test tests-unit/governance_test)

# Sortie des tests d'exécution : dossier neuf à chaque fois (les compteurs de fichiers dépendent de l'état précédent).
OUT="$(mktemp -d /tmp/comfy-test-out.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT

run_exec() {
  # Exclus : les variantes qui utilisent le cache « RAM pressure » (défaut de ComfyUI). Il exige au moins 2 Go de RAM
  # libre ; le sandbox (~6 Go au total, souvent < 2,5 Go libres) fait évincer le cache et les assertions « déjà en cache »
  # échouent. Limite de l'environnement, pas du code (voir CLAUDE.md, « Session Chat »).
  run_cmd "${PYTEST[@]}" tests/execution --output_dir "$OUT" --skip-timing-checks \
    -k "not server3 and not test_a_cached_rerun_keeps_the_preview" "$@"
}

case "$mode" in
  unit) run_cmd "${PYTEST[@]}" tests-unit "$@" ;;
  fast) run_cmd "${PYTEST[@]}" "${FAST_DIRS[@]}" "$@" ;;
  exec) run_exec "$@" ;;
  all)  run_cmd "${PYTEST[@]}" tests-unit "$@"; run_exec "$@" ;;
  *) die "mode inconnu '$mode' (unit|fast|exec|all)" ;;
esac
