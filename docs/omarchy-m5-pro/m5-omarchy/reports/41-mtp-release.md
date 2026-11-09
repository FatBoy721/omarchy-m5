# 41: What releases the MTP core on T6050: ranked plan and tests t11–t13

**Correction to the t10b conclusion:**
- **What t10b proved (NATIVE):** RUN wrote nothing to SRAM TEXT or DATA. The crc32 values TEXT 0xfa7eca24 and DATA 0x83ccf837 stayed the same before (twice) and after the re-probe.
- **What it did not prove:** that the core never executed.
  - **CPU_STATUS says "not stopped".** By the Asahi ASC notes (`src/asahi-docs/docs/hw/soc/asc.md`, CC-BY 3.0, M1-era layout), CPU_STATUS = 0x4c means IRQ and FIQ not pending (bits 2 and 3) plus an unknown bit 6. CPU_STOPPED (bit 1) and CPU_IDLE (bit 0) are clear, so a core held in reset would be expected to show STOPPED.
  - **A spinning core writes nothing.** The TEXT vector at +0x80 (report 39) only saves ESR, FAR and ELR into registers and then spins on `b .`. A core that faults immediately and sits there leaves SRAM bit-identical too.
- **So two causes remain:**
  - (A) The core is held in reset or has no clock, and CPU_STATUS doesn't reflect that.
  - (B) The core starts, faults on its first memory or instruction access, and spins in the vector.

## Why (B) became likely (REPORTED/HYPOTHESIS)
- **Aurora's T6050 DT notes** (`aurora-silicon/linux` branch `j716c/t6050-dt`, `t6050-die0.dtsi`; read as GPL source):
  - "The boot loader leaves ANS running … post-M4 ANS is never reset through PMGR".
  - "iBoot leaves the AOP halted on locked dart-aop tables".
  - The SMC firmware is also left running by iBoot.
  - So **no T6050 coprocessor is publicly known to be cold-started by Linux**. ANS isn't a usable "release" comparator, because Linux never starts it.
- **Aurora's MTP handoff** (`mtp-live-v1`, report 37) explicitly keeps an **identity (DVA == PA) DART bypass**.
- **The IOP's own page table points at physical addresses.** The table in DATA (report 39) maps IOP VAs to the AP-physical SRAM addresses 0x294c0N000.
- **Our DART maps the firmware VAs, not the physical addresses.** It maps TEXT/DATA only at IOVA 0x1000000 and 0x1054000 (DT I3W iommu-addresses). If the IOP's accesses leave the core as DVA = 0x294c0N000, they go through DART-mtp. That covers the reset-vector fetch from the wrapper boot base (0x94c00001) or the first page-table walk. In that case they hit an IOVA we never mapped.
  - The DART reported no error (t02). Either fault reporting is masked, or (A) holds instead.

## Ranked plan
1. **t11 (read-only, MTP block only).**
   - Reads CPU_STATUS five times across a second.
   - Reads ASC 0x400 (bit 10 is "set when the CPU is started" on M1).
   - Reads the 0x800–0x82c IRQ configuration and events (an IRQ/FIQ latched by a fault would show there).
   - Reads the mailbox mirror at +0x8000.
   - Before and after the stock re-probe.
   - It's a cheap way to decode the status words.
2. **t12 (writes the MTP ASC CPU_CONTROL bit 4 only, the same write rtkit-helper makes).**
   - Sets RUN to 0, then back to 1, and reads CPU_STATUS 1–5 ms after each change.
   - Takes SRAM crc32 after each step.
   - If bit 1 (STOPPED) rises with RUN=0 and clears with RUN=1, the status word tracks the core, and it ran in t10b, so (B).
   - If CPU_STATUS doesn't move at all, the core is clocked off or held in reset, so (A).
3. **t13 (writes DART-mtp TCR on streams 0–4 plus ASC RUN, both inside the allowed MTP blocks).**
   - Sets `BYPASS_DART|BYPASS_DAPF` (TCR bits 1 and 2): identity DVA == PA, which is aurora's handoff contract.
   - Cycles RUN 0→1, then takes crc32 and the mailbox again, then does the stock re-probe.
   - **If the DATA crc changes or the mailbox drains, the blocker is the DART identity mapping.** The fix would then be a DT change (identity `iommu-addresses` for TEXT/DATA/OS_LOG, or bypass at hand-off), not power.
   - Under bypass, the stock re-probe's DMA buffers won't match. Judge t13 on the crc and mailbox before the bind.
4. **If t12 says (A):** the core release is outside the ASC. The only AP-visible candidates left are the wrapper registers.
   - Next step: a read-only wrapper map, then a single-bit test of the 0x294050000 +0x04 word (currently 2), to be reviewed before any write.
   - The PMGR `MTP_*` domains have no AP register (report 37). No PMGR writes.

Run order: t11 → t12 → t13, about 2 minutes each. t12 and t13 write only MTP ASC and DART-mtp registers. There are no reads or writes outside the MTP block, given the t10 crash.
