#!/usr/bin/env python3
"""Append the m5boot payload (header + dtb + Image + initrd) to m5boot code. See src/payload.h."""
import argparse, struct

def pad(b, a=64): return b + b'\0' * (-len(b) % a)

def build(code, dtb, image, initrd=b''):
    out = pad(code)
    blobs, off, offs = b'', 64, []
    for b in (dtb, image, initrd):
        offs += [off if b else 0, len(b)]
        blobs += pad(b); off += len(pad(b))
    hdr = b'M5BOOTPL' + struct.pack('<II6Q', 2, 64, *offs)
    trailer = b'M5PLEND!' + struct.pack('<Q', off)
    return pad(out + pad(hdr) + blobs + trailer, 0x4000)   # task 07 H-ALIGN: file size % 16 KiB == 0 (zeros after the trailer)

def parse(blob, code_len):
    h = blob[(code_len + 63) & ~63:]
    assert h[:8] == b'M5BOOTPL'
    v, hs, *f = struct.unpack_from('<II6Q', h, 8)
    assert v == 2 and hs == 64
    t = max([64] + [f[2*i] + f[2*i+1] for i in range(3) if f[2*i+1]]); t = (t + 63) & ~63
    assert h[t:t+8] == b'M5PLEND!' and struct.unpack_from('<Q', h, t + 8)[0] == t
    return {k: h[f[2*i]:f[2*i]+f[2*i+1]] for i, k in enumerate(('dtb', 'image', 'initrd'))}

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('code'); ap.add_argument('dtb'); ap.add_argument('image')
    ap.add_argument('--initrd'); ap.add_argument('-o', required=True)
    a = ap.parse_args()
    rd = lambda p: open(p, 'rb').read() if p else b''
    img = rd(a.image)
    if img[:2] == b'\x1f\x8b':   # Image.gz: m5boot inflates it (src/inflate.c); check the inner header here
        import gzip; inner = gzip.decompress(img)[:64]
    else: inner = img
    assert inner[0x38:0x3c] == b'ARM\x64', 'Image: bad arm64 magic (booting.rst)'
    open(a.o, 'wb').write(build(rd(a.code), rd(a.dtb), img, rd(a.initrd)))
