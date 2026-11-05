# Task 11 (URGENT): MMU-off FIRST, before any MMIO or FB write

**Hypothesis (PM):** iBoot enters our image at file offset 0 with the **MMU (and maybe D-cache) ON**, and its page tables map DRAM but **not MMIO** (or map it elsewhere). Our current entry order is VBAR → **WDT write (MMIO)** → paint → … and the MMU is only switched off later. The very first WDT store then faults, the VBAR handler also touches MMIO/FB and faults again, and the nested-fault guard halts in `wfe`. Result: black screen, power on, no reset, no beacon. That matches probe2 and gz2 natively, and predicts "no reboot" for the beacon.

Change all builds (beacon, probe, gz2):
1. **First instructions after the offset-0 branch:** mask DAIF, read CurrentEL, and use the matching SCTLR_ELx. If M or C is set: clean+invalidate the D-cache by set/way (all levels, from CLIDR), `dsb sy`, then clear M, C (and I), `isb`, `ic iallu`, `dsb`/`isb`. **Only then** set VBAR and do the WDT write, the paint and everything else. Record the original SCTLR value in a register/variable so the beacon/probe can report "MMU was on".
2. The exception handler must also make sure the MMU is off before any MMIO/FB access (it should already be, after step 1).
3. Keep the existing later MMU-off before the Linux jump; it becomes a no-op.
4. **QEMU test that reproduces the hypothesis:** a pre-stub that enables the MMU with an identity map of **DRAM only** (MMIO unmapped), then jumps to offset 0. With the OLD code the WDT write must fault and halt; with the NEW code the beacon/probe must work. That proves the fix.
5. Rebuild beacon2, probe, gz2. Publish the hashes. The beacon code bit "MMU on at entry" should now actually report what we saw.

End with `DONE 11`.

## Addendum (PM, NATIVE beacon result): reset after ~10 s = the EXCEPTION path
The beacon (sha 11e5d666, 1812efc) reset after about 10 s, black screen throughout. So our code ran, took an exception early (before any visible paint), and the handler's WDT re-arm worked (MMIO is reachable from the handler). Build **beacon3** = this task's MMU-off-first order + **stage-coded exception beacon**:
- Keep a `stage` variable, updated **before** each operation, in fine-grained steps. Suggested order:
  0. offset-0 branch landed
  1. SCTLR/CurrentEL read
  2. MMU-off sequence done
  3. VBAR set
  4. WDT disable done
  5. x0 (boot_args ptr) sanity-checked as a pointer
  6. boot_args header (Revision/Version) read
  7. Video fields read
  8. FB sanity passed
  9. paint started
  10. paint + cache clean done
  11. deviceTreeP read
  12. ADT header read
  13. ADT walk
  14. /vram lookup
  15. everything done
- **On exception:** WDT bite after `T = 10 + 10*stage` seconds (stage 0..15 gives 10..160 s).
- **If everything completes without an exception:** bite after **175 s** (a distinct "success").
- Document the table in NOTES.md and print it in your DONE message. Keep all other safety rules.
- QEMU: force an exception at a chosen stage (test hook) and check the bite value for at least 3 stages, plus the success value.
End with `DONE 11`.
