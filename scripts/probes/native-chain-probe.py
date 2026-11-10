#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run one stage of the native boot chain from the m1n1 proxy, with its output visible.

A native boot here uses two stages to keep the enrolled object small and
kernel updates separate: the enrolled loader reads m1n1/boot.bin from the EFI
partition and chainloads it; that loader reads the kernel payload from a file.
Started by iBoot, neither stage brings USB up before it is done, so nothing
they print reaches the host. This runs the same compiled code of one stage
instead:

  --chainload SPEC   stage 1: chainload_load(SPEC), then the proxy is left and
                     the loader enters what it loaded
  --payload SPEC     stage 2: payload_spec is set and payload_run() called (the
                     calibration guard, the file read, the parse, secondary
                     CPUs, the hand-off), then the proxy is left and the loader
                     enters Linux
  --identify         only the comparison described below: which loader is
                     answering, after a fallback for instance

SPEC is "<partition uuid>;<path>", as in the chainload= and payload= variables.
The storage loader under test is chainloaded without its variable, so it stops
in its proxy. A stage 1 with a compiled-in target instead auto-starts; reach
its proxy through the missing-boot.bin fallback and use --identify there:

    cd build/tether-<flavor>                      # Mac in the m1n1 proxy
    python3 hv/wdt-arm.py 120
    ./proxyclient/tools/chainload.py -r LOADER.bin m1n1.wdt=keep
    python3 hv/native-chain-probe.py --loader LOADER.bin --elf M1N1-RAW.elf \\
        --payload SPEC

LOADER.bin and M1N1-RAW.elf are build/<loader tree>/build/m1n1.bin and
m1n1-raw.elf of a CHAINLOADING=1 build. Before anything is called, what runs on
the Mac is compared with LOADER.bin: code and constants, with the loader's own
relocations applied. Nothing is written to disk and only the loader itself
touches NVMe. The watchdog has to be armed and is re-armed before each step.

The whole chain with nothing called by hand is simply the plain enrolled
object chainloaded (make m1n1-stage1); it then shows nothing on the host until
Linux is up. What neither run can show: iBoot starting the enrolled object,
and USB brought up cold.
"""
import argparse
import pathlib
import struct
import sys

WD1_CUR_TIME, WD1_BITE_TIME, WD1_CTRL = 0x10, 0x14, 0x1c
CTRL_RESET_EN = 1 << 2
CLK_HZ = 24_000_000
R_AARCH64_RELATIVE = 1027


def elf_layout(path):
    """Sections (addr, file bytes), symbol values and relative relocations
    (offset, addend) of a little-endian ELF64."""
    blob = path.read_bytes()
    if blob[:6] != b"\x7fELF\x02\x01":
        raise SystemExit(f"{path}: not a little-endian ELF64")
    shoff, = struct.unpack_from("<Q", blob, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", blob, 0x3a)
    heads = [struct.unpack_from("<IIQQQQIIQQ", blob, shoff + i * shentsize) for i in range(shnum)]

    def text(table, offset):
        start = heads[table][4] + offset
        return blob[start:blob.index(b"\0", start)].decode()

    sections, symbols, relative = {}, {}, []
    for name, kind, _, addr, offset, size, link, _, _, entsize in heads:
        if kind == 1:  # SHT_PROGBITS
            sections[text(shstrndx, name)] = (addr, blob[offset:offset + size])
        elif kind == 2:  # SHT_SYMTAB
            for at in range(offset, offset + size, entsize):
                sym_name, _, _, shndx, value, _ = struct.unpack_from("<IBBHQQ", blob, at)
                if sym_name and shndx:
                    symbols[text(link, sym_name)] = value
        elif kind == 4:  # SHT_RELA; the linker script pads it, and discarded entries are NONE
            for at in range(offset, offset + size - 23, 24):
                where, info, addend = struct.unpack_from("<QQq", blob, at)
                if info == R_AARCH64_RELATIVE:
                    relative.append((where, addend))
                elif info:
                    raise SystemExit(f"{path}: relocation type {info:#x} is not handled here")
    return sections, symbols, relative


def as_loaded(addr, data, relative, base):
    """A section as the loader has it once it has relocated itself to `base`:
    even its code carries a few literal words that hold absolute addresses."""
    image = bytearray(data)
    for where, addend in relative:
        if addr <= where <= addr + len(data) - 8:
            struct.pack_into("<Q", image, where - addr, base + addend)
    return bytes(image)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--loader", type=pathlib.Path, required=True)
    parser.add_argument("--elf", type=pathlib.Path, required=True)
    stage = parser.add_mutually_exclusive_group(required=True)
    stage.add_argument("--chainload", metavar="SPEC")
    stage.add_argument("--payload", metavar="SPEC")
    stage.add_argument("--identify", action="store_true")
    parser.add_argument("--watchdog", type=int, default=120, metavar="SECONDS")
    args = parser.parse_args()
    if not 30 <= args.watchdog <= 170:
        parser.error("--watchdog must be 30..170")
    spec = args.chainload or args.payload
    if spec and (";" not in spec or not spec.isascii()):
        parser.error("SPEC is <partition uuid>;<path>")

    # Everything that can be refused is refused before the Mac is touched.
    loader = args.loader.read_bytes()
    sections, symbols, relative = elf_layout(args.elf)
    needed = (("chainload_load",) if args.chainload else
              ("payload_spec", "payload_run") if args.payload else ())
    for name in ("_base", "_payload_start") + needed:
        if name not in symbols:
            raise SystemExit(f"{args.elf}: no symbol {name}")
    if symbols["_base"] != 0 or symbols["_payload_start"] != len(loader):
        raise SystemExit("this ELF does not describe that loader (raw layout, no variable appended)")
    readonly = [sections[name] for name in (".init", ".text", ".rodata") if name in sections]
    if len(readonly) != 3 or any(loader[addr:addr + len(data)] != data for addr, data in readonly):
        raise SystemExit("the ELF's code and constants are not the loader's")

    sys.path.append(str(pathlib.Path(__file__).resolve().parents[1] / "proxyclient"))
    from m1n1.setup import p, u, iface  # connects to the proxy

    wdt = u.adt["/arm-io/wdt"].get_reg(0)[0]

    def arm():
        p.write32(wdt + WD1_CTRL, 0)
        p.write32(wdt + WD1_CUR_TIME, 0)
        p.write32(wdt + WD1_BITE_TIME, args.watchdog * CLK_HZ)
        p.write32(wdt + WD1_CTRL, CTRL_RESET_EN)

    # The chainloaded loader must have kept the watchdog (m1n1.wdt=keep).
    if not p.read32(wdt + WD1_CTRL) & CTRL_RESET_EN:
        raise SystemExit("the watchdog is not armed: chainload the loader with m1n1.wdt=keep")
    arm()

    base = p.get_base()
    for addr, data in readonly:
        if iface.readmem(base + addr, len(data)) != as_loaded(addr, data, relative, base):
            raise SystemExit(f"what runs at {base + addr:#x} is not this loader: "
                             "chainload it first, without its variable")
    print(f"CHAIN_LOADER_VERIFIED base {base:#x} (code and constants, relocated)")
    if args.identify:
        return

    text = u.malloc(len(spec) + 1)
    iface.writemem(text, spec.encode() + b"\0")
    arm()
    # Reading a file through the loader's NVMe driver outlasts the proxy
    # client's default 3 s reply timeout; the watchdog is the real limit.
    iface.dev.timeout = args.watchdog
    if args.chainload:
        print(f"CHAIN_STAGE1 chainload_load({spec})")
        result = p.call(base + symbols["chainload_load"], text, 0, 0)
        what = "chainload_load()"
    else:
        print(f"CHAIN_STAGE2 payload={spec}; payload_run()")
        p.write64(base + symbols["payload_spec"], text)
        result = p.call(base + symbols["payload_run"])
        what = "payload_run()"
    if result:
        raise SystemExit(f"{what} returned {result:#x}: this stage did not get to its hand-off "
                         "(its reason is in the output above); the watchdog is still armed")

    # Both only record the next stage. The loader enters it when its proxy
    # returns, which is where main() stands after a native payload_run().
    arm()
    print("CHAIN_HANDOFF_PREPARED; leaving the proxy so the loader enters the next stage")
    try:
        p.exit()
        iface.nop()  # nothing answers any more: this only drains the loader's last lines
    except Exception as gone:  # the proxy's USB port goes away with the loader
        print(f"CHAIN_HANDOFF the proxy went away as the loader left ({type(gone).__name__})")
        return
    raise SystemExit("the proxy still answers after P_EXIT: the loader did not leave it")


if __name__ == "__main__":
    main()
