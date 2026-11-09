#!/usr/bin/env bash
# Recette pour le runner GitHub Actions de claude-bridge (2 cœurs, ~7 Go de RAM, réseau ouvert, <= 300 min).
# Le runner ne passe aucun argument et lance le script sous `env -i` : les réglages sont des variables placées EN TÊTE du
# script envoyé, par ex.  { printf 'MODE=tests\n'; cat comfyui-runner.sh; } > /tmp/job.sh
#
#   MODE=info      (défaut) matériel, versions, accès réseau : ne télécharge rien, ne clone rien
#   MODE=tests     tests-unit + tests/execution COMPLETS (COMFY_ALL_EXEC=1 : les 5 tests « RAM pressure » inclus)
#   MODE=generate  télécharge UN checkpoint .safetensors, l'insère dans le graphe txt2img, exécute sur CPU, rend l'image
#
# Réglages : FORK BRANCH MEDIA(0|1)  — generate : MODEL_URL (https, .safetensors) MODEL_SHA256 (obligatoire) PROMPT NEGATIVE
#            SIZE(256) STEPS(8) WORKFLOW_TIMEOUT(3600) MAX_MODEL_BYTES(6000000000)
# Sorties : $BRIDGE_WS/out/ (journaux, résumé, image). Aucun secret requis ni utilisé. Aucun modèle n'est choisi ici.
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}" HOME="${HOME:-/tmp}" LC_ALL=C.UTF-8
: "${MODE:=info}" "${FORK:=https://github.com/Metba09/ComfyUI.git}" "${BRANCH:=sandbox-hermetic}" "${MEDIA:=0}"
: "${SIZE:=256}" "${STEPS:=8}" "${WORKFLOW_TIMEOUT:=3600}" "${MAX_MODEL_BYTES:=6000000000}"
: "${PROMPT:=a lighthouse on a cliff at sunset, detailed}" "${NEGATIVE:=blurry, low quality}"
OUT="${BRIDGE_WS:-$PWD}/out"; W=/tmp/comfy-job
mkdir -p "$OUT" "$W"
say() { printf '[runner] %s\n' "$*"; }
die() { printf '[runner] ERREUR : %s\n' "$*" >&2; exit 2; }

case "$MODE" in info|tests|generate) ;; *) die "MODE inconnu : $MODE" ;; esac

if [ "$MODE" = info ]; then
  { say "cœurs : $(nproc)"; free -m | sed -n 1,2p; df -h /tmp | tail -1; python3 --version
    for u in https://pypi.org/simple/pip/ https://github.com; do
      printf '%s -> HTTP %s\n' "$u" "$(curl -s -o /dev/null -m 15 -w '%{http_code}' "$u" || echo échec)"; done
  } | tee "$OUT/info.txt"
  exit 0
fi

# --- contrôles d'entrée de generate, AVANT tout téléchargement lourd ---
if [ "$MODE" = generate ]; then
  [ -n "${MODEL_URL:-}" ] || die "MODEL_URL est requis (aucun modèle par défaut : on n'en invente pas)"
  case "$MODEL_URL" in https://*) ;; *) die "MODEL_URL doit être en https://" ;; esac
  MODEL_FILE="$(basename "${MODEL_URL%%[?#]*}")"
  case "$MODEL_FILE" in *.safetensors) ;; *) die "seuls les .safetensors sont acceptés (pas de pickle/.ckpt)" ;; esac
  case "$MODEL_FILE" in *[!A-Za-z0-9._-]*) die "nom de fichier suspect : $MODEL_FILE" ;; esac
  printf '%s' "${MODEL_SHA256:-}" | grep -Eq '^[0-9a-fA-F]{64}$' || die "MODEL_SHA256 (64 hex) est obligatoire"
  for v in SIZE STEPS WORKFLOW_TIMEOUT MAX_MODEL_BYTES; do
    printf '%s' "${!v}" | grep -Eq '^[0-9]+$' || die "$v doit être un entier"; done
fi

# --- dépôt + Python 3.13 (le runner a 3.12) + installation du bundle ---
rm -rf "$W/src"
git clone --depth 1 -b "$BRANCH" "$FORK" "$W/src" 2>&1 | tail -2
python3 -m venv "$W/uvenv" && "$W/uvenv/bin/pip" install -q uv
PY313="$("$W/uvenv/bin/uv" python install 3.13 >/dev/null 2>&1 && "$W/uvenv/bin/uv" python find 3.13)"
say "Python : $PY313"
cd "$W/src"
PYTHON="$PY313" MEDIA="$MEDIA" bash setup.sh 2>&1 | tee "$OUT/setup.log" | tail -5
. scripts/sandbox/env.sh

if [ "$MODE" = tests ]; then
  rc=0
  export COMFY_ALL_EXEC=1
  bash scripts/sandbox/test.sh unit 2>&1 | tee "$OUT/tests-unit.log" | tail -3 || rc=1
  bash scripts/sandbox/test.sh exec 2>&1 | tee "$OUT/tests-exec.log" | tail -3 || rc=1
  { say "tests-unit : $(tail -1 "$OUT/tests-unit.log")"; say "tests-exec : $(tail -1 "$OUT/tests-exec.log")"; } | tee "$OUT/summary.txt"
  exit "$rc"
fi

# --- generate ---
mkdir -p models/checkpoints
say "téléchargement de $MODEL_FILE (plafond ${MAX_MODEL_BYTES} octets)"
curl -fL --retry 3 -m 3000 --max-filesize "$MAX_MODEL_BYTES" -o "models/checkpoints/$MODEL_FILE" "$MODEL_URL"
printf '%s  %s\n' "$(printf '%s' "$MODEL_SHA256" | tr A-F a-f)" "models/checkpoints/$MODEL_FILE" | sha256sum -c - \
  || { rm -f "models/checkpoints/$MODEL_FILE"; die "empreinte du modèle différente : fichier supprimé"; }
export MODEL_FILE PROMPT NEGATIVE SIZE STEPS
python - <<'PY'
import json, os
g = json.load(open("sandbox/samples/model/txt2img_checkpoint.json"))
for n in g.values():
    for k, v in n.get("inputs", {}).items():
        if isinstance(v, str):
            n["inputs"][k] = (v.replace("__CKPT__", os.environ["MODEL_FILE"]).replace("__PROMPT__", os.environ["PROMPT"])
                              .replace("__NEGATIVE__", os.environ["NEGATIVE"]))
        elif k in ("width", "height"):
            n["inputs"][k] = int(os.environ["SIZE"])
        elif k == "steps":
            n["inputs"][k] = int(os.environ["STEPS"])
json.dump(g, open("/tmp/comfy-job/graph.json", "w"))
PY
python scripts/sandbox/smoke.py --workflow "$W/graph.json" --keep-output "$OUT/images" --workflow-timeout "$WORKFLOW_TIMEOUT" 2>&1 | tee "$OUT/generate.log"
say "images : $(find "$OUT/images" -type f -name '*.png' | wc -l) fichier(s) dans out/images"
