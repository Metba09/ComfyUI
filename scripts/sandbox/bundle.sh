#!/usr/bin/env bash
# Empaquette le dépôt reconditionné en archives autonomes, avec empreintes et script de restauration.
#   bash scripts/sandbox/bundle.sh                              # source + patch + lockfiles (quelques Mo)
#   bash scripts/sandbox/bundle.sh --groups core,cuda,media     # + wheelhouse découpé en morceaux (~3,1 Go)
#   options : --out DIR (défaut dist/comfyui-sandbox)  --split-mb N (défaut 40)  --base REF (défaut master)
# Le wheelhouse est reproductible sans archive : `make fetch` le re-télécharge à l'identique (empreintes vérifiées).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/env.sh"

OUT="dist/comfyui-sandbox"; MB=40; GROUPS_LIST=""; BASE="master"
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --split-mb) MB="$2"; shift 2 ;;
    --groups) GROUPS_LIST="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    *) die "option inconnue : $1" ;;
  esac
done

[ -z "$(git status --porcelain --untracked-files=no)" ] || die "modifications non commitées : committer d'abord (l'archive reflète HEAD)"
rm -rf "$OUT"; mkdir -p "$OUT"

say "bundle : source (git archive HEAD)"
git archive --format=tar.gz --prefix=ComfyUI/ -o "$OUT/comfyui-source.tar.gz" HEAD
say "bundle : patch par rapport à $BASE"
git diff "$BASE"..HEAD > "$OUT/comfyui-sandbox.patch"

for g in ${GROUPS_LIST//,/ }; do
  case "$g" in core) d=wheels ;; cuda) d=wheels-cuda ;; media) d=wheels-media ;; *) die "groupe inconnu : $g" ;; esac
  compgen -G "vendor/$d/*.whl" >/dev/null || die "vendor/$d vide : lancer 'make fetch' d'abord"
  say "bundle : wheelhouse $g (morceaux de ${MB} Mo)"
  tar -cf - -C vendor "$d" | split -b "${MB}M" -d -a 3 - "$OUT/comfyui-wheelhouse-$g.tar.part-"
done

cat > "$OUT/restore.sh" <<'EOS'
#!/usr/bin/env bash
# Restaure le dépôt (et le wheelhouse présent dans ce dossier) dans le dossier courant ou celui passé en argument.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$PWD}"
( cd "$HERE" && sha256sum -c SHA256SUMS )
mkdir -p "$DEST"
tar -xzf "$HERE/comfyui-source.tar.gz" -C "$DEST"
for g in core cuda media; do
  parts=("$HERE"/comfyui-wheelhouse-$g.tar.part-*)
  [ -e "${parts[0]}" ] && cat "${parts[@]}" | tar -xf - -C "$DEST/ComfyUI/vendor"
done
echo "OK : cd $DEST/ComfyUI && make setup && make check"
EOS
chmod +x "$OUT/restore.sh"

cat > "$OUT/README.md" <<'EOR'
# ComfyUI — bundle hermétique pour sandbox de session Chat

| Fichier | Rôle |
|---|---|
| `comfyui-source.tar.gz` | dépôt ComfyUI reconditionné (scripts, lockfiles, CLAUDE.md, exemples), sans wheels |
| `comfyui-sandbox.patch` | différences avec l'amont |
| `comfyui-wheelhouse-<groupe>.tar.part-NNN` | (optionnel) wheels vendorisés, découpés ; groupes : core, cuda, media |
| `SHA256SUMS`, `restore.sh` | vérification et restauration |

Sans les morceaux de wheelhouse, `make setup` re-télécharge exactement les mêmes wheels depuis PyPI (empreintes
imposées par `--require-hashes`), puis tout fonctionne sans réseau. Voir `CLAUDE.md`, section « Session Chat ».
EOR

( cd "$OUT" && sha256sum -- * > SHA256SUMS.tmp 2>/dev/null; grep -v ' SHA256SUMS' SHA256SUMS.tmp > SHA256SUMS; rm -f SHA256SUMS.tmp )
say "bundle : terminé -> $OUT ($(du -sh "$OUT" | cut -f1))"
