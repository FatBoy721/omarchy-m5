#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check this GPU trial's device-specific bins before handing off to Linux.

Run hv/gpu-preflight.py from the GPU tether bundle. --adt checks a saved capture;
--save writes a new private capture, refusing to overwrite an existing file.
Live mode reads boot arguments and the ADT in RAM, without m1n1.setup,
ProxyUtils, PMU reset, heap changes, MMIO scans or power-controller writes.
Firmware-version metadata is not image attestation: the kernel must still
accept the actual loaded GPU firmware through its exact-image identity check.
"""
import argparse
import hashlib
import os
from pathlib import Path
import struct
import sys

sys.path.append(str(Path(__file__).resolve().parents[1] / "proxyclient"))
from m1n1.adt import ADTNodeStruct

MODEL = "Mac17,9"
FIRMWARE = "mBoot-20457.60.65.0.1"
PERF_SHA256 = {
    "perf-states": "278d7f6a40883c74cc53c7f24d852677c254b75ebf93d4cb2decb548a5466911",
    "perf-states-sram": "b22318df8b6b06b090745c2114aca68a6a34d41c02c723c2a2627b6abbcda027",
    "afr-perf-states": "3db7509b5e5f37f47a9332291a075cbd3ba39bab26fccff05e36ca22c2785c15",
    "cs-perf-states": "3db7509b5e5f37f47a9332291a075cbd3ba39bab26fccff05e36ca22c2785c15",
}

# TripleU613's J714s (owner ADT d7feb012...): the kernel's J714S_TRIPLEU tables,
# as (MHz, core0, core1, sram0, sram1) mV and auxiliary (MHz, core, sram) mV.
TRIPLEU_MAIN = [(0, 125, 125, 775, 775), (338, 590, 590, 775, 775), (486, 620, 620, 775, 775),
                (636, 655, 655, 775, 775), (796, 705, 705, 775, 775), (888, 730, 730, 775, 775),
                (988, 760, 760, 775, 775), (1084, 785, 785, 785, 785), (1182, 800, 800, 800, 800),
                (1278, 840, 840, 840, 840), (1374, 880, 865, 880, 865), (1470, 925, 910, 925, 910),
                (1578, 1000, 985, 1000, 985), (1620, 1025, 1010, 1025, 1010)]
TRIPLEU_AUX = [(24, 125, 775), (338, 600, 775), (486, 635, 775), (636, 640, 775), (796, 680, 775),
               (888, 700, 775), (988, 740, 775), (1084, 765, 775), (1182, 790, 790),
               (1278, 830, 830), (1374, 860, 860), (1470, 895, 895), (1578, 955, 955),
               (1620, 985, 985)]


def decode_bins(sgx):
    """Decode the live sgx voltage tables the way the kernel table was derived."""
    rows = lambda name: list(struct.iter_unpack("<II", sgx[name]))
    core, sram = rows("perf-states"), rows("perf-states-sram")
    if len(core) != 28 or len(sram) != 28:
        raise SystemExit("GPU preflight: unexpected perf-states shape")
    main = [(core[i][0] // 10**6, core[i][1], core[i + 14][1], sram[i][1], sram[i + 14][1])
            for i in range(14)]
    aux_data = sgx["afr-perf-states"]
    aux = list(struct.iter_unpack("<QQ", aux_data[16:-8]))
    return main, [(f // 10**6, v // 1000, max(775, v // 1000)) for v, f in aux]


def properties(node):
    return {prop["name"]: prop["value"] for prop in node["properties"]}


def child(node, name):
    matches = [c for c in node["children"]
               if properties(c).get("name", b"").split(b"\0", 1)[0] == name.encode("ascii")]
    if len(matches) != 1:
        raise SystemExit(f"GPU preflight: expected one ADT child {name!r}")
    return matches[0]


def validate(data, unit="betizzel"):
    root = ADTNodeStruct.parse(data)
    model = properties(root).get("model", b"").split(b"\0", 1)[0].decode("ascii")
    if model != MODEL:
        raise SystemExit(f"GPU preflight: model {model!r} is not {MODEL}")
    chosen = properties(child(root, "chosen"))
    for name in ("firmware-version", "system-firmware-version"):
        value = chosen.get(name, b"").split(b"\0", 1)[0].decode("ascii")
        if value != FIRMWARE:
            raise SystemExit(f"GPU preflight: {name} {value!r} differs from {FIRMWARE}")
    sgx = properties(child(child(root, "arm-io"), "sgx"))
    if unit == "tripleu":
        main, aux = decode_bins(sgx)
        if main != TRIPLEU_MAIN or aux != TRIPLEU_AUX:
            raise SystemExit(f"GPU preflight: live bins differ from J714S_TRIPLEU\n main={main}\n aux={aux}")
        print(f"GPU preflight PASS: {model}, {FIRMWARE}, live bins equal the kernel's J714S_TRIPLEU")
        return root
    for name, expected in PERF_SHA256.items():
        actual = hashlib.sha256(sgx.get(name, b"")).hexdigest()
        if actual != expected:
            raise SystemExit(f"GPU preflight: {name} differs from this trial's voltage bins ({actual})")
    print(f"GPU preflight PASS: {model}, {FIRMWARE}, all four raw voltage tables match")
    print("GPU firmware image identity still requires kernel admission; no GPU execution performed.")
    return root


def capture():
    from m1n1.proxy import M1N1Proxy, UartInterface
    from m1n1.tgtypes import BootArgs_r1, BootArgs_r2, BootArgs_r3

    iface = UartInterface(os.environ.get("M1N1DEVICE", "/dev/m1n1"))
    try:
        iface.nop()  # Negotiate the serial protocol, not a hardware setup sequence.
        proxy = M1N1Proxy(iface)
        address, revision = proxy.get_bootargs_rev()
        layouts = {0: BootArgs_r1, 1: BootArgs_r1, 2: BootArgs_r2, 3: BootArgs_r3}
        if revision not in layouts:
            raise SystemExit(f"GPU preflight: unsupported boot-argument revision {revision}")
        args = iface.readstruct(address, layouts[revision])
        base = (args.devtree - args.virt_base + args.phys_base) & 0xffffffffffffffff
        size = args.devtree_size
        if not (0 < size <= 16 * 1024 * 1024 and
                args.phys_base <= base < base + size <= args.phys_base + args.mem_size):
            raise SystemExit("GPU preflight: ADT is outside the boot-argument RAM bounds")
        return iface.readmem(base, size)
    finally:
        iface.dev.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adt", type=Path, help="check saved ADT without connecting to hardware")
    parser.add_argument("--save", type=Path, help="save raw ADT privately; never overwrite")
    parser.add_argument("--unit", choices=("betizzel", "tripleu"), default="betizzel",
                        help="which J714s unit's GPU voltage bins the kernel DTB selects")
    args = parser.parse_args()
    data = args.adt.read_bytes() if args.adt else capture()
    if args.save:
        with args.save.open("xb") as output:
            output.write(data)
        print(f"Saved private ADT: {args.save} (SHA256 {hashlib.sha256(data).hexdigest()})")
    validate(data, args.unit)


if __name__ == "__main__":
    main()
