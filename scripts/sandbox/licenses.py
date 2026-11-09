#!/usr/bin/env python3
"""Extrait les licences des wheels vendorisés vers vendor/LICENSES/ et écrit vendor/LICENSES/INDEX.md.

    python3 scripts/sandbox/licenses.py            # lit vendor/wheels*, écrit vendor/LICENSES
    python3 scripts/sandbox/licenses.py --check    # échoue si un wheel n'a ni licence déclarée ni fichier de licence

Les fichiers viennent des dist-info des wheels (rien n'est inventé). Les paquets NVIDIA (nvidia-*, cuda-*) sont signalés :
licence propriétaire, redistribution restreinte -> ne pas pousser ces wheels dans un dépôt public.
"""
import argparse
import email.parser
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "vendor" / "LICENSES"
RESTRICTED = ("nvidia-", "cuda-", "triton")
LICENSE_HINTS = ("licen", "copying", "notice", "authors")


def say(*parts):
    sys.stdout.write(" ".join(str(x) for x in parts) + "\n")


def inspect(whl):
    with zipfile.ZipFile(whl) as z:
        names = z.namelist()
        meta = next((n for n in names if n.endswith(".dist-info/METADATA")), None)
        msg = email.parser.Parser().parsestr(z.read(meta).decode("utf-8", "replace"), headersonly=True) if meta else {}
        decl = (msg.get("License-Expression") or msg.get("License") or "").strip().splitlines()
        decl = decl[0][:120] if decl else ""
        if not decl:
            decl = "; ".join(c.split("::")[-1].strip() for c in (msg.get_all("Classifier") or []) if c.startswith("License ::"))
        files = [n for n in names if ".dist-info/" in n and not n.endswith("/")
                 and not n.endswith((".py", ".pyc"))
                 and any(h in n.rsplit("/", 1)[-1].lower() for h in LICENSE_HINTS)]
        return msg.get("Name", whl.name), msg.get("Version", "?"), decl, files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    wheels = sorted(p for d in ("wheels", "wheels-cuda", "wheels-media") for p in (ROOT / "vendor" / d).glob("*.whl"))
    if not wheels:
        say("aucun wheel : lancer `make fetch` d'abord")
        return 2
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(parents=True)
    rows, missing = [], []
    for whl in wheels:
        name, ver, decl, files = inspect(whl)
        restricted = name.lower().startswith(RESTRICTED)
        if files:
            dest = OUT / f"{name}-{ver}"
            dest.mkdir(exist_ok=True)
            with zipfile.ZipFile(whl) as z:
                for f in files:
                    (dest / f.rsplit("/", 1)[-1]).write_bytes(z.read(f))
        if not decl and not files:
            missing.append(whl.name)
        rows.append((name, ver, decl or "(non déclarée)", len(files), restricted))
    lines = ["# Licences des composants tiers vendorisés", "",
             "Extraites automatiquement des métadonnées des wheels (`scripts/sandbox/licenses.py`). Rien n'est ajouté à la main.", "",
             "**Restriction de redistribution** : les paquets marqués ⚠ (NVIDIA, triton) sont sous licence propriétaire ou spécifique ;",
             "leurs wheels ne doivent pas être publiés dans un dépôt public sans vérifier ces conditions.", "",
             "| Paquet | Version | Licence déclarée | Fichiers | |", "|---|---|---|---|---|"]
    for n, v, d, c, r in rows:
        lines.append(f"| {n} | {v} | {d.replace('|', '/')} | {c} | {'⚠' if r else ''} |")
    if missing:
        lines += ["", "Sans licence ni fichier de licence dans le wheel : " + ", ".join(missing)]
    (OUT / "INDEX.md").write_text("\n".join(lines) + "\n")
    say(f"{len(rows)} wheels, {sum(1 for r in rows if r[4])} restreints, {len(missing)} sans licence, "
        f"{sum(1 for _ in OUT.rglob('*') if _.is_file())} fichiers dans vendor/LICENSES")
    return 1 if (a.check and missing) else 0


if __name__ == "__main__":
    sys.exit(main())
