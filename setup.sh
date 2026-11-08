#!/usr/bin/env bash
# Point d'entrée à la racine : installation idempotente, sans saisie (voir scripts/sandbox/setup.sh).
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/sandbox/setup.sh" "$@"
