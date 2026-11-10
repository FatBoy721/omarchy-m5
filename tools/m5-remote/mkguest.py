#!/usr/bin/env python3
"""Build a self-contained m1n1 guest payload (no ESP reads).

mkguest.py OUT --loader cpu.bin --dtb X.dtb --kernel Image.gz --initrd initrd.gz
           [--add-args "..."] [--allow-extra fpwm0,...]
Takes the m1n1 binary from --loader (everything before its 'boot=' config),
keeps its chosen.* config lines, appends DTB, kernel and initramfs.
"""
import argparse
import re

ap = argparse.ArgumentParser()
ap.add_argument("out")
ap.add_argument("--loader", required=True)
ap.add_argument("--dtb", required=True)
ap.add_argument("--kernel", required=True)
ap.add_argument("--initrd", required=True)
ap.add_argument("--add-args", default="")
ap.add_argument("--allow-extra", default="")
a = ap.parse_args()

b = open(a.loader, "rb").read()
i = b.find(b"boot=c3d4")
assert i > 0, "no boot= config in loader"
binary, cfg = b[:i], b[i:].decode()
lines = [l for l in cfg.split("\n") if l.startswith("chosen.")]
for n, l in enumerate(lines):
    if l.startswith("chosen.bootargs="):
        if a.allow_extra:
            l = re.sub(r"(m5_pmgr_allow=\S+)", r"\1," + a.allow_extra, l)
        if a.add_args:
            l += " " + a.add_args
        lines[n] = l
        print(l[:420])
out = binary + ("\n".join(lines) + "\n").encode()
out += open(a.dtb, "rb").read() + open(a.kernel, "rb").read()
rd = open(a.initrd, "rb").read()
out += b"m1n1_initramfs" + len(rd).to_bytes(4, "little") + rd
open(a.out, "wb").write(out)
print(a.out, len(out), "bytes")
