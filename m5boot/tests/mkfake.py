#!/usr/bin/env python3
"""VM only: fake boot_args (at 0x44000000) + fake ADT (at 0x44010000) for QEMU virt. Layout per src/bootargs.h."""
import struct, sys
NOMM = '--no-memory-map' in sys.argv
BAD = '--bad-layout' in sys.argv    # probe: no plausible memSizeActual under any layout
RAMCO = '--ram-carveout' in sys.argv   # task 13: add a carveout equal to [physBase, physBase+memSize) like native
NOVRAM = '--no-vram' in sys.argv   # task 09: no /vram node -> tier c (VM "observed" region 0xb9000000)
OUT = '--fb-outside' in sys.argv   # Video base just past ADT DRAM end (0xc0000000): must not be used
FAULT = '--fault' in sys.argv       # probe VM build: cmdline 'probefault' -> brk after step 3   # makes m5boot panic in step 3 (after the WDT step)
PHYS, MEM, VIRT = 0x40000000, 0x70000000, 0xfffffe0000000000
FB = 0xb8000000   # above physBase+memSize, like spec §3 (video memory above the RAM window)
BA, ADT = 0x44000000, 0x44010000

def prop(name, val):
    b = name.encode().ljust(32, b'\0') + struct.pack('<I', len(val)) + val
    return b + b'\0' * (-len(b) % 4)
def node(props, children=()):
    return struct.pack('<II', len(props), len(children)) + b''.join(prop(*p) for p in props) + b''.join(children)
s = lambda x: x.encode() + b'\0'
u32 = lambda v: struct.pack('<I', v)
q = lambda *v: struct.pack('<%dQ' % len(v), *v)

adt = node([('name', s('device-tree')), ('#address-cells', u32(2)), ('#size-cells', u32(2))], [
    node([('name', s('chosen')), ('dram-base', q(0x40000000)), ('dram-size', q(0x80000000))], [] + [   # like spec §3: FB above memSize, inside DRAM
        *([] if NOMM else [node([('name', s('memory-map')), ('BootArgs', q(BA, 0x4000)), ('DeviceTree', q(ADT, 0x10000)), ('Unused', q(0, 0))])]),
        node([('name', s('carveout-memory-map')), ('region-id-1', q(0x50000000, 0x1000000))] +
             ([('region-id-24', q(PHYS, MEM))] if RAMCO else [])),   # task 13: the J714s RAM-window carveout
    ]),
    *([] if NOVRAM else [node([('name', s('vram')), ('device_type', s('vram')), ('reg', q(0xb8000000, 0x200000))])]),
    node([('name', s('arm-io')), ('#address-cells', u32(2)), ('#size-cells', u32(2)),
          ('ranges', q(0, 0xbe000000, 0x1000000))], [   # wdt -> 0xbef00000: QEMU RAM, outside the fake DRAM window
        node([('name', s('pmgr')), ('reg', q(0xf10000, 0x4000, 0xf20000, 0x4000))]),   # task 17: -> 0xbef10000/0xbef20000
        node([('name', s('wdt')), ('compatible', b'wdt,t8101\0wdt,s5l8960x\0'), ('reg', q(0xf00000, 0x4000, 0xf00100, 4, 0xf00104, 4, 0xf00108, 4, 0xf0010c, 4))]   # task 16: + 4 extra single regs like J714s
             + ([] if '--wdt-version1' in sys.argv else [('wdt-version', u32(3))])),   # task 19: J714s has wdt-version 3
    ]),
])
ba = bytearray(2048)
struct.pack_into('<HH', ba, 0, 2, 2); struct.pack_into('<4Q', ba, 8, VIRT, PHYS, MEM, 0x45000000)
struct.pack_into('<6Q', ba, 40, 0xc0000000 if OUT else FB, 0, 640 * 4, 640, 480, 32)
struct.pack_into('<IxxxxQI', ba, 88, 0, VIRT + ADT - PHYS, len(adt))   # deviceTreeP as a VA (spec H4)
CL = b'probefault' if FAULT else b'm5test m5.logdisk=vda' if '--logdisk' in sys.argv else b'm5test'   # task 20: VM disk name
ba[108:108 + len(CL) + 1] = CL + b'\0'
struct.pack_into('<QQ', ba, (108 + 1024 + 7) & ~7, 0, 0 if BAD else 2 << 30)
open(sys.argv[1], 'wb').write(ba)
open(sys.argv[2], 'wb').write(adt)
