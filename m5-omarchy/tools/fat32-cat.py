#!/usr/bin/env python3
"""fat32-cat.py IMAGE OFFSET [PATH]: list a FAT32 directory or print a file from a disk image, read-only, stdlib only.
OFFSET = byte offset of the FAT32 partition in IMAGE. PATH like m5log or m5log/boot-1.txt (case-insensitive).
Used for the VM ESP (no mtools/loop mounts needed). Handles long file names; no write support by design."""
import struct, sys

def main():
    img, off = sys.argv[1], int(sys.argv[2], 0)
    path = [p for p in (sys.argv[3] if len(sys.argv) > 3 else "").split("/") if p]
    f = open(img, "rb")
    def rd(o, n):
        f.seek(off + o); return f.read(n)
    bs = rd(0, 512)
    bps, spc = struct.unpack_from("<HB", bs, 11)
    rsv, nf = struct.unpack_from("<H", bs, 14)[0], bs[16]
    fsz, root = struct.unpack_from("<I", bs, 36)[0], struct.unpack_from("<I", bs, 44)[0]
    fat, cs = rsv * bps, bps * spc
    data = fat + nf * fsz * bps
    def chain(c):
        while 2 <= c < 0x0FFFFFF8:
            yield c
            c = struct.unpack_from("<I", rd(fat + 4 * c, 4))[0] & 0x0FFFFFFF
    def ls(c):
        out, lfn = [], ""
        for cl in chain(c):
            d = rd(data + (cl - 2) * cs, cs)
            for i in range(0, cs, 32):
                e = d[i:i + 32]
                if e[0] == 0:
                    return out
                if e[0] == 0xE5:
                    lfn = ""; continue
                if e[11] == 0x0F:
                    lfn = (e[1:11] + e[14:26] + e[28:32]).decode("utf-16le", "ignore").split("\x00")[0] + lfn
                    continue
                name = lfn or (e[0:8].decode().strip() + ("." + e[8:11].decode().strip() if e[8:11].strip() else ""))
                lfn = ""
                clus = (struct.unpack_from("<H", e, 20)[0] << 16) | struct.unpack_from("<H", e, 26)[0]
                out.append((name, clus, struct.unpack_from("<I", e, 28)[0], bool(e[11] & 0x10)))
        return out
    cur, isdir, size = root, True, 0
    for p in path:
        hit = [x for x in ls(cur) if x[0].lower() == p.lower()]
        if not hit:
            sys.exit(f"{p}: not found")
        _, cur, size, isdir = hit[0]
    if isdir:
        for n, _, s, d in ls(cur):
            if n not in (".", ".."):
                print(f"{'DIR' if d else s:>10}  {n}")
    else:
        sys.stdout.buffer.write(b"".join(rd(data + (c - 2) * cs, cs) for c in chain(cur))[:size])

if __name__ == "__main__":
    main()
