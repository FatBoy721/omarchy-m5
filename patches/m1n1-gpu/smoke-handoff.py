#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compile/run the actual isolated loader handoff against saved ADT and actual DTBs.

Offline only: no m1n1.setup, proxy, MMIO, USB, SSH or target execution.
The C handoff, reservation and DCP opt-out bodies are extracted verbatim and
linked to the source's libfdt. ADT properties use m1n1.adt/get_reg; DCP checks
and watchdog writes are host substitutes. Python boot-argument serialization
is consumed by the actual C layout/watchdog code. No target Rust ADT FFI or hardware.

Usage: python patches/m1n1-gpu/smoke-handoff.py --adt SAVED.bin --dtb GPU.dtb
       --default-dtb DEFAULT.dtb --simpledrm-dtb SIMPLEDRM.dtb
       [--source build/m1n1-gpu-simpledrm] [--cc cc]
"""
import argparse
import ctypes as C
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

MAILBOX_PATHS = ("/arm-io/gfx-asc", "/arm-io/gfx1-asc")
PATHS = ("/arm-io/sgx", *MAILBOX_PATHS, "/arm-io/wdt")
REGIONS = ("uat-handoff", "uat-l2-pagetables", "uat-pagetables", "uat-ttbs", "gpu-fw-text", "gpu-fw-data")


def fixture(tree):
    arrays, props, regs = [], [], []
    for idx, path in enumerate(PATHS):
        node = tree[path]
        for p in node.tostruct()["properties"]:
            ident = f"prop_{len(props)}"
            value = p["value"]
            arrays.append(f"static unsigned char {ident}[] = {{{','.join(map(str, value))}}};")
            props.append(f'{{{idx}, "{p["name"]}", {ident}, {len(value)}}}')
        for reg_idx in range(len(node.reg)):
            base, size = node.get_reg(reg_idx)
            regs.append(f"{{{idx},{reg_idx},0x{base:x}ULL,0x{size:x}ULL}}")
    return "\n".join(arrays) + "\n" + """
struct prop { int node; const char *name; unsigned char *value; u32 len; };
static struct prop props[] = { %s };
struct reg { int node, idx; u64 base, size; };
static struct reg regs[] = { %s };
static const char *paths[] = { %s };
static void *adt;
static int adt_path_offset(const void *unused, const char *name) {
    (void)unused;
    for (size_t i=0; i<ARRAY_SIZE(paths); i++) if (!strcmp(paths[i], name)) return i;
    return -1;
}
static int adt_path_offset_trace(const void *unused, const char *name, int *path) {
    int node=adt_path_offset(unused,name); path[0]=node; return node;
}
static const void *adt_getprop(const void *unused, int node, const char *name, u32 *len) {
    (void)unused;
    for (size_t i=0; i<ARRAY_SIZE(props); i++)
        if (props[i].node==node && !strcmp(props[i].name,name)) {
            if (len) *len=props[i].len;
            return props[i].value;
        }
    if (len) *len=0;
    return NULL;
}
static int adt_getprop_copy(const void *unused, int node, const char *name, void *out, size_t len) {
    u32 actual=0; const void *p=adt_getprop(unused,node,name,&actual);
    if (!p || actual!=len) return -1;
    memcpy(out,p,len); return actual;
}
static int adt_get_reg(const void *unused, int *path, const char *name, int idx, u64 *base, u64 *size) {
    (void)unused;
    if (strcmp(name,"reg")) return -1;
    for (size_t i=0; i<ARRAY_SIZE(regs); i++) if (regs[i].node==path[0] && regs[i].idx==idx) {
        if (base) *base=regs[i].base;
        if (size) *size=regs[i].size;
        return 0;
    }
    return -1;
}
int fixture_u64(const char *name, u64 value) {
    u32 len; void *p=(void *)adt_getprop(adt,0,name,&len);
    if (!p || len!=8) return -1;
    memcpy(p,&value,8); return 0;
}
""" % (",".join(props), ",".join(regs), ",".join(f'"{path}"' for path in PATHS))


PRELUDE = r"""
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include "libfdt.h"
typedef uint64_t u64;
typedef uint32_t u32;
typedef uint16_t u16;
#define SZ_16K 16384
#define ARRAY_SIZE(x) (sizeof(x)/sizeof((x)[0]))
#define ADT_GETPROP(a,n,p,v) adt_getprop_copy(a,n,p,v,sizeof(*(v)))
#define bail(...) do { printf(__VA_ARGS__); return -1; } while (0)
struct adt_segment_ranges { u64 phys, iova, remap; u32 size, unk; } __attribute__((packed));
"""


def display_code(source):
    code = (source / "src/kboot.c").read_text()
    declarations = code[code.index("struct t6050_dcp_nodes {"):code.index("static int t6050_fdt_reg_base(")]
    iommu = code[code.index("static int t6050_fdt_iommu("):code.index("/* The first u32 of an ADT property")]
    nodes = code[code.index("static bool t6050_dcp_find_nodes("):code.index("static bool t6050_dcp_running(")]
    handoff = code[code.index("static int dt_set_t6050_dcp("):code.index("static int dt_set_display(")]
    hardware = r"""
static unsigned display_hw_calls;
static bool t6050_dcp_running(void) { display_hw_calls++; return false; }
static bool t6050_dart_inherited(const char *path, u32 phandle, const u32 *sids, int count) {
    (void)path; (void)phandle; (void)sids; (void)count;
    display_hw_calls++; return false;
}
static int t6050_dcp_publish(const struct t6050_dcp_nodes *nodes, u64 base, u64 size) {
    (void)nodes; (void)base; (void)size;
    display_hw_calls++; return -1;
}
"""
    wrappers = r"""
int run_display(void *tree) { dt=tree; display_hw_calls=0; return dt_set_t6050_dcp(); }
unsigned display_hw_accesses(void) { return display_hw_calls; }
"""
    return "static void *dt;\n" + declarations + iommu + nodes + hardware + handoff + wrappers


def watchdog_code(source):
    code = (source / "src/wdt.c").read_text()
    body = code[code.index("#define WDT_COUNT"):code.index("void wdt_reboot(")]
    return f'#include "{source / "src/xnuboot.h"}"\n' + r"""
_Static_assert(sizeof(void *) == 8, "Boot-argument ABI smoke needs a 64-bit host");
struct boot_args cur_boot_args;
static unsigned wdt_writes;
static u64 wdt_addresses[2];
static u32 wdt_values[2];
static void write32(u64 address, u32 value) {
    if (wdt_writes < ARRAY_SIZE(wdt_addresses)) {
        wdt_addresses[wdt_writes]=address; wdt_values[wdt_writes]=value;
    }
    wdt_writes++;
}
""" + body + r"""
int run_watchdog(const void *data, size_t size) {
    if (size > sizeof(cur_boot_args)) return -1;
    memset(&cur_boot_args,0,sizeof(cur_boot_args));
    memcpy(&cur_boot_args,data,size);
    wdt_writes=0; wdt_disable(); return wdt_writes;
}
const char *bootargs_cmdline(void) {
    switch (cur_boot_args.revision) {
        case 1: return cur_boot_args.rv1.cmdline;
        case 2: return cur_boot_args.rv2.cmdline;
        default: return cur_boot_args.rv3.cmdline;
    }
}
u64 bootargs_flags(void) {
    switch (cur_boot_args.revision) {
        case 1: return cur_boot_args.rv1.boot_flags;
        case 2: return cur_boot_args.rv2.boot_flags;
        default: return cur_boot_args.rv3.boot_flags;
    }
}
u64 bootargs_mem_size_actual(void) {
    switch (cur_boot_args.revision) {
        case 1: return cur_boot_args.rv1.mem_size_actual;
        case 2: return cur_boot_args.rv2.mem_size_actual;
        default: return cur_boot_args.rv3.mem_size_actual;
    }
}
u64 bootargs_devtree(void) { return (uintptr_t)cur_boot_args.devtree; }
u32 bootargs_devtree_size(void) { return cur_boot_args.devtree_size; }
u64 watchdog_write_address(unsigned i) { return wdt_addresses[i]; }
u32 watchdog_write_value(unsigned i) { return wdt_values[i]; }
"""


def check_bootargs(lib, tree):
    from m1n1.tgtypes import BootArgs_r1, BootArgs_r2, BootArgs_r3
    lib.run_watchdog.argtypes = [C.c_void_p, C.c_size_t]
    lib.bootargs_cmdline.restype = C.c_char_p
    for name in ("bootargs_flags", "bootargs_mem_size_actual", "bootargs_devtree",
                 "watchdog_write_address"):
        getattr(lib, name).restype = C.c_uint64
    lib.bootargs_devtree_size.restype = C.c_uint32
    lib.watchdog_write_value.restype = C.c_uint32
    lib.watchdog_write_address.argtypes = lib.watchdog_write_value.argtypes = [C.c_uint]
    marker = "m1n1.wdt=keep"
    for revision, (layout, capacity) in enumerate(
            ((BootArgs_r1, 256), (BootArgs_r2, 608), (BootArgs_r3, 1024)), 1):
        values = {
            "revision": revision, "version": 2, "virt_base": 0x10000000,
            "phys_base": 0x10000000000, "mem_size": 0xc00000000,
            "top_of_kernel_data": 0x10001000000,
            "video": dict(base=0x10bd310c000, display=1, stride=12096,
                          width=3024, height=1964, depth=30),
            "machine_type": 0, "devtree": 0x10002000000, "devtree_size": 0xb8000,
            "boot_flags": 0x1122334455667700 + revision,
            "mem_size_actual": 0xc00000000 + revision * 0x4000,
        }
        cases = (("empty", ""), ("leading", marker),
                 ("embedded", "other=1 " + marker + " last=1"),
                 ("capacity boundary", "x" * (capacity - len(marker) - 2) + " " + marker))
        for name, cmdline in cases:
            wire = layout.build({**values, "cmdline": cmdline})
            writes = lib.run_watchdog(C.create_string_buffer(wire), len(wire))
            actual = lib.bootargs_cmdline().decode("ascii")
            assert actual == cmdline, f"r{revision} {name}: C reads {actual!r}, expected {cmdline!r}"
            assert lib.bootargs_flags() == values["boot_flags"]
            assert lib.bootargs_mem_size_actual() == values["mem_size_actual"]
            assert lib.bootargs_devtree() == values["devtree"]
            assert lib.bootargs_devtree_size() == values["devtree_size"]
            assert writes == (0 if marker in cmdline else 2), (revision, name, writes)
            if writes:
                expected = (tree["/arm-io/wdt"].get_reg(0)[0] + 0x1c,
                            tree["/arm-io/wdt"].get_reg(2)[0])
                assert tuple(lib.watchdog_write_address(i) for i in range(writes)) == expected
                assert all(lib.watchdog_write_value(i) == 0 for i in range(writes))
            print(f"PASS: bootargs r{revision} {name} preserves command line, tail fields and watchdog contract")


def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adt", type=Path, required=True)
    parser.add_argument("--dtb", type=Path, required=True)
    parser.add_argument("--default-dtb", type=Path, required=True)
    parser.add_argument("--simpledrm-dtb", type=Path, required=True)
    parser.add_argument("--source", type=Path, default=root / "build/m1n1-gpu-simpledrm")
    parser.add_argument("--cc", default="cc")
    args = parser.parse_args()
    source = args.source.resolve()
    sys.path.insert(0, str(source / "proxyclient"))
    from m1n1.adt import load_adt
    tree = load_adt(args.adt.read_bytes())
    code = (source / "src/kboot_gpu.c").read_text()
    reservation = code[code.index("static int dt_set_resvmem("):code.index("static int dt_set_region(")]
    body = code[code.index("/* Adapted from Rolando Trevino"):code.index("\nint dt_set_gpu(void *dt)")]
    with tempfile.TemporaryDirectory(prefix="j714s-gpu-smoke-") as td:
        td = Path(td)
        unit = td / "handoff.c"
        unit.write_text(PRELUDE + fixture(tree) + reservation + body + display_code(source)
                        + watchdog_code(source)
                        + "\nint run_handoff(void *dt) { return dt_set_gpu_t6050(dt); }\n")
        fdt = source / "src/libfdt"
        library = td / "handoff.so"
        # The freestanding libfdt environment omits the host strtoul declaration.
        subprocess.run([args.cc, "-shared", "-fPIC", "-O2", "-Wall", "-Wextra",
                        "-include", "stdlib.h", "-I", str(fdt),
                        str(unit), *map(str, sorted(fdt.glob("*.c"))), "-o", str(library)], check=True)
        lib = C.CDLL(str(library))
        lib.fdt_open_into.argtypes = [C.c_void_p, C.c_void_p, C.c_int]
        lib.fdt_path_offset.argtypes = [C.c_void_p, C.c_char_p]
        lib.fdt_getprop.argtypes = [C.c_void_p, C.c_int, C.c_char_p, C.POINTER(C.c_int)]
        lib.fdt_getprop.restype = C.c_void_p
        lib.fdt_setprop.argtypes = [C.c_void_p, C.c_int, C.c_char_p, C.c_void_p, C.c_int]
        lib.fdt_delprop.argtypes = [C.c_void_p, C.c_int, C.c_char_p]
        lib.run_handoff.argtypes = [C.c_void_p]
        lib.run_display.argtypes = [C.c_void_p]
        lib.display_hw_accesses.restype = C.c_uint
        lib.fixture_u64.argtypes = [C.c_char_p, C.c_uint64]

        def fresh(path=args.dtb):
            blob = path.read_bytes()
            out = C.create_string_buffer(len(blob) + 65536)
            assert lib.fdt_open_into(blob, out, len(out)) == 0
            return out

        def node(dt, path):
            offset = lib.fdt_path_offset(dt, path.encode())
            assert offset >= 0, path
            return offset

        def prop(dt, path, key):
            length = C.c_int()
            value = lib.fdt_getprop(dt, node(dt, path), key.encode(), C.byref(length))
            assert value and length.value >= 0, (path, key)
            return C.string_at(value, length.value)

        def setprop(dt, path, key, value):
            assert lib.fdt_setprop(dt, node(dt, path), key.encode(), value, len(value)) == 0

        def disabled(dt):
            for path in ["gpu", "gpu-mbox", "gpu-mbox1", *["/reserved-memory/" + r for r in REGIONS]]:
                assert prop(dt, path, "status") == b"disabled\0", path

        dt = fresh()
        assert lib.run_handoff(dt) == 0
        for path in ["gpu", "gpu-mbox", "gpu-mbox1", *["/reserved-memory/" + r for r in REGIONS]]:
            assert prop(dt, path, "status") == b"okay\0", path
        sgx = tree[PATHS[0]]
        expected = [(sgx.getprop(n + "-base"), sgx.getprop(n + "-size")) for n in
                    ("gfx-handoff", "gfx-shared-l2-region", "gfx-shared-region", "gpu-region")]
        segments = [list(struct.iter_unpack("<QQQII", tree[p].getprop("segment-ranges"))) for p in MAILBOX_PATHS]
        expected += [(segments[0][0][0], segments[0][0][3] + segments[1][0][3]),
                     (segments[0][1][0], sum(s[3] for asc in segments for s in asc[1:]))]
        for name, value in zip(REGIONS, expected):
            assert struct.unpack(">QQ", prop(dt, "/reserved-memory/" + name, "reg")) == value
        for alias, path in zip(("gpu-mbox", "gpu-mbox1"), MAILBOX_PATHS):
            assert struct.unpack(">QQQQ", prop(dt, alias, "reg")) == (tree[path].get_reg(0)[0], 0x88000, tree[path].get_reg(1)[0], 8)
        print("PASS: actual GPU DT receives six exact ADT ranges and both native mailboxes")

        dt = fresh(args.default_dtb)
        before = dt.raw
        assert lib.run_handoff(dt) == 0 and dt.raw == before
        print("PASS: default DT unchanged")
        dt = fresh()
        assert lib.fdt_delprop(dt, node(dt, "gpu"), b"apple,m1n1-gpu-handoff") == 0
        before = dt.raw
        assert lib.run_handoff(dt) == 0 and dt.raw == before
        print("PASS: absent trial marker leaves DT unchanged")

        def wrong_sgx(dt):
            data = bytearray(prop(dt, "gpu", "reg"))
            names = prop(dt, "gpu", "reg-names").split(b"\0")
            struct.pack_into(">Q", data, 16 * names.index(b"sgx"), 0x4000)
            setprop(dt, "gpu", "reg", bytes(data))

        def wrong_irq(dt):
            data = bytearray(prop(dt, "gpu-mbox", "interrupts"))
            struct.pack_into(">I", data, len(data) // 2 - 8, 1)
            setprop(dt, "gpu-mbox", "interrupts", bytes(data))

        cases = {
            "wrong sgx": wrong_sgx,
            "duplicate role": lambda dt: setprop(dt, "gpu-mbox1", "apple,firmware-role", b"GFX\0"),
            "foreign interrupt": wrong_irq,
            "single mailbox": lambda dt: setprop(dt, "gpu", "mboxes", prop(dt, "gpu", "mboxes")[:4]),
            "bad memory reference": lambda dt: setprop(dt, "gpu", "memory-region", b"\0" * 24),
        }
        for name, mutate in cases.items():
            dt = fresh()
            mutate(dt)
            assert lib.run_handoff(dt) == 0
            disabled(dt)
            print("PASS: fail-closed", name)
        original = sgx.getprop("gfx-handoff-base")
        for name, value in (("overlap", sgx.getprop("gpu-region-base")), ("unaligned", original + 1), ("above 4TiB", 1 << 42)):
            assert lib.fixture_u64(b"gfx-handoff-base", value) == 0
            dt = fresh()
            assert lib.run_handoff(dt) == 0
            disabled(dt)
            print("PASS: fail-closed ADT", name)
        assert lib.fixture_u64(b"gfx-handoff-base", original) == 0

        display_paths = ("dcp", "disp0", "/soc/mailbox@48ae08000",
                         "/soc/iommu@48a340000", "/soc/iommu@48a300000",
                         "/reserved-memory/framebuffer@0")
        dt = fresh(args.simpledrm_dtb)
        assert prop(dt, "dcp", "apple,m1n1-simpledrm-only") == b""
        for path in display_paths:
            assert prop(dt, path, "status") == b"disabled\0", path
            setprop(dt, path, "status", b"okay\0")
        fb_path = "/chosen/framebuffer@0"
        framebuffer = {
            "reg": struct.pack(">QQ", 0x10010000000, 0x2000000),
            "width": struct.pack(">I", 3024),
            "height": struct.pack(">I", 1890),
            "stride": struct.pack(">I", 12096),
            "format": b"x2r10g10b10\0",
            "status": b"okay\0",
        }
        for key, value in framebuffer.items():
            setprop(dt, fb_path, key, value)
        assert lib.run_display(dt) == 0 and lib.display_hw_accesses() == 0
        assert lib.run_handoff(dt) == 0
        for path in display_paths:
            assert prop(dt, path, "status") == b"disabled\0", path
        for key, value in framebuffer.items():
            assert prop(dt, fb_path, key) == value, key
        assert prop(dt, "gpu", "status") == b"okay\0"
        print("PASS: simpledrm opt-out disables DCP without hardware checks and preserves framebuffer/GPU handoff")

        dt = fresh()
        assert lib.run_display(dt) == 0 and lib.display_hw_accesses() == 1
        print("PASS: unmarked DCP profile still reaches the inherited-hardware check")

        dt = fresh(args.simpledrm_dtb)
        assert lib.fdt_delprop(dt, node(dt, "/aliases"), b"dcp") == 0
        assert lib.run_display(dt) < 0 and lib.display_hw_accesses() == 0
        print("PASS: malformed simpledrm display bindings stop before hardware checks")

        check_bootargs(lib, tree)


if __name__ == "__main__":
    main()
