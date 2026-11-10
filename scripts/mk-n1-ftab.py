#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build the N1 (Centauri) firmware file the Linux driver loads.

The driver requests apple/centauri/<target>-ftab.bin: Apple's RTKit FTAB for
the N1 with the board's static Image4 manifest stored as the FTAB ticket.
Both inputs are plain members of the matching macOS restore image:

    Firmware/t2026macG1/Release/ftab.bin
    Firmware/Manifests/restore/macOS Customer/centauri/centauri.<board>ap.im4m

The method (append the manifest after the last entry, store its offset and
length at 0x10/0x14) was worked out and published by rolotrealanis98
(m5pro-linux, contrib/pending/wireless/aurora-n1/w3). This is a separate
implementation that additionally checks the result against BuildManifest.plist.

Nothing here contacts Apple or a device. The manifest is the global one for
the board (no ECID, no nonce); a per-unit ticket is refused. The output is
Apple firmware: keep it private, never commit or publish it.

Usage:
    scripts/mk-n1-ftab.py --build-manifest BuildManifest.plist \\
        --device-class j714sap --ftab ftab.bin --im4m centauri.j714sap.im4m \\
        --out build/n1-fw/j714s-ftab.bin
Only sizes, counts and tag names are printed; no input or output digest.
"""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import struct
import sys

MAGIC = b"rkosftab"
MAX_SIZE = 64 << 20  # the driver accepts 0x30 <= size <= 64 MiB


class Refused(Exception):
    pass


def require(condition, message):
    if not condition:
        raise Refused(message)


def parse_ftab(data, what):
    require(len(data) >= 0x30 and data[0x20:0x28] == MAGIC, f"{what}: no {MAGIC.decode()} at 0x20")
    header = struct.unpack_from("<8I", data, 0)
    count, tail = struct.unpack_from("<2I", data, 0x28)
    table_end = 0x30 + 16 * count
    require(0 < count < 1024 and table_end <= len(data), f"{what}: bad entry count {count}")
    entries = {}
    spans = []
    for index in range(count):
        tag, offset, size, _ = struct.unpack_from("<4sIII", data, 0x30 + 16 * index)
        require(table_end <= offset and offset + size <= len(data),
                f"{what}: entry {index} lies outside the file")
        require(tag not in entries, f"{what}: duplicate entry tag")
        entries[tag] = (offset, size)
        spans.append((offset, offset + size))
    spans.sort()
    for (_, end), (start, _) in zip(spans, spans[1:]):
        require(start >= end, f"{what}: overlapping entries")
    return {"header": header, "tail": tail, "entries": entries, "table_end": table_end,
            "data_end": spans[-1][1], "ticket": (header[4], header[5])}


def der_read(data, pos, end):
    """One DER element at pos: (class/constructed byte, tag number, value start, value end)."""
    require(pos + 2 <= end, "manifest: truncated DER element")
    first = data[pos]
    pos += 1
    number = first & 0x1F
    if number == 0x1F:
        number = 0
        while True:
            require(pos < end, "manifest: truncated DER tag")
            byte = data[pos]
            pos += 1
            number = (number << 7) | (byte & 0x7F)
            if not byte & 0x80:
                break
    require(pos < end, "manifest: truncated DER length")
    length = data[pos]
    pos += 1
    if length & 0x80:
        width = length & 0x7F
        require(0 < width <= 4 and pos + width <= end, "manifest: bad DER length")
        length = int.from_bytes(data[pos:pos + width], "big")
        pos += width
    require(pos + length <= end, "manifest: DER element overruns its parent")
    return first, number, pos, pos + length


def der_children(data, start, end):
    items = []
    pos = start
    while pos < end:
        item = der_read(data, pos, end)
        items.append(item)
        pos = item[3]
    return items


def fourcc(number):
    require(number.bit_length() <= 32, "manifest: tag is not a four-character code")
    return number.to_bytes(4, "big")


def named_set(data, element):
    """A private [4CC] wrapper holding SEQUENCE { IA5String 4CC, payload }: (name, payload)."""
    first, number, start, end = element
    require(first & 0xE0 == 0xE0, "manifest: expected a private constructed tag")
    inner = der_children(data, start, end)
    require(len(inner) == 1 and inner[0][0] == 0x30, "manifest: malformed tagged sequence")
    parts = der_children(data, inner[0][2], inner[0][3])
    require(len(parts) == 2 and parts[0][0] == 0x16, "manifest: malformed tagged sequence")
    name = data[parts[0][2]:parts[0][3]]
    require(name == fourcc(number), "manifest: tag and name disagree")
    return name, parts[1]


def properties(data, element):
    require(element[0] == 0x31, "manifest: expected a property set")
    result = {}
    for child in der_children(data, element[2], element[3]):
        name, value = named_set(data, child)
        require(name not in result, "manifest: duplicate property")
        result[name] = (value[0], data[value[2]:value[3]])
    return result


def parse_im4m(data):
    top = der_read(data, 0, len(data))
    require(top[0] == 0x30 and top[3] == len(data), "manifest: not a single DER sequence")
    parts = der_children(data, top[2], top[3])
    require(len(parts) >= 4 and parts[0][0] == 0x16 and data[parts[0][2]:parts[0][3]] == b"IM4M"
            and parts[2][0] == 0x31 and parts[3][0] == 0x04, "manifest: not an IM4M")
    body = [named_set(data, child) for child in der_children(data, parts[2][2], parts[2][3])]
    manb = [payload for name, payload in body if name == b"MANB"]
    require(len(manb) == 1 and manb[0][0] == 0x31, "manifest: no MANB")
    manp, images = None, {}
    for child in der_children(data, manb[0][2], manb[0][3]):
        name, payload = named_set(data, child)
        if name == b"MANP":
            require(manp is None, "manifest: duplicate MANP")
            manp = properties(data, payload)
        else:
            require(name not in images, "manifest: duplicate image")
            images[name] = properties(data, payload)
    require(manp is not None and images, "manifest: no MANP or no images")
    return manp, images


def integer(props, key):
    require(key in props and props[key][0] == 0x02, f"manifest: no integer {key.decode()}")
    return int.from_bytes(props[key][1], "big")


def boolean(props, key):
    require(key in props and props[key][0] == 0x01 and len(props[key][1]) == 1,
            f"manifest: no boolean {key.decode()}")
    return props[key][1] != b"\x00"


def expected_identity(path, device_class):
    """Wireless1 chip, board, firmware path and component digests of every matching identity."""
    with path.open("rb") as stream:
        manifest = plistlib.load(stream)
    found = None
    for identity in manifest.get("BuildIdentities", ()):
        if identity.get("Info", {}).get("DeviceClass", "").lower() != device_class:
            continue
        components = {name: entry for name, entry in identity.get("Manifest", {}).items()
                      if name.startswith("Wireless1,")}
        paths = {entry.get("Info", {}).get("Path") for entry in components.values()}
        digests = {entry.get("Digest") for entry in components.values()}
        require(components and len(paths) == 1 and all(isinstance(d, bytes) for d in digests),
                "BuildManifest: unusable Wireless1 components")
        current = (identity.get("Wireless1,ChipID"), identity.get("Wireless1,BoardID"),
                   paths.pop(), frozenset(digests), len(components))
        require(found is None or found == current,
                "BuildManifest: the board's identities disagree about Wireless1")
        found = current
    require(found is not None, f"BuildManifest: no identity for device class {device_class}")
    require(isinstance(found[0], int) and isinstance(found[1], int),
            "BuildManifest: no Wireless1 chip or board ID")
    return {"version": manifest.get("ProductVersion"), "build": manifest.get("ProductBuildVersion"),
            "chip": found[0], "board": found[1], "path": found[2], "digests": found[3],
            "components": found[4]}


def build(args):
    expected = expected_identity(args.build_manifest, args.device_class.lower())
    print(f"BuildManifest: {expected['version']} ({expected['build']}), {args.device_class}: "
          f"Wireless1 chip 0x{expected['chip']:x} board 0x{expected['board']:x}, "
          f"{expected['components']} components in {expected['path']}")
    require(args.ftab.as_posix().endswith(expected["path"]),
            f"--ftab is not the restore image member {expected['path']}")

    ftab = args.ftab.read_bytes()
    im4m = args.im4m.read_bytes()
    source = parse_ftab(ftab, "input")
    require(source["ticket"] == (0, 0), "input already carries a ticket")
    require(not any(source["header"][2:]) and not source["tail"],
            "input header has unknown nonzero fields")
    require(source["data_end"] == len(ftab) and len(ftab) % 4 == 0,
            "input has trailing bytes or is not 4-byte aligned")

    manp, images = parse_im4m(im4m)
    for key in (b"ECID", b"BNCH", b"snon", b"Nonc"):
        require(key not in manp, f"manifest carries {key.decode()}: a per-unit ticket, refused")
    require(integer(manp, b"CHIP") == expected["chip"] and integer(manp, b"BORD") == expected["board"],
            "manifest chip/board are not the ones BuildManifest selects for this board")
    require(boolean(manp, b"CPRO") and boolean(manp, b"CSEC"),
            "manifest is not the production variant (use the plain .im4m, not .dev/.insecure)")

    signed = set()
    for tag, props in images.items():
        require(b"DGST" in props and len(props[b"DGST"][1]) == 48, "manifest image has no SHA-384")
        require(tag in source["entries"], f"manifest image {tag.decode('latin1')} is not in the FTAB")
        offset, size = source["entries"][tag]
        require(hashlib.sha384(ftab[offset:offset + size]).digest() == props[b"DGST"][1],
                f"FTAB entry {tag.decode('latin1')} does not match the manifest")
        signed.add(props[b"DGST"][1])
    require(signed == expected["digests"],
            "manifest images are not exactly the components BuildManifest lists")
    print(f"manifest: global (no ECID or nonce), production, {len(images)} images match their "
          f"FTAB entries and the {len(expected['digests'])} distinct BuildManifest digests")
    print(f"ftab: {len(ftab)} bytes, {len(source['entries'])} entries, "
          f"{len(source['entries']) - len(images)} not covered by the manifest")

    header = bytearray(ftab[:0x30])
    struct.pack_into("<II", header, 0x10, len(ftab), len(im4m))
    output = bytes(header) + ftab[0x30:] + im4m

    result = parse_ftab(output, "output")
    require(result["entries"] == source["entries"] and result["ticket"] == (len(ftab), len(im4m))
            and output[len(ftab):] == im4m and output[:0x10] == ftab[:0x10]
            and output[0x18:len(ftab)] == ftab[0x18:], "output differs beyond the ticket fields")
    require(0x30 <= len(output) <= MAX_SIZE, "output fails the driver's size check")

    out = args.out
    require(not out.exists() or args.force, f"{out} exists; pass --force to replace it")
    out.parent.mkdir(parents=True, exist_ok=True)
    temporary = out.with_name(out.name + ".tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(output)
    os.replace(temporary, out)
    require(out.read_bytes() == output, "readback differs")
    print(f"wrote {out}: {len(output)} bytes (ticket at 0x{len(ftab):x}, {len(im4m)} bytes), mode 0600")
    print("Apple firmware: private input for /lib/firmware only. Do not commit or publish.")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--build-manifest", type=Path, required=True)
    parser.add_argument("--device-class", required=True, help="for example j714sap")
    parser.add_argument("--ftab", type=Path, required=True)
    parser.add_argument("--im4m", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--force", action="store_true", help="replace an existing output")
    args = parser.parse_args()
    try:
        build(args)
    except (Refused, OSError, plistlib.InvalidFileException) as error:
        print(f"REFUSED: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
