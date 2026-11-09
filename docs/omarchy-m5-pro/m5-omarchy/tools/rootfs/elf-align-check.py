#!/usr/bin/env python3
"""Report ELF files whose PT_LOAD p_align < 16 KiB (they can't load on a 16K-page kernel). Usage: elf-align-check.py DIR"""
import os, struct, sys
bad, n = [], 0
for root, _, files in os.walk(sys.argv[1]):
    for f in files:
        p = os.path.join(root, f)
        if os.path.islink(p) or not os.path.isfile(p): continue
        try:
            with open(p, 'rb') as fh:
                h = fh.read(64)
                if h[:4] != b'\x7fELF' or h[4] != 2 or h[5] != 1: continue
                if struct.unpack_from('<H', h, 18)[0] != 183: continue      # EM_AARCH64
                if struct.unpack_from('<H', h, 16)[0] not in (2, 3): continue  # EXEC/DYN only (skip .ko)
                phoff, = struct.unpack_from('<Q', h, 32); phentsize, phnum = struct.unpack_from('<HH', h, 54)
                fh.seek(phoff); ph = fh.read(phentsize * phnum)
        except OSError:
            continue
        n += 1
        aligns = [struct.unpack_from('<Q', ph, i * phentsize + 48)[0] for i in range(phnum)
                  if struct.unpack_from('<I', ph, i * phentsize)[0] == 1]
        if aligns and min(aligns) < 0x4000: bad.append((min(aligns), p[len(sys.argv[1]):]))
print(f"aarch64 EXEC/DYN ELF files scanned: {n}; with PT_LOAD align < 16K: {len(bad)}")
for a, p in sorted(bad)[:40]: print(f"  align 0x{a:x}  {p}")
