#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compile and run the loader's actual N1 hand-off (src/kboot_n1.c) on the host.

Offline only: no m1n1.setup, proxy, MMIO, USB, SSH or target execution.
kboot_n1.c is compiled verbatim (its #include lines replaced by a host prelude)
and linked to the same source tree's libfdt. ADT lookups are served from a
saved runtime ADT through m1n1.adt; device trees are the real compiled DTBs.

Checks: the N1 DTB gets the control identity, all six host lists and the
port/DART pair enabled; a DTB whose host is disabled is left byte-identical;
every missing precondition or unusable ADT record leaves port and DART disabled.
Tree side of the same contract: only the N1 tree raises the GP power closure the
kernel train needs, and PERST#'s pin bank never exposes the pin that faults.

Usage: python patches/m1n1-gpu/smoke-n1.py --adt SAVED.bin --n1-dtb N1.dtb
       --inert-dtb GPU.dtb [--source build/m1n1-gpu-n1] [--cc cc]
"""
import argparse
import ctypes as C
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

PATHS = ("/", "/chosen", "/arm-io/apcie0", "/arm-io/apcie0/pci-bridge0")
KEEP = {"/": ("target-type",), "/chosen": ("board-id", "chip-id")}
# ADT list -> (DT property, DT host window, offset added): pcie-apple.c's own table
HOST_LISTS = (
    ("apcie-axi2af-tunables", "apple,tunable-axi2af", "axi2af", 0),
    ("apcie-cio3pllcore-tunables", "apple,tunable-cio3pllcore", "pcieclkgen", 0x2200),
    ("apcie-pcieclkgen-tunables", "apple,tunable-pcieclkgen", "pcieclkgen", 0),
    ("apcie-phy-tunables", "apple,tunable-phy", "phy-window", 0),
    ("apcie-phy-ip-pll-tunables", "apple,tunable-phy-ip-pll", "phy-ip", 0),
    ("apcie-phy-ip-auspma-tunables", "apple,tunable-phy-ip-auspma", "phy-ip", 0),
)
PORT_LISTS = ("apcie-config-tunables", "pcie-rc-tunables", "pcie-rc-gen3-shadow-tunables",
              "pcie-rc-gen4-shadow-tunables", "pcie-rc-gen5-shadow-tunables")
HOST = "/pcie@1cb0000000"
PORT = HOST + "/pci@0,0"
CONTROL = PORT + "/control@0,0"
DART = "/soc/iommu@410000000"
PINCTRL = "/soc/pinctrl@29c000000"
PMGR = "/soc/power-management@280900000/power-controller@"
# GP power closure the kernel train needs up: label, unit address, auto-PM off.
# iBoot leaves the three auto-PM ones targeted on but gated, and the shared
# PHY then never acknowledges its clock request (m1n1 pcie_t6050 stage A).
CLOSURE = (("apcie_gp", "118", False), ("apcie_sys_gp", "148", True),
           ("apcie_phy_sw", "1b0", True), ("aphy_gp_aus5_a", "258", False),
           ("aphy_gp_aus5", "280", True))
FAULTING_PIN = 112  # its register (0x29c0001c0) takes an SError when read

PRELUDE = r"""
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libfdt.h"
typedef uint64_t u64;
typedef uint32_t u32;
typedef uint8_t u8;
#define PACKED __attribute__((packed))
#define ARRAY_SIZE(x) (sizeof(x)/sizeof((x)[0]))
#define ADT_GETPROP(a,n,p,v) adt_getprop_copy(a,n,p,v,sizeof(*(v)))
"""


def fixture(tree):
    arrays, props = [], []
    for idx, path in enumerate(PATHS):
        node = tree if path == "/" else tree[path]
        for p in node.tostruct()["properties"]:
            if path in KEEP and p["name"] not in KEEP[path]:
                continue
            if path not in KEEP and "tunables" not in p["name"]:
                continue
            ident = f"prop_{len(props)}"
            arrays.append(f"static unsigned char {ident}[] = {{{','.join(map(str, p['value']))}}};")
            props.append(f'{{{idx}, "{p["name"]}", {ident}, {len(p["value"])}}}')
    return "\n".join(arrays) + """
struct prop { int node; const char *name; unsigned char *value; int len; };
static struct prop props[] = { %s };
static const char *paths[] = { %s };
static void *adt;
static int adt_path_offset(const void *unused, const char *name) {
    (void)unused;
    for (size_t i=0; i<ARRAY_SIZE(paths); i++) if (!strcmp(paths[i], name)) return i;
    return -1;
}
static struct prop *fixture_prop(int node, const char *name) {
    for (size_t i=0; i<ARRAY_SIZE(props); i++)
        if (props[i].node==node && !strcmp(props[i].name,name)) return &props[i];
    return NULL;
}
static const void *adt_getprop(const void *unused, int node, const char *name, u32 *len) {
    struct prop *p = fixture_prop(node, name);
    (void)unused;
    if (len) *len = p && p->len >= 0 ? p->len : 0;
    return p && p->len >= 0 ? p->value : NULL;
}
static int adt_getprop_copy(const void *unused, int node, const char *name, void *out, size_t len) {
    u32 actual=0; const void *p=adt_getprop(unused,node,name,&actual);
    if (!p || actual!=len) return -1;
    memcpy(out,p,len); return actual;
}
/* Returns the previous length; a negative length hides the property. */
int fixture_len(const char *path, const char *name, int len) {
    struct prop *p = fixture_prop(adt_path_offset(adt, path), name);
    int old;
    if (!p) return -2;
    old = p->len; p->len = len; return old;
}
int fixture_swap(const char *path, const char *name, unsigned off, void *bytes, unsigned n) {
    struct prop *p = fixture_prop(adt_path_offset(adt, path), name);
    unsigned char tmp[8];
    if (!p || n > sizeof(tmp) || p->len < 0 || off + n > (unsigned)p->len) return -1;
    memcpy(tmp, p->value + off, n); memcpy(p->value + off, bytes, n); memcpy(bytes, tmp, n);
    return 0;
}
""" % (",".join(props), ",".join(f'"{path}"' for path in PATHS))


def records(tree, path, name):
    for p in tree[path].tostruct()["properties"]:
        if p["name"] == name:
            return list(struct.iter_unpack("<IIQQ", bytes(p["value"])))
    raise SystemExit(f"saved ADT has no {path} {name}")


def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adt", type=Path, required=True)
    parser.add_argument("--n1-dtb", type=Path, required=True)
    parser.add_argument("--inert-dtb", type=Path, required=True)
    parser.add_argument("--source", type=Path, default=root / "build/m1n1-gpu-n1")
    parser.add_argument("--cc", default="cc")
    args = parser.parse_args()
    source = args.source.resolve()
    sys.path.insert(0, str(source / "proxyclient"))
    from m1n1.adt import load_adt
    tree = load_adt(args.adt.read_bytes())
    body = "\n".join(line for line in (source / "src/kboot_n1.c").read_text().splitlines()
                     if not line.startswith("#include"))

    with tempfile.TemporaryDirectory(prefix="j714s-n1-smoke-") as td:
        td = Path(td)
        unit = td / "n1.c"
        unit.write_text(PRELUDE + fixture(tree) + body)
        fdt = source / "src/libfdt"
        library = td / "n1.so"
        # Warnings are errors for the hand-off itself, not for the vendored libfdt.
        subprocess.run([args.cc, "-c", "-fPIC", "-O2", "-Wall", "-Wextra", "-Werror",
                        "-Wno-unused-function", "-I", str(fdt), str(unit), "-o", str(td / "n1.o")],
                       check=True)
        subprocess.run([args.cc, "-shared", "-fPIC", "-O2", "-w", "-include", "stdlib.h",
                        "-I", str(fdt), str(td / "n1.o"), *map(str, sorted(fdt.glob("*.c"))),
                        "-o", str(library)], check=True)
        lib = C.CDLL(str(library))
        lib.fdt_getprop.restype = C.c_void_p
        lib.fdt_getprop.argtypes = [C.c_void_p, C.c_int, C.c_char_p, C.POINTER(C.c_int)]
        lib.fdt_path_offset.argtypes = [C.c_void_p, C.c_char_p]
        lib.fdt_open_into.argtypes = [C.c_void_p, C.c_void_p, C.c_int]
        lib.fdt_delprop.argtypes = [C.c_void_p, C.c_int, C.c_char_p]
        lib.fdt_setprop.argtypes = [C.c_void_p, C.c_int, C.c_char_p, C.c_void_p, C.c_int]
        lib.fdt_pack.argtypes = [C.c_void_p]
        lib.kboot_setup_n1.argtypes = [C.c_void_p]
        lib.fixture_len.argtypes = [C.c_char_p, C.c_char_p, C.c_int]
        lib.fixture_swap.argtypes = [C.c_char_p, C.c_char_p, C.c_uint, C.c_void_p, C.c_uint]
        lib.fdt_get_phandle.restype = C.c_uint32
        lib.fdt_get_phandle.argtypes = [C.c_void_p, C.c_int]

        def fresh(path):
            blob = path.read_bytes()
            out = C.create_string_buffer(len(blob) + (1 << 20))
            assert lib.fdt_open_into(blob, out, len(out)) == 0
            return out

        def prop(dt, path, key):
            length = C.c_int()
            node = lib.fdt_path_offset(dt, path.encode())
            assert node >= 0, path
            value = lib.fdt_getprop(dt, node, key.encode(), C.byref(length))
            return C.string_at(value, length.value) if value else None

        def status(dt, path):
            value = prop(dt, path, "status")
            return "okay" if value is None else value.rstrip(b"\0").decode()

        def window(dt, name):
            names = prop(dt, HOST, "reg-names").rstrip(b"\0").split(b"\0")
            reg = struct.unpack(f">{len(names) * 4}I", prop(dt, HOST, "reg"))
            idx = names.index(name.encode())
            assert reg[idx * 4 + 2] == 0
            return reg[idx * 4 + 3]

        def disabled(dt, why):
            assert (status(dt, PORT), status(dt, DART)) == ("disabled", "disabled"), why
            print("PASS: fail-closed,", why)

        def tree_side(dt, n1):
            bank, perst, _ = struct.unpack(">3I", prop(dt, PORT, "reset-gpios"))
            assert bank == lib.fdt_get_phandle(dt, lib.fdt_path_offset(dt, PINCTRL.encode()))
            spans = list(struct.iter_unpack(">2I", prop(dt, PINCTRL, "gpio-reserved-ranges") or b""))

            def reserved(pin):
                return any(first <= pin < first + count for first, count in spans)

            # The bank's driver is built in, so every tree binds it: N1 on or off.
            assert status(dt, PINCTRL) == "okay" and reserved(FAULTING_PIN) and not reserved(perst)
            for label, unit, auto_off in CLOSURE:
                node = PMGR + unit
                assert prop(dt, node, "label") == label.encode() + b"\0", node
                manual = prop(dt, node, "apple,no-auto-pm") is not None
                if n1:
                    assert prop(dt, node, "apple,always-on") is not None and manual == auto_off, label
                else:
                    assert not manual, label

        # 0. What the kernel train needs from the tree before any loader runs.
        tree_side(fresh(args.n1_dtb), True)
        print("PASS: N1 tree raises the GP power closure and its pin bank exposes PERST#, "
              f"not pin {FAULTING_PIN}")
        tree_side(fresh(args.inert_dtb), False)
        print("PASS: tree with the N1 off leaves the closure to auto-PM and keeps the same pin guard")

        # 1. The N1 tree: identity, all lists, port and DART enabled together.
        dt = fresh(args.n1_dtb)
        assert (status(dt, HOST), status(dt, PORT), status(dt, DART)) == ("okay", "disabled", "disabled")
        assert lib.kboot_setup_n1(dt) == 0
        assert prop(dt, CONTROL, "firmware-name") == b"apple/centauri/j714s-ftab.bin\0"
        assert prop(dt, CONTROL, "apple,centauri-platform-id") == struct.pack(">I", 0x00086050)
        assert prop(dt, CONTROL, "apple,centauri-protocol") == struct.pack(">I", 27)
        total = 0
        for adt_name, dt_name, win, add in HOST_LISTS:
            recs = records(tree, "/arm-io/apcie0", adt_name)
            expect = b"".join(struct.pack(">4I", off + add, 4, mask, value)
                              for off, size, mask, value in recs)
            assert recs and all(size == 4 and off + add <= window(dt, win) - 4
                                for off, size, _, _ in recs), adt_name
            assert prop(dt, HOST, dt_name) == expect, dt_name
            total += len(recs)
        for name in PORT_LISTS:
            recs = records(tree, "/arm-io/apcie0/pci-bridge0", name)
            expect = b"".join(struct.pack(">4I", off, 4, mask, value) for off, size, mask, value in recs)
            assert prop(dt, PORT, "apple," + name) == expect, name
        assert (status(dt, PORT), status(dt, DART)) == ("okay", "okay")
        assert lib.fdt_pack(dt) == 0
        print(f"PASS: N1 tree gets identity, {total} host records in six in-window lists, "
              "five port lists, and port+DART enabled together")

        # 2. A tree whose host is disabled is not touched at all.
        dt = fresh(args.inert_dtb)
        before = bytes(dt)
        assert status(dt, HOST) == "disabled" and lib.kboot_setup_n1(dt) == 0 and bytes(dt) == before
        print("PASS: disabled host leaves the device tree byte-identical")

        # 3. Missing DT preconditions.
        for path, key in ((DART, "apple,manual-availability"), (PORT, "pwren-gpios"),
                          (PORT, "apple,link-trained-by-bootloader")):
            dt = fresh(args.n1_dtb)
            assert lib.fdt_delprop(dt, lib.fdt_path_offset(dt, path.encode()), key.encode()) == 0
            assert lib.kboot_setup_n1(dt) == 0
            disabled(dt, f"DT without {key}")
        dt = fresh(args.n1_dtb)
        names = prop(dt, HOST, "reg-names").replace(b"phy-ip\0", b"phy-xx\0")
        assert lib.fdt_setprop(dt, lib.fdt_path_offset(dt, HOST.encode()), b"reg-names", names,
                               len(names)) == 0
        assert lib.kboot_setup_n1(dt) == 0
        disabled(dt, "DT host without the phy-ip window")

        # 4. Unusable ADT data: every list missing in turn, then bad records.
        for adt_name, dt_name, _, _ in HOST_LISTS:
            old = lib.fixture_len(b"/arm-io/apcie0", adt_name.encode(), -1)
            dt = fresh(args.n1_dtb)
            assert old > 0 and lib.kboot_setup_n1(dt) == 0
            disabled(dt, f"ADT without {adt_name}")
            lib.fixture_len(b"/arm-io/apcie0", adt_name.encode(), old - 1)
            dt = fresh(args.n1_dtb)
            assert lib.kboot_setup_n1(dt) == 0
            disabled(dt, f"ADT {adt_name} with a truncated record")
            lib.fixture_len(b"/arm-io/apcie0", adt_name.encode(), old)
        name = b"apcie-phy-ip-auspma-tunables"
        for label, offset, value in (("record beyond its window", 0, struct.pack("<I", 0x1b4000)),
                                     ("unaligned record", 0, struct.pack("<I", 0x184009)),
                                     ("8-byte record", 4, struct.pack("<I", 8)),
                                     ("64-bit mask", 8, struct.pack("<Q", 1 << 32))):
            saved = C.create_string_buffer(value, len(value))
            assert lib.fixture_swap(b"/arm-io/apcie0", name, offset, saved, len(value)) == 0
            dt = fresh(args.n1_dtb)
            assert lib.kboot_setup_n1(dt) == 0
            disabled(dt, f"ADT {label}")
            assert lib.fixture_swap(b"/arm-io/apcie0", name, offset, saved, len(value)) == 0
        for path, key in (("/", "target-type"), ("/chosen", "board-id")):
            old = lib.fixture_len(path.encode(), key.encode(), -1)
            dt = fresh(args.n1_dtb)
            assert lib.kboot_setup_n1(dt) == 0
            disabled(dt, f"ADT without {key}")
            lib.fixture_len(path.encode(), key.encode(), old)

        # 5. The fixture was restored: the positive case still passes.
        dt = fresh(args.n1_dtb)
        assert lib.kboot_setup_n1(dt) == 0 and (status(dt, PORT), status(dt, DART)) == ("okay", "okay")
        print("PASS: restored inputs enable the port and DART again")


if __name__ == "__main__":
    main()
