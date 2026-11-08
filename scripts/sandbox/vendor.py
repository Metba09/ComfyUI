#!/usr/bin/env python3
"""Vendoring des dépendances Python de ComfyUI dans vendor/wheels (wheelhouse hors-ligne).

À lancer UNE FOIS avec accès à PyPI (le sandbox de session y a accès). Ensuite tout se fait sans réseau :
    python3 scripts/sandbox/vendor.py --fetch    # re-télécharge EXACTEMENT les versions des lockfiles (reproductible)
    python3 scripts/sandbox/vendor.py            # re-résout (versions récentes), télécharge, réécrit les lockfiles
    python3 scripts/sandbox/vendor.py --verify   # revérifie les empreintes d'un wheelhouse existant (sans réseau)

Le sandbox n'a ni GPU ni CUDA, mais le torch de PyPI (build CUDA) refuse de s'importer sans ses libs NVIDIA
(l'index CPU de PyTorch est bloqué par le réseau du sandbox). D'où quatre groupes :
    core           : tout sauf ce qui suit                         -> vendor/wheels, requirements.lock.txt
    cuda           : libs NVIDIA indispensables à `import torch`   -> vendor/wheels-cuda, requirements.cuda.lock.txt
    cuda-optional  : libs NVIDIA inutiles sur CPU + triton         -> requirements.cuda-optional.lock.txt (non téléchargés)
    media          : templates de workflows médias (~530 Mo)       -> vendor/wheels-media (--no-media pour les ignorer)
"""
import argparse
import concurrent.futures as cf
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def say(*parts):
    sys.stdout.write(" ".join(str(x) for x in parts) + "\n")


VENDOR = ROOT / "vendor"
REQ_INPUTS = [ROOT / "requirements.txt", ROOT / "tests-unit" / "requirements.txt", ROOT / "sandbox" / "dev-requirements.txt"]
CUDA_PREFIXES = ("nvidia-", "cuda-", "triton")
# Mesuré avec torch 2.15.0+cu132 : `import torch` + calcul CPU fonctionnent sans ces paquets (voir probe_cuda.sh).
# À remesurer si la version de torch change.
CUDA_OPTIONAL = {"cuda-bindings", "cuda-pathfinder", "cuda-toolkit", "nvidia-cuda-cccl", "nvidia-cusolver",
                 "nvidia-nvjitlink", "nvidia-nvtx", "triton"}
MEDIA_PREFIX = "comfyui-workflow-templates-media-"


def norm(name):
    return name.lower().replace("_", "-")


def resolve(report_path):
    reqs = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False)
    for f in REQ_INPUTS:
        for line in f.read_text().splitlines():
            line = line.split("#")[0].strip()
            if line:
                reqs.write(line + "\n")
    reqs.close()
    subprocess.run([sys.executable, "-m", "pip", "install", "--dry-run", "--ignore-installed", "--quiet",
                    "--report", str(report_path), "-r", reqs.name], check=True)
    return json.loads(Path(report_path).read_text())


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(item):
    name, ver, url, digest, dest = item
    out = dest / url.rsplit("/", 1)[1]
    if out.exists() and sha256(out) == digest:
        return name, "ok (déjà là)"
    dest.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(out.suffix + ".part")
    subprocess.run(["curl", "-fsSL", "--retry", "4", "--retry-delay", "3", "-o", str(tmp), url], check=True)
    if sha256(tmp) != digest:
        tmp.unlink()
        raise SystemExit(f"empreinte invalide : {name}")
    tmp.rename(out)
    return name, "téléchargé"


def classify(name):
    n = norm(name)
    if n in CUDA_OPTIONAL:
        return "cuda-optional"
    if n.startswith(CUDA_PREFIXES):
        return "cuda"
    if n.startswith(MEDIA_PREFIX):
        return "media"
    return "core"


def write_locks(entries):
    groups = {"core": [], "media": [], "cuda": [], "cuda-optional": []}
    for e in entries:
        groups[e["group"]].append(e)
    files = {"core": "requirements.lock.txt", "media": "requirements.media.lock.txt", "cuda": "requirements.cuda.lock.txt",
             "cuda-optional": "requirements.cuda-optional.lock.txt"}
    for g, fname in files.items():
        lines = [f"{norm(e['name'])}=={e['version']} --hash=sha256:{e['sha256']}" for e in sorted(groups[g], key=lambda e: norm(e["name"]))]
        (VENDOR / fname).write_text("\n".join(lines) + "\n")
    manifest = [f"{e['sha256']}  {e['dir']}/{e['file']}" for e in sorted(entries, key=lambda e: e["file"])]
    (VENDOR / "MANIFEST.sha256").write_text("\n".join(manifest) + "\n")


def parse_lock(path):
    for line in path.read_text().splitlines():
        if line.strip():
            req, _, h = line.partition(" --hash=sha256:")
            name, _, ver = req.partition("==")
            yield name, ver, h.strip()


def pypi_url(name, ver, digest):
    """URL du fichier de PyPI dont l'empreinte SHA-256 est celle du lockfile (jamais un autre fichier)."""
    raw = subprocess.run(["curl", "-fsSL", "--retry", "4", "--retry-delay", "3", f"https://pypi.org/pypi/{name}/{ver}/json"],
                         check=True, capture_output=True, text=True).stdout
    for f in json.loads(raw)["urls"]:
        if f["digests"]["sha256"] == digest:
            return f["url"]
    raise SystemExit(f"{name}=={ver} : aucun fichier de PyPI ne correspond à l'empreinte du lockfile")


def fetch_from_locks(a):
    """Re-télécharge EXACTEMENT les fichiers des lockfiles : URL retrouvée par empreinte, téléchargement parallèle
    et repris si interrompu, empreinte revérifiée à l'arrivée."""
    groups = [("wheels", "requirements.lock.txt")]
    if not a.no_media:
        groups.append(("wheels-media", "requirements.media.lock.txt"))
    groups.append(("wheels-cuda", "requirements.cuda.lock.txt"))
    if a.with_cuda_optional:
        groups.append(("wheels-cuda-optional", "requirements.cuda-optional.lock.txt"))
    todo = []
    for d, lock in groups:
        for name, ver, digest in parse_lock(VENDOR / lock):
            todo.append((name, ver, digest, VENDOR / d))

    def one(t):
        name, ver, digest, dest = t
        return fetch((name, ver, pypi_url(name, ver, digest), digest, dest))

    with cf.ThreadPoolExecutor(a.jobs) as ex:
        for name, state in ex.map(one, todo):
            say(f"{name}: {state}")
    (VENDOR / "PYTHON_VERSION").write_text("%d.%d\n" % sys.version_info[:2])
    say(f"{len(todo)} wheels vérifiés dans {VENDOR}")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--fetch", action="store_true", help="télécharge les versions figées des lockfiles, sans re-résoudre")
    ap.add_argument("--no-media", action="store_true")
    ap.add_argument("--with-cuda-optional", action="store_true", help="télécharge aussi les wheels CUDA non requis à l'import (~565 Mo)")
    ap.add_argument("--jobs", type=int, default=8)
    a = ap.parse_args()

    if a.verify:
        bad = 0
        for line in (VENDOR / "MANIFEST.sha256").read_text().splitlines():
            digest, rel = line.split("  ", 1)
            p = VENDOR / rel
            if p.exists() and sha256(p) != digest:
                say("EMPREINTE INVALIDE", rel)
                bad += 1
        say("vérification terminée :", "échec" if bad else "OK")
        return 1 if bad else 0

    VENDOR.mkdir(exist_ok=True)
    if a.fetch:
        return fetch_from_locks(a)
    report = resolve(VENDOR / "resolve-report.json")
    entries, todo = [], []
    for it in report["install"]:
        meta, dl = it["metadata"], it["download_info"]
        group = classify(meta["name"])
        d = {"core": "wheels", "media": "wheels-media", "cuda": "wheels-cuda", "cuda-optional": "wheels-cuda-optional"}[group]
        file = dl["url"].rsplit("/", 1)[1]
        digest = dl["archive_info"]["hashes"]["sha256"]
        entries.append({"name": meta["name"], "version": meta["version"], "group": group, "dir": d, "file": file, "sha256": digest})
        if group == "media" and a.no_media:
            continue
        if group == "cuda-optional" and not a.with_cuda_optional:
            continue
        todo.append((meta["name"], meta["version"], dl["url"], digest, VENDOR / d))
    write_locks(entries)
    with cf.ThreadPoolExecutor(a.jobs) as ex:
        for name, state in ex.map(fetch, todo):
            say(f"{name}: {state}")
    (VENDOR / "resolve-report.json").unlink(missing_ok=True)
    (VENDOR / "PYTHON_VERSION").write_text("%d.%d\n" % sys.version_info[:2])
    say(f"{len(todo)} wheels dans {VENDOR} ; lockfiles écrits.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
