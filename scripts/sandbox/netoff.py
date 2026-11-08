#!/usr/bin/env python3
"""Lance une commande dans un espace réseau SANS Internet (seul le loopback 127.0.0.1 fonctionne).

    python3 scripts/sandbox/netoff.py -- python main.py --cpu --offline

Prouve qu'une commande n'a besoin d'aucun réseau : `unshare -rn` coupe tout, puis on remonte `lo`
(le sandbox n'a pas la commande `ip`). Si `unshare` est refusé, le script s'arrête au lieu de lancer la commande
avec du réseau (jamais de faux positif).
"""
import fcntl
import os
import socket
import struct
import sys

SIOCSIFFLAGS, SIOCGIFFLAGS, IFF_UP = 0x8914, 0x8913, 0x1


def lo_up():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    ifr = struct.pack("16sH14x", b"lo", 0)
    flags = struct.unpack("16sH14x", fcntl.ioctl(s, SIOCGIFFLAGS, ifr))[1]
    fcntl.ioctl(s, SIOCSIFFLAGS, struct.pack("16sH14x", b"lo", flags | IFF_UP))


def main():
    if "--" not in sys.argv:
        sys.exit("usage : netoff.py -- commande [args...]")
    cmd = sys.argv[sys.argv.index("--") + 1:]
    if os.environ.get("NETOFF_INNER") != "1":
        os.environ["NETOFF_INNER"] = "1"
        os.execvp("unshare", ["unshare", "-rn", sys.executable, os.path.abspath(__file__), "--"] + cmd)
    lo_up()
    try:
        socket.create_connection(("1.1.1.1", 443), timeout=2).close()
    except OSError:
        pass
    else:
        sys.exit("le réseau n'est pas coupé : abandon")
    os.execvp(cmd[0], cmd)


if __name__ == "__main__":
    main()
