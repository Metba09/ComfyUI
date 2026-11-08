# CLAUDE.md

Règles de contribution du projet : lire `AGENTS.md` avant de modifier du code (changements minimaux, aucune requête Internet dans le cœur de ComfyUI).
Ce fichier ajoute uniquement ce qu'il faut pour travailler dans un **sandbox de session Chat Claude.ai**.

## Session Chat

Le sandbox repart de zéro à chaque session : 2 cœurs, ~6 Go de RAM (souvent < 2,5 Go libres), pas de GPU, réseau limité à GitHub et aux registres de paquets.
Tout ce qui fait le travail est un script ordinaire dans `scripts/sandbox/` ; le `Makefile` n'est qu'une table de raccourcis. Aucun hook : on lance les vérifications à la main.

### Installation et tests (commandes exactes)

```sh
make setup          # ou : bash setup.sh   — idempotent, sans saisie, hors-ligne (~35 s la 1re fois, ~3 s ensuite)
make check          # lint + tests rapides + smoke test (~2 min) — à lancer avant de conclure
make offline-check  # idem dans un espace réseau coupé : preuve que rien ne dépend d'Internet
```

Autres cibles : `make lint`, `make format`, `make test-fast` (~1,5 min), `make test` (tests-unit complet, ~7 min), `make test-exec` (~2,5 min),
`make test-all`, `make smoke`, `make run` (serveur local), `make bundle`. Cibler un test : `make test ARGS='tests-unit/comfy_test -k nom'`.
Un appel d'outil dure au plus ~10 min : lancer `make test` et `make test-all` avec un délai généreux.
Sans `make` : `bash scripts/sandbox/{setup,check,lint,test,smoke...}`.

Résultats de référence (sandbox, réseau coupé) : tests-unit 3365 réussis / 94 ignorés / 0 échec ; tests/execution 342 réussis / 7 ignorés / 5 déselectionnés (voir limites) ; `make smoke` OK (693 nœuds, 3 workflows).

### Dépendances vendorisées

- `vendor/requirements*.lock.txt` (versionnés, avec empreintes SHA-256) et `vendor/MANIFEST.sha256` figent 113 paquets (105 vendorisés + 8 NVIDIA/triton optionnels non téléchargés) pour **Python 3.13** (`vendor/PYTHON_VERSION`).
- Les wheels (`vendor/wheels*`, ~3,1 Go) ne sont pas dans Git. Absents, `make setup` les re-télécharge **à l'identique** depuis PyPI
  (`pip --require-hashes` refuse tout fichier différent) ; présents, aucune connexion n'est faite. `OFFLINE_STRICT=1` interdit même ce téléchargement.
- Pourquoi 3 Go : l'index CPU de PyTorch est bloqué dans le sandbox, donc `torch` vient de PyPI (build CUDA). Il refuse de s'importer sans 11 libs NVIDIA
  (`wheels-cuda`, 1,8 Go) même sans GPU ; 8 autres paquets NVIDIA/triton sont inutiles et exclus (mesuré par `make probe-cuda`).
  Les templates de workflows (`wheels-media`, 527 Mo) s'installent par défaut ; `MEDIA=0 make setup` les saute.
- Rafraîchir les versions : `make vendor` (réécrit les lockfiles, PyPI requis) puis revalider avec `make check`.

### Inutilisable dans le sandbox

- **GPU / CUDA** : calcul sur CPU uniquement. `torch` s'importe mais `torch.cuda.is_available()` vaut `False`. Pas de modèles (`models/` est vide) :
  `tests/inference` et `tests/compare` ne sont pas exécutables ici.
- **Docker** et tout service externe : aucun n'est requis.
- **Nœuds partenaires** (`comfy_api_nodes`, 334 nœuds) : désactivés par `--offline` (déjà dans `COMFY_ARGS`). Leurs tests unitaires utilisent leurs propres mocks et passent hors-ligne.
- **ComfyUI-Manager / agent** (`--enable-manager`, `--enable-agent`, `manager_requirements.txt`, `agent_requirements.txt`) : non vendorisés, ils ont besoin du réseau.
- **Téléchargement de modèles**, installation de custom nodes, `--front-end-version owner/repo@tag` (appelle l'API GitHub) : à ne pas utiliser. Le frontend et les templates viennent des paquets pip figés.
- **Secrets** : aucun requis. `.env.example` ne contient que des réglages locaux ; `COMFY_API_KEY` reste vide.
- `make offline-check` / `NETOFF=1` exigent `unshare -rn` (présent dans le sandbox) ; si l'espace réseau ne peut pas être créé, la commande s'arrête au lieu de tourner avec du réseau.

### Limites connues (mesurées, pas des bugs du code)

- `tests/execution` : 5 tests sont déselectionnés par `scripts/sandbox/test.sh` (4 en variante `server3` de `test_execution.py` : `test_full_cache`, `test_partial_cache`, `test_custom_is_changed`, `test_is_changed_with_outputs`, et `test_exr_previews.py::test_a_cached_rerun_keeps_the_preview`).
  Ce cache exige ≥ 2 Go de RAM libre et évince ses entrées quand le sandbox en a moins ; les assertions « déjà en cache » échouent alors.
- Les tests se lancent seuls grâce au plugin `sandbox/pytest_force_cpu.py` (force `--cpu` : le torch CUDA de PyPI plante à l'import sans pilote NVIDIA, contrairement au torch CPU de la CI amont).

### Données d'exemple locales

`sandbox/samples/workflows/*.json` : graphes API sans modèle (utilisés par `make smoke`), à copier pour en écrire d'autres. `input/example.png` est l'image d'entrée.

### Commandes à lire à la demande

Fines enveloppes autour des scripts ci-dessus ; ne les lire que quand la tâche correspond :
`.claude/commands/setup.md`, `check.md`, `lint.md`, `test.md`, `smoke.md`, `review.md` (revue d'un diff selon `AGENTS.md`).

### Avant de conclure

1. `make check` (ou `make offline-check`) doit être vert. 2. Aucune requête réseau ajoutée au cœur (`AGENTS.md`). 3. Livrer les fichiers produits ; les wheels ne se versionnent pas (voir `make bundle`).
