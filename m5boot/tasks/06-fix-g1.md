# Task 06: fix review G1 (BLOCKER) + G5, then rebuild gz/probe/spin

See ~/m5review/REVIEW.md (focused review of 030390b).
- G1: REMOVE the unconditional entry paint at the hard-coded 0x10bd3110000. Per our own ADT dump, DRAM is dram-base 0x100_0000_0000 + 24 GiB, so it ends at 0x106_0000_0000, and that address is OUTSIDE this Mac. Paint only after a layout-independent check of boot_args Video (fixed offsets per spec: 30/32 bpp, sane geometry like 3024x1964, stride bounds), with the whole FB range inside [physBase, physBase+memSize) or inside the ADT DRAM range. Delete the hard-coded fallback entirely: no tier-3 console at an address iBoot did not report. If there is no valid FB, run silently (the WDT is already off), halt in wfe, and let a hold-power recovery apply.
- G5: bound tier-2 FB acceptance by the DRAM range instead of 1<<44.
- Keep G2/G3/G4 as they are. Add a host test proving that no write outside the reported FB can happen in the console/paint paths.
Rebuild m5boot-gz.bin, probe and spin; run the host + QEMU tests; publish the hashes. End with DONE 06.
