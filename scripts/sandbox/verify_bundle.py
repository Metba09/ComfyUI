#!/usr/bin/env python3
"""Vérifie sandbox/BUNDLE.json : le pointeur du dépôt vers le livrable de claude-memory.

    python3 scripts/sandbox/verify_bundle.py                       # lockfiles locaux et pointeur (sans réseau)
    python3 scripts/sandbox/verify_bundle.py --livrable DIR        # + tarball du livrable (copie locale de
                                                                   #   claude-memory/livrables/comfyui-sandbox)
Code 0 = cohérent. Toute dérive est signalée : lockfile modifié, tarball altéré, lockfiles du livrable différents.

Le tarball épinglé est celui construit depuis `bundle.source_commit`, un commit ANTÉRIEUR à BUNDLE.json : le fichier ne
peut pas contenir l'empreinte d'une archive qui le contient. Le dépôt reste donc la source de vérité, le livrable un miroir.
"""
import argparse
import hashlib
import io
import json
import sys
import tarfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POINTER = ROOT / "sandbox" / "BUNDLE.json"


def say(*parts):
    sys.stdout.write(" ".join(str(x) for x in parts) + "\n")


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--livrable", help="dossier local livrables/comfyui-sandbox de claude-memory")
    a = ap.parse_args()

    ptr = json.loads(POINTER.read_text())
    bad = []

    for name, want in ptr["lockfiles_sha256"].items():
        p = ROOT / "vendor" / name
        got = sha256_bytes(p.read_bytes()) if p.exists() else "absent"
        if got != want:
            bad.append(f"lockfile {name} : {got[:12]} != {want[:12]}")
    py = (ROOT / "vendor" / "PYTHON_VERSION").read_text().strip()
    if py != ptr["python"]:
        bad.append(f"Python {py} != {ptr['python']}")
    say(f"pointeur : {len(ptr['lockfiles_sha256'])} lockfiles, Python {ptr['python']}, base amont {ptr['upstream_base'][:7]}")

    if a.livrable:
        d = Path(a.livrable)
        tar_path = d / ptr["bundle"]["tarball"]
        if not tar_path.exists():
            bad.append(f"tarball absent : {tar_path}")
        else:
            data = tar_path.read_bytes()
            if sha256_bytes(data) != ptr["bundle"]["tarball_sha256"]:
                bad.append("tarball : empreinte différente de BUNDLE.json (archive non lue)")
            else:
                try:
                    with tarfile.open(fileobj=io.BytesIO(data)) as t:
                        for name, want in ptr["lockfiles_sha256"].items():
                            m = t.extractfile(f"ComfyUI/vendor/{name}")
                            if m is None or sha256_bytes(m.read()) != want:
                                bad.append(f"lockfile {name} du livrable différent du pointeur")
                except (tarfile.TarError, KeyError, OSError, EOFError, zlib.error) as e:
                    bad.append(f"tarball illisible ou incomplet : {type(e).__name__}: {e}")
                say(f"livrable : {tar_path.name} contrôlé (empreinte et lockfiles)")
    else:
        b = ptr["bundle"]
        say(f"livrable : non contrôlé (--livrable). Emplacement : {b['repo']} / {b['path']}")

    if bad:
        for line in bad:
            say("ÉCART :", line)
        say("verify-bundle : ÉCHEC")
        return 1
    say("verify-bundle : OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
