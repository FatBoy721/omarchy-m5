# hv script: synchronously trace the N1 apcie host, PHY and port registers,
# so the last logged access before a bus hang names the culprit.
from m1n1.hv.types import TraceMode
from m1n1.utils import irange
for base, size, name in [
    (0x1cb0000000, 0x10000000, "apcie-config"),
    (0x410000000, 0x8000000, "apcie-regs"),   # port0, rc, phy, axi2af, clkgen, phy-ip, dart
]:
    hv.trace_range(irange(base, size), mode=TraceMode.SYNC, name=name)
print("apcie SYNC tracing armed")

# Host safety net: a dedicated CPU reboots the Mac if the HV host stalls (>1 s),
# e.g. an SError inside m1n1. That CPU is removed from the guest.
hv.wdt_cpu = 16
print("HV watchdog on cpu16")
