---
name: comfyui-sandbox
description: Utiliser ComfyUI (fork Metba09/ComfyUI, branche sandbox-hermetic) en session Chat, CPU et hors-ligne, avec le wheelhouse vendorisé : installer, vérifier, lancer des workflows sans modèle.
---

# ComfyUI en session Chat (CPU, hors-ligne, vendorisé)

Le sandbox repart de zéro à chaque session : 2 cœurs, ~6-8 Go de RAM (souvent < 2,5 Go libres), pas de GPU, réseau limité à GitHub et aux registres de paquets. Le fork `Metba09/ComfyUI`, branche `sandbox-hermetic`, est reconditionné pour ça. Toute la logique vit dans `scripts/sandbox/` ; le `Makefile` n'est qu'une table de raccourcis. Lire `CLAUDE.md` (section « Session Chat ») du dépôt en cas de doute : il fait foi.

## 1. Récupérer le dépôt

Le fork est public : cloner sans rattachement suffit pour lire.

```sh
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 -b sandbox-hermetic https://github.com/Metba09/ComfyUI /home/claude/comfyui
```

Si le clone échoue (proxy git), repli : dans `Metba09/claude-memory`, `livrables/comfyui-sandbox/` contient `comfyui-source.tar.gz`, `SHA256SUMS` et `restore.sh` (`bash restore.sh /chemin`). Le fichier `sandbox/BUNDLE.json` du dépôt épingle ce livrable (empreintes des lockfiles et du tarball, base amont, Python) : `make verify-bundle ARGS='--livrable <dossier>'` vérifie la concordance. Le dépôt est la source de vérité, le livrable un miroir. Pousser vers le fork demande de le rattacher avec accès en écriture (`add_repo`, access push) ; les Releases GitHub sont refusées pour ce type de session.

## 2. Installer (idempotent, sans saisie)

```sh
cd /home/claude/comfyui && make setup        # ou : bash setup.sh   (MEDIA=0 saute les templates médias, 527 Mo)
```

- ~35 s la première fois, ~3 s ensuite. Crée `.venv` (Python 3.13 exigé : `vendor/PYTHON_VERSION`) et `.env` depuis `.env.example`.
- Les wheels (~3,1 Go : core 813 Mo, cuda 1,8 Go, médias 527 Mo) ne sont PAS dans Git. S'ils manquent, `setup.sh` les re-télécharge à l'identique depuis PyPI (`pip --require-hashes` refuse tout fichier différent), puis installe sans réseau. Ce téléchargement dure plusieurs minutes : un appel d'outil est limité à ~10 min et un wheelhouse interrompu est détecté et repris en relançant la même commande.
- `OFFLINE_STRICT=1` interdit tout téléchargement. Mauvaise version de Python : le script s'arrête avec un message ; il faut alors `make vendor` (PyPI requis) avec ce Python.
- `torch` vient de PyPI en build CUDA (l'index CPU de PyTorch est bloqué) : il exige 11 libs NVIDIA pour s'importer même sans GPU. `torch.cuda.is_available()` vaut `False`, c'est normal.

## 3. Vérifier avant de travailler ou de conclure

```sh
make check            # lint + tests rapides + smoke (~2 min)
make offline-check    # idem, réseau coupé (unshare -rn) : preuve hors-ligne
```

Autres cibles : `make lint` (contrôle aussi `sandbox/BUNDLE.json`), `make verify-bundle` (pointeur seul, sans réseau), `make format`, `make test-fast` (~1,5 min), `make test` (tests-unit, ~7 min), `make test-exec` (~2,5 min), `make smoke`, `make run`. Cibler : `make test ARGS='tests-unit/comfy_test -k nom'`. Lancer les suites longues avec un délai d'outil généreux (≈ 10 min). Références mesurées : tests-unit 3365 réussis / 94 ignorés / 0 échec ; tests/execution 342 / 7 / 5 déselectionnés (`COMFY_ALL_EXEC=1` les inclut, ≥ 2 Go de RAM libre) ; smoke OK (693 nœuds, 3 workflows).

## 4. Utiliser ComfyUI

Tout ce qui n'a pas besoin de modèle fonctionne : opérations sur images et masques (`EmptyImage`, `LoadImage`, `ImageScale`, `ImageInvert`, `ImageBlend`, `SolidMask`, `MaskToImage`, `SaveImage`…), latents vides, logique de graphe. Modèles de départ : `sandbox/samples/workflows/*.json` (format API) et `input/example.png`.

- Exécuter un graphe sur un serveur éphémère : `make smoke ARGS='--workflow chemin.json'`. Pour GARDER les images : `make smoke ARGS='--workflow g.json --keep-output /tmp/out --workflow-timeout 1800'` (sans `--keep-output`, le dossier de sortie est supprimé). Puis livrer les images de `/tmp/out` avec SendUserFile.
- Alternative manuelle (serveur lancé à soi, dans le MÊME appel d'outil que les requêtes : les processus d'arrière-plan sont tués à la fin de l'appel) :

```sh
source scripts/sandbox/env.sh   # place .venv dans le PATH, coupe HF
mkdir -p /tmp/out && python main.py --cpu --offline --disable-auto-launch --listen 127.0.0.1 --port 8188 --output-directory /tmp/out &
for i in $(seq 90); do curl -s -m 2 127.0.0.1:8188/system_stats >/dev/null && break; sleep 1; done
curl -s -X POST 127.0.0.1:8188/prompt -H 'Content-Type: application/json' -d "{\"prompt\": $(cat graphe.json)}"
# suivre GET /history/<prompt_id>, puis lire /tmp/out ; kill %1 en fin d'appel
```

Livrer ensuite les images avec SendUserFile.

## 5. Ce qui est inutilisable ici

- **GPU/CUDA, modèles** : `models/` est vide ; KSampler, chargeurs de checkpoints et `tests/inference`, `tests/compare` ne tournent pas. Sans modèle fourni par l'utilisateur, ne pas promettre de génération d'images par diffusion. Un petit modèle joint par l'utilisateur à placer dans `models/…` pourrait marcher sur CPU, mais très lentement et sans test : le dire.
- **Nœuds partenaires** (334, `comfy_api_nodes`) : désactivés par `--offline`. Pas de ComfyUI-Manager ni d'agent (`--enable-manager`, `--enable-agent`), pas de custom nodes téléchargés, pas de `--front-end-version owner/repo@tag`, pas de téléchargement de modèles.
- **Secrets** : aucun requis ; `COMFY_API_KEY` reste vide. Ne rien ajouter qui appelle Internet dans le cœur (`AGENTS.md`).

## 6. Pièges connus

- 5 tests de `tests/execution` (4 en variante `server3` + `test_exr_previews.py::test_a_cached_rerun_keeps_the_preview`) sont déselectionnés par `scripts/sandbox/test.sh` : le cache « RAM pressure » exige ≥ 2 Go de RAM libre et évince ses entrées sinon. Limite de l'environnement, pas un bug.
- Les tests se lancent seuls grâce au plugin `sandbox/pytest_force_cpu.py` (force `--cpu`) ; toujours passer par `scripts/sandbox/test.sh`, pas par `pytest` nu.
- `python main.py` sans le venv dans le `PATH` utilise le Python système sans `torch` : passer par `make run` ou `source scripts/sandbox/env.sh`.
- `lint.sh` fait un `git init` local si le dossier n'a pas de `.git` (archive), sinon `ruff` analyserait tout, `custom_nodes/` compris.
- Rafraîchir les versions figées : `make vendor` (réécrit les lockfiles, PyPI requis), puis `make check`. `make lint` échoue alors tant que les empreintes de `sandbox/BUNDLE.json` ne sont pas mises à jour, et le livrable de `claude-memory` régénéré (`make bundle`) : c'est voulu, ça évite un pointeur périmé. Après un changement de torch, relancer `make probe-cuda` et mettre à jour `CUDA_OPTIONAL` dans `scripts/sandbox/vendor.py`.

## 6 bis. Runner claude-bridge (RAM suffisante, réseau ouvert)

`scripts/sandbox/runner/comfyui-runner.sh` : modes `info`, `tests` (suites complètes, `COMFY_ALL_EXEC=1`), `generate` (télécharge UN `.safetensors` : `MODEL_URL` https + `MODEL_SHA256` obligatoires, plafond 6 Go, graphe `sandbox/samples/model/txt2img_checkpoint.json`, CPU). Réglages en variables placées en tête du script (`{ printf 'MODE=tests\n'; cat comfyui-runner.sh; } > /tmp/job.sh`), car le runner n'a pas d'arguments. Montrer le script à l'utilisateur avant envoi ; jamais de modèle inventé. Non testé de bout en bout : commencer par `MODE=info`. Détails : `scripts/sandbox/runner/README.md`.

## 7. Avant de conclure

1. `make check` (ou `make offline-check`) vert. 2. Aucun appel réseau ajouté au cœur. 3. Les wheels ne se versionnent pas : ne jamais les pousser dans `claude-memory` (règle < 40 Mo, historique non purgeable) ni dans le fork public (bibliothèques NVIDIA sous licence propriétaire) sans accord explicite.
