#!/usr/bin/env python3
"""Check J714s Aura CPU liveness; --start also requests secondary startup once.

Use Aura's proxyclient on PYTHONPATH and AURADEVICE=/dev/ttyACM0.
Normal aura.setup initializes the proxy and resets the PMU panic counter.
No kernel load, PMP access, MMIO scan, disk write or boot-policy change.
"""
import argparse
from datetime import datetime, timezone


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", action="store_true", help="start secondaries, then report liveness")
    args = parser.parse_args()

    from aura.setup import iface, p, u

    try:
        if iface.readmem(u.base + 0x808, 8) != b"AURALOAD":
            raise RuntimeError("resident image is not Aura; cold-boot the enrolled candidate first")
        model = u.adt.getprop("model")
        chip = u.adt["/chosen"].getprop("chip-id")
        board = u.adt["/chosen"].getprop("board-id")
        print("UTC:", datetime.now(timezone.utc).isoformat())
        print(f"model={model} chip={chip:#x} board={board:#x}")
        if (model, chip, board) != ("Mac17,9", 0x6050, 0x8):
            raise RuntimeError("this diagnostic is scoped to Mac17,9 / J714s / T6050 board 0x8")
        print("CurrentEL:", u.mrs("CurrentEL") >> 2)
        print("system firmware:", u.adt["/chosen"].getprop("system-firmware-version"))
        nodes = list(u.adt["/cpus"])
        cpus = sorted(node.getprop("cpu-id") for node in nodes)
        running = [node.getprop("cpu-id") for node in nodes if node.getprop("state") == "running"]
        if not cpus or len(running) != 1:
            raise RuntimeError("expected CPU IDs and exactly one running boot CPU in the ADT")
        boot_cpu = running[0]
        print("ADT CPU IDs:", cpus)
        print("Boot CPU (ADT running state):", boot_cpu)

        def report(tag):
            # Aura's spin-table liveness flag is for secondaries, not the boot CPU.
            alive = [cpu for cpu in cpus if cpu == boot_cpu or p.smp_is_alive(cpu)]
            missing = [cpu for cpu in cpus if cpu not in alive]
            print(f"{tag}: alive={alive} missing={missing} ({len(alive)}/{len(cpus)})")
            return not missing

        report("before")
        if args.start:
            p.smp_start_secondaries()
            return 0 if report("after") else 1
        return 0
    finally:
        iface.dev.close()


if __name__ == "__main__":
    raise SystemExit(main())
