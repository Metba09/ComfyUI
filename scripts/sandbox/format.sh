#!/usr/bin/env bash
# Corrections automatiques sûres (ruff --fix) sur les fichiers donnés, ou sur les fichiers Python modifiés.
# Le dépôt n'impose pas `ruff format` : on ne reformate donc pas.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/env.sh"
need_venv
if [ $# -gt 0 ]; then files="$*"; else
  files="$( { git diff --name-only HEAD; git ls-files -o --exclude-standard; } | grep '\.py$' | sort -u || true)"
fi
[ -n "$files" ] || { say "format : rien à corriger"; exit 0; }
# shellcheck disable=SC2086
ruff check --fix $files
