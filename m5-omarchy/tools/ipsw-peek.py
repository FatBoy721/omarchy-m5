#!/usr/bin/env python3
"""ipsw-peek.py URL [member]: list an IPSW's zip members, or fetch one member, via HTTP range requests (stdlib only).
With no member: prints the BuildManifest identities for --board (default j714sap) and AEA-ness of their BaseSystem/RestoreRamDisk.
Usage: ipsw-peek.py URL [--board j714sap] [--get MEMBER OUT]"""
import plistlib, struct, sys, urllib.request, zlib

def rng(url, a, b):
    r = urllib.request.Request(url, headers={"Range": f"bytes={a}-{b}", "User-Agent": "ipsw-peek"})
    with urllib.request.urlopen(r) as f:
        return f.read()

def size(url):
    r = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "ipsw-peek"})
    with urllib.request.urlopen(r) as f:
        return int(f.headers["Content-Length"])

def central(url):
    n = size(url)
    tail = rng(url, n - 65536, n - 1)
    i = tail.rfind(b"PK\x06\x06")                     # zip64 EOCD (IPSWs are > 4 GiB)
    if i >= 0:
        cd_size, cd_off = struct.unpack_from("<QQ", tail, i + 40)
    else:
        i = tail.rfind(b"PK\x05\x06")
        cd_size, cd_off = struct.unpack_from("<II", tail, i + 12)
    cd, out, p = rng(url, cd_off, cd_off + cd_size - 1), {}, 0
    while p < len(cd) and cd[p:p+4] == b"PK\x01\x02":
        meth, = struct.unpack_from("<H", cd, p + 10)
        csz, usz = struct.unpack_from("<II", cd, p + 20)
        nl, el, cl = struct.unpack_from("<HHH", cd, p + 28)
        off, = struct.unpack_from("<I", cd, p + 42)
        name = cd[p+46:p+46+nl].decode()
        ex, q = cd[p+46+nl:p+46+nl+el], 0
        while q + 4 <= len(ex):                         # zip64 extra: replaces 0xffffffff fields in order
            hid, hl = struct.unpack_from("<HH", ex, q)
            if hid == 1:
                vals, k = [], q + 4
                for v in (usz, csz, off):
                    if v == 0xffffffff:
                        vals.append(struct.unpack_from("<Q", ex, k)[0]); k += 8
                    else:
                        vals.append(v)
                usz, csz, off = vals
            q += 4 + hl
        out[name] = (meth, csz, usz, off)
        p += 46 + nl + el + cl
    return out

def get(url, ent, limit=None):
    meth, csz, usz, off = ent
    h = rng(url, off, off + 29)
    nl, el = struct.unpack_from("<HH", h, 26)
    start = off + 30 + nl + el
    n = csz if limit is None else min(csz, limit)
    data = rng(url, start, start + n - 1)
    return zlib.decompressobj(-15).decompress(data) if meth == 8 else data

def main():
    a = sys.argv[1:]
    url = a.pop(0)
    board = a[a.index("--board") + 1] if "--board" in a else "j714sap"
    cd = central(url)
    if "--get" in a:
        m, o = a[a.index("--get") + 1], a[a.index("--get") + 2]
        open(o, "wb").write(get(url, cd[m])); return
    bm = plistlib.loads(get(url, cd["BuildManifest.plist"]))
    print("ProductVersion", bm.get("ProductVersion"), "Build", bm.get("ProductBuildVersion"))
    for idn in bm["BuildIdentities"]:
        info = idn["Info"]
        if info.get("DeviceClass") != board:
            continue
        print(f"\n{info['Variant']} / {info['RestoreBehavior']}  board {idn['ApBoardID']} chip {idn['ApChipID']}")
        for k in ("iBoot", "LLB", "iBEC", "BaseSystem", "RestoreRamDisk", "KernelCache"):
            if k in idn["Manifest"]:
                p = idn["Manifest"][k]["Info"]["Path"]
                ent = cd.get(p)
                print(f"  {k:14s} {p}  {ent[2] if ent else '?'} B")
        for k in ("BaseSystem",):
            p = idn["Manifest"].get(k, {}).get("Info", {}).get("Path")
            if p in cd:
                head = get(url, cd[p], limit=4096)[:4]
                print(f"  {k} first bytes: {head!r} ({'AEA-encrypted' if head == b'AEA1' else 'plain'})")

if __name__ == "__main__":
    main()
