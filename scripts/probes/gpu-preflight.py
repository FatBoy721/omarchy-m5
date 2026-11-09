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


def properties(node):
    return {prop["name"]: prop["value"] for prop in node["properties"]}


def child(node, name):
    matches = [c for c in node["children"]
               if properties(c).get("name", b"").split(b"\0", 1)[0] == name.encode("ascii")]
    if len(matches) != 1:
        raise SystemExit(f"GPU preflight: expected one ADT child {name!r}")
    return matches[0]


def validate(data):
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
    for name, expected in PERF_SHA256.items():
        actual = hashlib.sha256(sgx.get(name, b"")).hexdigest()
        if actual != expected:
            raise SystemExit(f"GPU preflight: {name} differs from this trial's voltage bins ({actual})")
    print(f"GPU preflight PASS: {model}, {FIRMWARE}, all four raw voltage tables match")
    print("GPU firmware image identity still requires kernel admission; no GPU execution performed.")


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
    args = parser.parse_args()
    data = args.adt.read_bytes() if args.adt else capture()
    if args.save:
        with args.save.open("xb") as output:
            output.write(data)
        print(f"Saved private ADT: {args.save} (SHA256 {hashlib.sha256(data).hexdigest()})")
    validate(data)


if __name__ == "__main__":
    main()
