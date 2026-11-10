#!/usr/bin/env python3
"""Catch the Mac's m1n1 USB proxy during boot and take control.

Usage: m5catch.py [--timeout S] (info|reboot)
  info   : hold m1n1 in proxy, print boot-args revision, then reboot it (no chainload)
  reboot : grab the proxy and reboot the Mac immediately
Exit 2 if no proxy appeared within the timeout.
"""
import argparse, os, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "m1n1-proxy"))
ap = argparse.ArgumentParser()
ap.add_argument("action", choices=("info", "reboot"))
ap.add_argument("--timeout", type=float, default=180)
ap.add_argument("--dev", default="/dev/m1n1")
a = ap.parse_args()
t0 = time.time()
while not os.path.exists(a.dev):
    if time.time() - t0 > a.timeout:
        sys.exit(f"no m1n1 proxy within {a.timeout:.0f}s") or 2
    time.sleep(0.02)
from m1n1.proxy import UartInterface, M1N1Proxy
iface = UartInterface(a.dev)
iface.nop()                      # opening CDC keeps m1n1 in the proxy
p = M1N1Proxy(iface)
print(f"caught m1n1 proxy after {time.time()-t0:.1f}s; bootargs {p.get_bootargs_rev()}", flush=True)
p.reboot()
print("reboot sent", flush=True)
