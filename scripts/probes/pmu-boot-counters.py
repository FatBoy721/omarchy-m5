#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Read the PMU's boot counters from the m1n1 proxy without clearing them.

iBoot keeps a boot stage, a boot-error count and a panic count in the PMU's
legacy scratchpad (ADT info-leg_scrpad) and stops starting an OS that keeps
failing. Every other proxy tool imports m1n1.setup, which zeroes the counts as
it connects, so with the cable attached they never add up. Without the cable
only the OS can clear them (the root filesystem's omarchy-m5-boot-ok.service).
This connects the way m1n1.setup does, minus that write, and prints what iBoot
left. Run it first after a reset, before any other tool:

    cd build/tether-<flavor>                      # Mac in the m1n1 proxy
    python3 hv/pmu-boot-counters.py

Read-only: SPMI register reads of sixteen scratchpad bytes.
"""
import pathlib
import sys

sys.path.append(str(pathlib.Path(__file__).resolve().parents[1] / "proxyclient"))
from m1n1.proxy import M1N1Proxy, UartInterface  # noqa: E402
from m1n1.proxyutils import ProxyUtils, bootstrap_port  # noqa: E402
from m1n1.hw.pmu import PMU  # noqa: E402

iface = UartInterface()
p = M1N1Proxy(iface, debug=False)
bootstrap_port(iface, p)
pmu = PMU(ProxyUtils(p))
base = pmu.node.info_leg__scrpad[0]
pad = [pmu.spmi.read8(pmu.reg, base + i) for i in range(16)]
print(f"PMU_SCRATCHPAD {base:#x}: {' '.join(f'{v:02x}' for v in pad)}")
print(f"PMU_BOOT_COUNTERS stage {pad[1]:#04x}, boot errors {pad[2] & 0xf}, "
      f"panics {pad[2] >> 4}, shutdown flag {pad[15] >> 3 & 1}")
