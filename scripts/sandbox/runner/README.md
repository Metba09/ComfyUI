# Recette pour le runner claude-bridge

`comfyui-runner.sh` exécute ComfyUI sur un runner GitHub Actions (2 cœurs, ~7 Go de RAM, réseau ouvert), là où le sandbox Chat
est trop limité. Il ne contient aucun secret et ne choisit aucun modèle.

| MODE | Effet |
|---|---|
| `info` (défaut) | matériel, versions, accès à PyPI/GitHub ; rien n'est cloné |
| `tests` | tests-unit + tests/execution complets (`COMFY_ALL_EXEC=1`, les 5 tests « RAM pressure » inclus) |
| `generate` | télécharge un `.safetensors` (`MODEL_URL`, `MODEL_SHA256` obligatoire), exécute `sandbox/samples/model/txt2img_checkpoint.json` sur CPU |

Le runner n'accepte pas d'arguments et lance sous `env -i` : les réglages se placent en tête du script envoyé.

```sh
{ printf 'MODE=tests\n'; cat scripts/sandbox/runner/comfyui-runner.sh; } > /tmp/job.sh
{ printf 'MODE=generate\nMODEL_URL=%s\nMODEL_SHA256=%s\nSTEPS=8\n' "$URL" "$SHA"; cat scripts/sandbox/runner/comfyui-runner.sh; } > /tmp/job.sh
# puis, avec le skill harnais-session (après relecture du script par l'utilisateur) :
bash scripts/offload.sh -f /tmp/job.sh --timeout 120 --session S --get out/summary.txt
```

Garde-fous : https uniquement, `.safetensors` uniquement (pas de pickle), empreinte SHA-256 vérifiée (fichier supprimé sinon),
plafond de taille `MAX_MODEL_BYTES` (6 Go). Les sorties vont dans `$BRIDGE_WS/out/` ; le harnais retire les fichiers > 95 Mo.

Non testé de bout en bout (aucun runner joignable depuis la session de rédaction) : `uv python install 3.13`, le téléchargement
du wheelhouse sur le runner et une vraie génération. Valider d'abord avec `MODE=info`, puis `MODE=tests`.
Sur CPU, 2 cœurs : un SD1.5 en 256×256/8 pas prend de quelques minutes ; SDXL est à éviter.
