# Commandes du bundle hermétique (session Chat). Toute la logique vit dans scripts/sandbox/ : ce Makefile n'est
# qu'une table de raccourcis, chaque cible a son équivalent `bash scripts/sandbox/<script>.sh`.
SHELL := /bin/bash
ARGS ?=
BUNDLE_ARGS ?=

.PHONY: help setup vendor fetch verify-vendor lint format test test-fast test-exec test-all smoke check offline-check run bundle probe-cuda verify-bundle clean

help:
	@echo "make setup          installe tout, hors-ligne, sans saisie (idempotent)   [MEDIA=0 : sans templates médias]"
	@echo "make check          lint + tests rapides + smoke test  (à lancer avant de conclure)"
	@echo "make offline-check  idem, dans un espace réseau coupé (preuve hors-ligne)"
	@echo "make lint | format  vérifications statiques | corrections ruff automatiques"
	@echo "make test           tests-unit complet (~7 min)    ARGS='tests-unit/comfy_test -k foo' pour cibler"
	@echo "make test-fast      sous-ensemble rapide (~1,5 min)"
	@echo "make test-exec      tests/execution (~2,5 min)       make test-all : tout"
	@echo "make smoke          serveur local CPU --offline + workflows sans modèle"
	@echo "make run            lance le serveur (options de COMFY_ARGS dans .env)"
	@echo "make fetch          re-télécharge le wheelhouse EXACT des lockfiles (PyPI requis)"
	@echo "make vendor         re-résout les versions et réécrit les lockfiles (PyPI requis)"
	@echo "make verify-vendor  vérifie les empreintes du wheelhouse"
	@echo "make verify-bundle  contrôle sandbox/BUNDLE.json (ARGS='--livrable DIR' : + tarball de claude-memory)"
	@echo "make bundle         archives source + patch (BUNDLE_ARGS='--groups core,cuda,media' ajoute le wheelhouse)"

setup:
	@bash scripts/sandbox/setup.sh

fetch:
	@python3 scripts/sandbox/vendor.py --fetch

vendor:
	@python3 scripts/sandbox/vendor.py

verify-vendor:
	@python3 scripts/sandbox/vendor.py --verify

lint:
	@bash scripts/sandbox/lint.sh

format:
	@bash scripts/sandbox/format.sh $(ARGS)

test:
	@bash scripts/sandbox/test.sh unit $(ARGS)

test-fast:
	@bash scripts/sandbox/test.sh fast $(ARGS)

test-exec:
	@bash scripts/sandbox/test.sh exec $(ARGS)

test-all:
	@bash scripts/sandbox/test.sh all $(ARGS)

smoke:
	@bash -c '. scripts/sandbox/env.sh; need_venv; run_cmd python scripts/sandbox/smoke.py $(ARGS)'

check:
	@bash scripts/sandbox/check.sh

offline-check:
	@NETOFF=1 bash scripts/sandbox/check.sh

run:
	@bash -c '. scripts/sandbox/env.sh; need_venv; exec python main.py $${COMFY_ARGS:---cpu --offline --disable-auto-launch} --listen $${COMFY_HOST:-127.0.0.1} --port $${COMFY_PORT:-8188}'

bundle:
	@bash scripts/sandbox/bundle.sh $(BUNDLE_ARGS)

verify-bundle:
	@python3 scripts/sandbox/verify_bundle.py $(ARGS)

probe-cuda:
	@bash scripts/sandbox/probe_cuda.sh

clean:
	rm -rf .venv dist
