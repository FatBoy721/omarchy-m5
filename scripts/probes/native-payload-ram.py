#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run a native boot image's own payload path from RAM, without enrolling it.

A self-contained boot object is `stage1.bin | bootargs | Image.gz | dtb |
initramfs` (scripts/mkpayload.sh): m1n1 scans what follows its own image. This
proves that path for a candidate before anyone spends a Recovery ceremony on
it. With the candidate's stage 1 chainloaded and sitting in its proxy:

  1. what runs on the Mac is compared with the stage 1 inside the candidate
     (code and constants, with the loader's own relocations applied);
  2. the candidate's payload tail is copied to ordinary RAM and read back;
  3. the loader's own compiled load_one_payload() parses that copy, item by
     item, exactly as it would parse the bytes after its image;
  4. the loader's own payload_run() takes over: its calibration guard, its
     NVMe preparation, secondary CPUs and the device-tree hand-off;
  5. the proxy is left, and the loader's main() goes on as it does after a
     native payload_run(): it shuts its devices down and enters Linux.

Nothing is written to disk and nothing here initialises NVMe from the host,
so the loader's own preparation is what Linux gets. What this cannot show:
iBoot loading the image, where iBoot places it (CTRR), USB brought up cold,
or a boot with the cable unplugged. Those need the enrolled image.

    cd build/tether-<flavor>                      # Mac in the m1n1 proxy
    python3 hv/wdt-arm.py 120
    ./proxyclient/tools/chainload.py -r STAGE1.bin m1n1.wdt=keep
    python3 hv/native-payload-ram.py --candidate PAYLOAD.bin \\
        --stage1 STAGE1.bin --elf M1N1-RAW.elf

STAGE1.bin and M1N1-RAW.elf are build/<loader tree>/build/m1n1.bin and
m1n1-raw.elf of the CHAINLOADING=0 loader; PAYLOAD.bin is mkpayload's output.
The watchdog is re-armed before each long step and left armed for Linux.
"""
import argparse
import hashlib
import pathlib
import struct
import sys

WD1_CUR_TIME, WD1_BITE_TIME, WD1_CTRL = 0x10, 0x14, 0x1c
CTRL_RESET_EN = 1 << 2
CLK_HZ = 24_000_000
PAGE = 0x4000


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
    parser.add_argument("--candidate", type=pathlib.Path, required=True)
    parser.add_argument("--stage1", type=pathlib.Path, required=True)
    parser.add_argument("--elf", type=pathlib.Path, required=True)
    parser.add_argument("--watchdog", type=int, default=120, metavar="SECONDS")
    args = parser.parse_args()
    if not 30 <= args.watchdog <= 170:
        parser.error("--watchdog must be 30..170")

    # Everything that can be refused is refused before the Mac is touched.
    candidate, stage1 = args.candidate.read_bytes(), args.stage1.read_bytes()
    sections, symbols, relative = elf_layout(args.elf)
    if not candidate.startswith(stage1) or len(candidate) == len(stage1):
        raise SystemExit("the candidate does not start with this stage 1 followed by a payload")
    for name in ("_base", "_payload_start", "load_one_payload", "payload_run"):
        if name not in symbols:
            raise SystemExit(f"{args.elf}: no symbol {name}")
    if symbols["_base"] != 0 or symbols["_payload_start"] != len(stage1):
        raise SystemExit("this ELF does not describe that stage 1 (raw layout, payload at its end)")
    readonly = [sections[name] for name in (".init", ".text", ".rodata") if name in sections]
    if len(readonly) != 3 or any(stage1[addr:addr + len(data)] != data for addr, data in readonly):
        raise SystemExit("the ELF's code and constants are not the stage 1's")
    tail = candidate[len(stage1):]
    print(f"NATIVE_CANDIDATE_SHA256 {hashlib.sha256(candidate).hexdigest()} "
          f"({len(candidate)} bytes: stage 1 {len(stage1)}, payload {len(tail)})")

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
        raise SystemExit("the watchdog is not armed: chainload the stage 1 with m1n1.wdt=keep")
    print("WATCHDOG_PRESERVED across the chainload; re-arming for each step")
    arm()

    base = p.get_base()
    for addr, data in readonly:
        if iface.readmem(base + addr, len(data)) != as_loaded(addr, data, relative, base):
            raise SystemExit(f"what runs at {base + addr:#x} is not this stage 1: "
                             "chainload the candidate's own stage 1 first")
    print(f"NATIVE_RUNNING_IMAGE_VERIFIED base {base:#x} (code and constants, relocated); "
          "NVMe has not been initialised by the host")

    # The parser stops at zeros, as it does after the last payload of a real image.
    staged = tail + bytes(PAGE)
    copy = u.memalign(PAGE, len(staged))
    arm()
    iface.writemem(copy, staged, progress=True)
    arm()
    if iface.readmem(copy, len(staged)) != staged:
        raise SystemExit("the staged payload does not read back")
    print(f"NATIVE_PAYLOAD_TAIL_VERIFIED {copy:#x} {len(tail)}")

    arm()
    item, at = 0, copy
    while at:
        following = p.call(base + symbols["load_one_payload"], at, 0)
        if following:
            if not at < following <= copy + len(tail):
                raise SystemExit(f"the parser left the payload: {following:#x}")
            print(f"NATIVE_PAYLOAD_ITEM {item} {at:#x} {following:#x}")
            item += 1
        elif at != copy + len(tail):
            raise SystemExit(f"the parser stopped at {at:#x}, before the end of the payload")
        at = following
    print(f"NATIVE_PAYLOAD_PARSED {item} items; invoking the loader's guard, NVMe and kernel hand-off")

    arm()
    result = p.call(base + symbols["payload_run"])
    if result:
        raise SystemExit(f"payload_run() returned {result:#x}: the loader refused to boot Linux "
                         "(its reason is in the output above); the watchdog is still armed")
    # kboot_boot() only records the next stage. The loader enters it when its
    # proxy returns, which is where main() stands after a native payload_run().
    print("NATIVE_HANDOFF_PREPARED; leaving the proxy so the loader enters Linux")
    try:
        p.exit()
        iface.nop()  # nothing answers any more: this only drains the loader's last lines
    except Exception as gone:  # the proxy's USB port goes away with the loader
        print(f"NATIVE_HANDOFF the proxy went away as the loader entered Linux ({type(gone).__name__})")
        return
    raise SystemExit("the proxy still answers after P_EXIT: the loader did not leave it")


if __name__ == "__main__":
    main()
