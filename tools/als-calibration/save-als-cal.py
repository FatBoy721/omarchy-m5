#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run on macOS: save this Mac's ambient light sensor calibration for Linux.

Writes aop-als-cal.bin next to this script (or to the path given). Copy it to
/usr/lib/firmware/apple/aop-als-cal.bin on the Linux side and reboot: the
J714s light sensor (aop_als) reports only once it has this file.

The calibration is per machine (macOS keeps it as the `als` node's
CalibrationData, AppleSPUVD6286 on the M5 Pro). Gathered from
aurora-silicon/aurora-installer asahi_firmware/als.py (MIT), which the
aurora installer runs for the same file.
"""
import os, plistlib, subprocess, sys

out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "aop-als-cal.bin")
ioreg = subprocess.run(["ioreg", "-r", "-a", "-n", "als", "-l"], capture_output=True)
if ioreg.returncode != 0 or not ioreg.stdout:
    sys.exit("no 'als' node in ioreg: run this on macOS, on a Mac with an ambient light sensor")
tree = plistlib.loads(ioreg.stdout)
try:
    data = tree[0]["IORegistryEntryChildren"][0]["IORegistryEntryChildren"][0]["IORegistryEntryChildren"][0]["CalibrationData"]
except (KeyError, IndexError, TypeError):
    sys.exit("the 'als' node has no CalibrationData")
with open(out, "wb") as f:
    f.write(data)
print(f"saved {len(data)} bytes to {out}; copy it to /usr/lib/firmware/apple/aop-als-cal.bin on Linux")
