#!/usr/bin/env python3
"""Replace one file's contents inside a gzipped newc cpio, keeping all other
entries (device nodes, modes, owners) byte-identical.

patch_initrd.py IN.gz OUT.gz PATH OLD NEW   (OLD must occur exactly once in PATH)
"""
import gzip
import sys

src, dst, path, old, new = sys.argv[1:6]
data = gzip.decompress(open(src, "rb").read())
out, off, hit = bytearray(), 0, False
pad = lambda n: (4 - n % 4) % 4
while off < len(data):
    hdr = data[off:off + 110]
    assert hdr[:6] == b"070701", f"bad newc magic at {off}"
    f = [int(hdr[6 + 8 * i:14 + 8 * i], 16) for i in range(13)]
    namesize, filesize = f[11], f[6]
    name_end = off + 110 + namesize
    name = data[off + 110:name_end - 1].decode()
    body_off = name_end + pad(110 + namesize)
    body = data[body_off:body_off + filesize]
    nxt = body_off + filesize + pad(filesize)
    if name == path:
        assert body.count(old.encode()) == 1, "OLD must occur exactly once"
        body = body.replace(old.encode(), new.encode())
        hdr = hdr[:54] + b"%08X" % len(body) + hdr[62:]
        hit = True
    out += hdr + data[off + 110:body_off] + body + b"\0" * pad(len(body))
    off = nxt
    if name == "TRAILER!!!":
        out += data[off:]
        break
assert hit, f"{path} not found"
open(dst, "wb").write(gzip.compress(bytes(out), 9))
print(f"patched {path}; {len(out)} bytes uncompressed")
