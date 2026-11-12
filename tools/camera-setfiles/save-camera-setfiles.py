#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Save the J714s front camera's IMX958 tuning files (ISP setfiles) from macOS.

Run on the Mac's macOS (27.3 or newer):  python3 save-camera-setfiles.py [OUTDIR]
It reads Apple's camera daemon and writes apple/isp_2224_01XX.dat and
apple/isp_2226_02XX.dat into OUTDIR (default ./camera-firmware). Copy that apple/
folder into /usr/lib/firmware/ on the J714s's Linux before running
tools/install-image/install-from-linux.sh, which then packs them into the image's
vendor firmware. Without them the camera still streams, but grainy and colour-cast.

The extraction is omacom/omarchy-mac-installer#208 by Eduard Moldovan (edimoldovan),
Engine/overlay/src/omarchy_isp.py, cut down to the IMX958 entries. Nothing is uploaded.
"""
import struct
import sys
from collections import namedtuple
from pathlib import Path

SetFile = namedtuple("SetFile", "magic name size")
KNOWN = {
    0x22240106: SetFile(0x22240106, "2224_01XX", 0x6FF4),  # IMX958
    0x22260201: SetFile(0x22260201, "2226_02XX", 0x6FF4),  # IMX958 build rev 2 (M5 Max J714c, M5 Pro J714s)
}
ALIGNMENT = 0x1000
SEARCH = ("/usr/libexec", "/usr/sbin", "/System/Library/PrivateFrameworks", "/System/Library/Frameworks")


def valid_header(h):
    return (h[2] == h[3] == h[6] == 0 and h[4] != 0 and h[4] & 0xFF000000 == h[4]
            and h[5] != 0 and h[5] & 0xFFFF0000 == h[5] and h[7] == 0x03C00000)


def extract(data):
    files = {}
    for off in range(0, len(data) - 31, ALIGNMENT):
        h = struct.unpack_from(">8I", data, off)
        if not valid_header(h) or h[0] not in KNOWN:
            continue
        e = KNOWN[h[0]]
        size = (e.size + 63) & ~63
        if off + size > len(data):
            sys.exit(f"truncated setfile {e.name} at {off:#x}")
        name = f"apple/isp_{e.name}.dat"
        blob = bytes(data[off:off + size])
        if name in files and files[name] != blob:
            sys.exit(f"conflicting copies of {name}")
        files[name] = blob
    return files


def find_daemon():
    for root in SEARCH:
        for p in Path(root).rglob("appleh16camerad"):
            if p.is_file():
                return p
    return None


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "camera-firmware")
    daemon = find_daemon()
    if not daemon:
        sys.exit("appleh16camerad not found; run this on the Mac's macOS")
    files = extract(daemon.read_bytes())
    if not files:
        sys.exit(f"no IMX958 setfiles found in {daemon}")
    for name, blob in sorted(files.items()):
        dst = out / name
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(blob)
        print(f"{dst}  ({len(blob)} bytes)")
    print(f"from {daemon}. Copy {out}/apple/ into /usr/lib/firmware/ on the J714s's Linux.")


if __name__ == "__main__":
    main()
