#!/usr/bin/env python3
"""Smoke test de bout en bout : démarre ComfyUI (CPU, --offline) sur un port libre, vérifie que le serveur,
le frontend embarqué et le moteur d'exécution fonctionnent, puis exécute des workflows SANS modèle.

    python scripts/sandbox/smoke.py                              # tous les graphes de sandbox/samples/workflows
    python scripts/sandbox/smoke.py --workflow chemin.json       # un graphe précis (format API)
    python scripts/sandbox/smoke.py --workflow g.json --keep-output sortie/ --workflow-timeout 1800   # garder les images
    python scripts/sandbox/netoff.py -- python scripts/sandbox/smoke.py   # idem, réseau coupé (preuve hors-ligne)

Code de sortie 0 = tout est bon. Le journal du serveur est affiché en cas d'échec.
"""
import argparse
import glob
import json
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REQUIRED_NODES = ("LoadImage", "SaveImage", "EmptyImage", "ImageScale", "ImageInvert", "ImageBlend", "SolidMask", "MaskToImage",
                  "KSampler", "CheckpointLoaderSimple", "VAEDecode")


def say(*parts):
    sys.stdout.write(" ".join(str(x) for x in parts) + "\n")
    sys.stdout.flush()


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def http(method, url, body=None, timeout=30):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, dict(r.headers), r.read()


def wait_ready(base, proc, deadline):
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"le serveur s'est arrêté (code {proc.returncode})")
        try:
            if http("GET", base + "/system_stats", timeout=3)[0] == 200:
                return
        except (urllib.error.URLError, OSError):
            time.sleep(1)
    raise RuntimeError("le serveur n'a pas démarré à temps")


def run_workflow(base, name, graph, out_dir, timeout=120):
    _, _, raw = http("POST", base + "/prompt", {"prompt": graph, "client_id": "sandbox-smoke"})
    pid = json.loads(raw)["prompt_id"]
    deadline = time.time() + timeout
    while time.time() < deadline:
        _, _, raw = http("GET", f"{base}/history/{pid}")
        hist = json.loads(raw)
        if pid in hist:
            st = hist[pid]["status"]
            if st["status_str"] != "success":
                raise RuntimeError(f"{name} : exécution en échec : {json.dumps(st)[:400]}")
            files = [f for node in hist[pid]["outputs"].values() for f in node.get("images", [])]
            if not files:
                raise RuntimeError(f"{name} : aucune image produite")
            for f in files:
                p = Path(out_dir) / f.get("subfolder", "") / f["filename"]
                if not p.exists() or p.stat().st_size < 50:
                    raise RuntimeError(f"{name} : fichier de sortie absent ou vide : {p}")
            return len(files)
        time.sleep(0.5)
    raise RuntimeError(f"{name} : délai dépassé")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workflow", action="append", help="graphe au format API (répétable)")
    ap.add_argument("--startup-timeout", type=int, default=180)
    ap.add_argument("--workflow-timeout", type=int, default=120, help="secondes par workflow (inférence CPU : prévoir large)")
    ap.add_argument("--keep-output", metavar="DIR", help="copie les images produites dans DIR avant de nettoyer le dossier temporaire")
    a = ap.parse_args()

    workflows = a.workflow or sorted(glob.glob(str(ROOT / "sandbox" / "samples" / "workflows" / "*.json")))
    if not workflows:
        say("aucun workflow à exécuter")
        return 2

    tmp = Path(tempfile.mkdtemp(prefix="comfy-smoke-"))
    out_dir, log_path = tmp / "output", tmp / "server.log"
    for d in ("temp", "user"):
        (tmp / d).mkdir()
    port = free_port()
    base = f"http://127.0.0.1:{port}"
    cmd = [sys.executable, "main.py", "--cpu", "--offline", "--disable-auto-launch", "--listen", "127.0.0.1", "--port", str(port),
           "--output-directory", str(out_dir), "--temp-directory", str(tmp / "temp"), "--user-directory", str(tmp / "user"),
           "--database-url", f"sqlite:///{tmp / 'assets.db'}"]
    log = open(log_path, "w")
    proc = subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    ok = False
    try:
        wait_ready(base, proc, time.time() + a.startup_timeout)
        say("serveur : démarré (CPU, --offline)")

        _, _, raw = http("GET", base + "/system_stats")
        sysinfo = json.loads(raw)["system"]
        assert sysinfo["installed_templates_version"] == sysinfo["required_templates_version"], "templates : version inattendue"
        for pkg in sysinfo["comfy_package_versions"]:
            assert pkg["installed"] == pkg["required"], f"paquet {pkg['name']} : {pkg['installed']} != {pkg['required']}"
        say(f"versions : ComfyUI {sysinfo['comfyui_version']}, frontend {sysinfo['required_frontend_version']}, templates {sysinfo['installed_templates_version']}")

        status, headers, body = http("GET", base + "/")
        assert status == 200 and b"<html" in body.lower(), "le frontend embarqué n'est pas servi"
        csp = {k.lower(): v for k, v in headers.items()}.get("content-security-policy", "")
        assert csp, "--offline devrait poser une politique CSP"
        say("frontend : servi depuis le paquet embarqué, CSP restrictive présente")

        _, _, raw = http("GET", base + "/object_info", timeout=60)
        nodes = json.loads(raw)
        missing = [n for n in REQUIRED_NODES if n not in nodes]
        assert not missing, f"nœuds absents : {missing}"
        partner = [n for n, info in nodes.items() if info.get("api_node")]
        assert not partner, f"des nœuds partenaires sont actifs malgré --offline : {partner[:3]}"
        say(f"nœuds : {len(nodes)} enregistrés, aucun nœud partenaire")

        for path in workflows:
            name = Path(path).name
            n = run_workflow(base, name, json.loads(Path(path).read_text()), out_dir, timeout=a.workflow_timeout)
            say(f"workflow : {name} OK ({n} image(s))")

        server_log = log_path.read_text(errors="replace")
        for marker in ("IMPORT FAILED", "Traceback (most recent call last)"):
            assert marker not in server_log, f"le journal du serveur contient « {marker} »"
        say("journal : aucune erreur d'import ni trace d'exception")
        ok = True
    except (AssertionError, RuntimeError, urllib.error.URLError, OSError, KeyError, ValueError) as e:
        say(f"ÉCHEC : {type(e).__name__}: {e}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()
        log.close()
        if not ok:
            say("---- fin du journal serveur ----")
            say("\n".join(log_path.read_text(errors="replace").splitlines()[-30:]))
        if a.keep_output and out_dir.exists():
            shutil.copytree(out_dir, a.keep_output, dirs_exist_ok=True)
            say(f"sorties copiées dans {a.keep_output}")
        shutil.rmtree(tmp, ignore_errors=True)
    say("smoke : OK" if ok else "smoke : ÉCHEC")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
