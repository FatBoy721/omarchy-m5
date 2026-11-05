# Task 15 — URGENT research: why does iBoot power off right after launching our raw boot object?

**NATIVE result:** m5boot (49 MB raw image: our code at offset 0x800 + an appended payload), installed via step2.sh (`kmutil configure-boot -c boot.bin --raw --entry-point 2048 --lowest-virtual-address 0`; the stub is Permissive and `coih` is set). On power-on: **a brief Apple logo, then the Mac powers fully off within about a second** (the MagSafe LED goes out). It repeated ~6 times, then iBoot fell back to Recovery ("macOS needs to be reinstalled"). No m5boot output was ever seen. The implementer is building a tiny probe (VBAR + WDT write + full-screen colour as the first actions).

Research only (no m1n1 code, per rule 7; the Asahi **docs** repo, Apple Platform Security, kmutil/bputil man pages, XNU and our own files are fine). Answer with citations, and mark HYPOTHESIS where needed:
1. What does iBoot do between drawing the logo and jumping to a custom/raw (fuOS) boot object? What failures make it **power off** (vs reboot, vs show an error)? Is "power off on a failed fuOS boot" documented anywhere?
2. **Size/format limits** for `kmutil configure-boot --raw`: maximum size? Must the image be a Mach-O or have a particular header? Alignment? Does kmutil store the image as-is (img4 payload in Preboot)? Inspect what kmutil actually wrote in the stub's Preboot over SSH, read-only (`ssh macbook`; the PM can run sudo reads if you give the exact commands). Compare its size with our 49,034,128-byte boot.bin.
3. The entry/load contract: is `--entry-point` an offset into the image or a virtual address, given `--lowest-virtual-address 0`? Where does iBoot load the image (physical), and with what MMU/EL state? Anything that would make execution at 0x800 wrong?
4. macOS 26 / mBoot-18000.x / T6050 changes that affect fuOS (SPTM, `smb1`/`coih` semantics, the "Cryptex1 Generation" difference we saw: main macOS `stng 4` vs stub `stng 6`).
5. Does iBoot keep a boot-failure counter that triggers the Recovery fallback after N failed fuOS boots? Do we need to clear anything before the next attempt?

Deliver `reports/15-fuos-launch.md`, ranked hypotheses with the cheapest discriminating test for each. End with `DONE 15`.
