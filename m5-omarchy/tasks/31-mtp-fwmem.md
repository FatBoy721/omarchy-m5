# Task 31 — MTP firmware memory: reserve + map the iBoot-preloaded image

NATIVE gz14 (reports/native-gz14-rootfs-dmesg.txt, native-gz14-input.txt):
  rtkit-helper 294600000.mtp: CPU_CONTROL at probe: stopped
  → RUN + wake → -62 timeout, "Coprocessor shutdown failed". hyprctl devices: no keyboards/mice.
So the MTP was NOT running at handoff (report 30's premise was wrong — record that correction in report 30, don't delete).

Hypothesis (PM): iBoot preloads the MTP firmware into a carveout described in the ADT (mtp node: segment-ranges / preloaded-firmware / iommu mappings, and /chosen/carveout-memory-map). Linux has no reserved-memory node for it and the MTP DART has no mapping for the firmware's IOVA, so the IOP starts and immediately faults (or Linux/m5boot already overwrote it). On Asahi, the bootloader adds reserved-memory (+ iommu-addresses) for preloaded IOP firmware.
Do:
1. From our ADT dump (reports/04-j714s-full.txt) list every property of the MTP ASC, its DART (dart-mtp) and SMC-like preloaded IOPs that describes firmware location/size/IOVA (segment-ranges, region-base/size, preloaded, firmware-name, etc.). Decode segment-ranges per public Linux/Asahi docs or kernel sources (cite; no m1n1 code).
2. Check whether that physical range overlaps anything m5boot places (kernel/initrd/FDT) or that Linux was free to allocate. Coordinate with ~/m5boot (spec/NOTES) — tell me if m5boot must add reserved-memory nodes (I'll assign it there).
3. Produce a DT (I3) with reserved-memory for the MTP firmware (no-map) + `iommu-addresses` on the MTP DART consumer per the upstream binding (reserved-memory iommu-addresses), as the Asahi kernel expects for preloaded IOPs (cite the kernel code that consumes it: apple-dart / rtkit).
4. Hashes → ~/m5boot/spec/inputs.md § Input v3, new filenames. Report reports/31-mtp-fwmem.md. Print exactly `DONE 31` (or `BLOCKED 31: <q>`). No dialogs.
