# Task 07: H-ENTRY / H-ALIGN probe (urgent)

NATIVE: the 192 KB probe ALSO hit the same iBoot panic loop, so size is NOT the cause. All 3 images (49 MB, 18.9 MB, 192 KB) fail identically after iBoot loads fuos.
Hypothesis H-ENTRY: iBoot may start executing at file offset 0 (our first 0x800 bytes are zeros = UDF), not at --entry-point 2048. An exception before our VBAR goes to iBoot vectors and becomes an iBoot panic.
Hypothesis H-ALIGN: the image size must be a multiple of 16 KiB (ours are not).
Build probe2 + spin2:
1. Put an unconditional branch to the real entry at offset 0 (e.g. b _entry). Fill the rest of the 0x800 pad with branches/NOPs that also reach the entry, so entry at 0 or anywhere in the pad works. Keep entry at 0x800 too.
2. Pad the total file size to a multiple of 16 KiB (0x4000).
3. The very first instructions at the entry stay VBAR, then the WDT write, then the boot_args-validated paint (G1 fix stays).
4. Host test: the bytes at 0 decode to a branch landing on the entry; the size % 0x4000 == 0.
Publish hashes. Make all builds (probe/spin/gz) use the same header from now on. End with DONE 07. Be quick.
