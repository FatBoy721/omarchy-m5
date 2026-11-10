#!/usr/bin/env python3
# WARNING: repeated watchdog resets left panicmedic state in NVRAM and the next
# boot fell back to macOS (2026-11-09). Prefer hvtest.sh + hvwdt.py (proxy reboot).
"""Arm the Mac's primary watchdog from the m1n1 proxy (T6050-safe, no m1n1.setup).

arm_wdt.py SECONDS   (1..178; 24 MHz counter)
A hung test boot then resets the machine; an uncaught boot runs the ESP default.
Chainload the test with boot-arg m1n1.wdt=keep so the next m1n1 leaves it armed.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "m1n1-proxy"))
from m1n1.adt import load_adt
from m1n1.proxy import M1N1Proxy, UartInterface
from m1n1.tgtypes import BootArgs_r1, BootArgs_r2, BootArgs_r3

WDT_COUNT, WDT_ALARM, WDT_CTL = 0x10, 0x14, 0x1C
secs = int(sys.argv[1])
assert 1 <= secs <= 178, "alarm must fit the 32-bit 24 MHz counter"

iface = UartInterface(os.environ.get("M1N1DEVICE", "/dev/m1n1"))
iface.nop()
p = M1N1Proxy(iface)
addr, rev = p.get_bootargs_rev()
args = iface.readstruct(addr, {0: BootArgs_r1, 1: BootArgs_r1, 2: BootArgs_r2, 3: BootArgs_r3}[rev])
base = (args.devtree - args.virt_base + args.phys_base) & 0xFFFFFFFFFFFFFFFF
adt = load_adt(iface.readmem(base, args.devtree_size))
wdt, _ = adt["/arm-io/wdt"].get_reg(0)
alarm = secs * 24_000_000
p.write32(wdt + WDT_CTL, 0)
p.write32(wdt + WDT_COUNT, 0)
p.write32(wdt + WDT_ALARM, alarm)
p.write32(wdt + WDT_CTL, 4)
ok = p.read32(wdt + WDT_ALARM) == alarm and p.read32(wdt + WDT_CTL) & 4
print(f"WDT @ {wdt:#x}: armed {secs}s" if ok else "WDT arm FAILED")
sys.exit(0 if ok else 1)
