# Task 03 — Fix review findings (see ~/m5review/REVIEW.md, commit 0a23aaa)

Fix all of these, add a test for each where feasible, then rebuild `m5boot.bin` and publish the new SHA-256 in NOTES.md:
1. **MAJOR 1:** the start.S MMU-on path writes SCTLR = 0 (x9 is clobbered by `dcache_clean_inv_all`). Use a callee-saved register for the mask, clear **only** M|C (and I if justified), and keep the RES1 bits. Document that set/way is best-effort for system caches. Add a QEMU test that enters with the MMU+caches on (identity map set up by a small test pre-stub) to exercise this path (VM).
2. **MAJOR 2:** the reboot loop on early failure. Disable the WDT as early as possible: right after the minimal boot_args/ADT pointer validation, before any other check that can panic. Every panic screen must say whether the WDT was disabled. With no usable framebuffer, halt quietly (`wfe`), and document that a hold-power → Startup Options recovery is needed if the WDT was still armed.
3. **MAJOR 3:** invalidate the destination ranges (`dc ivac`) **before** copying the Image/initrd/FDT, and keep the clean after.
4. **MINOR 4:** with no `mem_actual`, run with no console. Bound `v_stride`, and check `stride*height` for overflow.
5. **MINOR 5:** validate the cmdline length before the first use.
6. **MINOR 6:** check payload offsets against the actual appended size; check Image alignment.
7. **MINOR 7:** overflow guards on `base + size` for ADT ranges.
8. **INFO 8:** confirm from Linux `arch/arm64/kernel/smp_spin_table.c` (fetch it into ref/) what happens with `cpu-release-addr = 0`. Report it; don't change the DTB.
9. **Real kernel in QEMU:** the J714s Image faulted under plain `qemu -kernel`. Our kernel uses **16K pages**, so try `-cpu max` (16K granule support). Boot the real Image + initramfs through m5boot in QEMU at EL1 and EL2 if it gets past early boot. Label it VM. Report how far it gets.

End with `DONE 03`.
