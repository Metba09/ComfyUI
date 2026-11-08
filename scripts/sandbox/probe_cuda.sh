#!/usr/bin/env bash
# Mesure quels paquets NVIDIA du torch de PyPI sont réellement nécessaires pour `import torch` sans GPU.
# Résultat de référence (torch 2.15.0+cu132) : voir CUDA_OPTIONAL dans scripts/sandbox/vendor.py.
# À relancer après toute mise à jour de torch ; nécessite les wheels de vendor/wheels et vendor/wheels-cuda,
# et, pour tester aussi les paquets optionnels, `python3 scripts/sandbox/vendor.py --fetch --with-cuda-optional`.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/env.sh"

tmp="$(mktemp -d /tmp/probe-cuda.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
python3 -m venv "$tmp/v"
pip="$tmp/v/bin/pip"; py="$tmp/v/bin/python"
"$pip" install -q --no-index --find-links vendor/wheels --no-deps --require-hashes -r vendor/requirements.lock.txt
for lock in requirements.cuda.lock.txt requirements.cuda-optional.lock.txt; do
  dir=wheels-cuda; [ "$lock" = requirements.cuda-optional.lock.txt ] && dir=wheels-cuda-optional
  compgen -G "vendor/$dir/*.whl" >/dev/null && "$pip" install -q --no-index --find-links "vendor/$dir" --no-deps --require-hashes -r "vendor/$lock"
done
probe() { "$py" -c 'import torch, torchvision; x = torch.randn(8, 8); (x @ x).sum()' >/dev/null 2>&1; }
probe || die "torch ne s'importe pas même avec tous les paquets installés"
for lock in requirements.cuda.lock.txt requirements.cuda-optional.lock.txt; do
  for name in $(sed 's/==.*//' "vendor/$lock"); do
    "$pip" uninstall -y -q "$name" >/dev/null 2>&1 || continue
    if probe; then say "OPTIONNEL  $name"; else say "REQUIS     $name"; grep "^$name==" "vendor/$lock" > "$tmp/one.txt"
      d=wheels-cuda; [ "$lock" = requirements.cuda-optional.lock.txt ] && d=wheels-cuda-optional
      "$pip" install -q --no-index --find-links "vendor/$d" --no-deps --require-hashes -r "$tmp/one.txt"; fi
  done
done
