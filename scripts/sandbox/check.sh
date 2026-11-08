#!/usr/bin/env bash
# À lancer à la main avant de conclure un travail : remplace tout hook automatique.
#   lint -> tests rapides -> smoke test (serveur local + workflows sans modèle)
#   NETOFF=1 bash scripts/sandbox/check.sh   : le tout dans un espace réseau coupé
#   FULL=1   : tests-unit complets au lieu du sous-ensemble rapide
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/env.sh"
need_venv
t0=$(date +%s)
bash "$HERE/lint.sh"
bash "$HERE/test.sh" "$([ "${FULL:-0}" = "1" ] && echo unit || echo fast)"
run_cmd python "$HERE/smoke.py"
say "check : OK en $(( $(date +%s) - t0 )) s${NETOFF:+ (réseau coupé)}"
