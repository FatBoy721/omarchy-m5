# 39: t09 analysis (NATIVE, `reports/native-t09.txt`) and t10

**Verdict:** the firmware is present, so loading is not the blocker. CPU_CONTROL stays at RUN, but nothing observable changes across the re-probe. t10 tests whether the MTP CPU ever executes anything.

## Decode (NATIVE values; interpretations marked)
| Address | Value | Meaning |
|---|---|---|
| SRAM TEXT +0x000 | 0x140000a5 | `b +0x294`: the reset branch of an AArch64 vector table. |
| TEXT +0x080..+0x08c | d538521c, d538601d, d538403e, 14000000 | `mrs x28, ESR_EL1`, `mrs x29, FAR_EL1`, `mrs x30, ELR_EL1`, `b .`: an exception entry that saves the fault syndrome and spins. Everything else in 0x0..0x100 is zero, which looks like normal padding between vector slots. **This is genuine RTKit EL1 firmware.** |
| DATA +0x54000.. | 0x2_94c0N483, step 0x1000 | 64-bit descriptors, one per 4 KiB page of the MTP SRAM (0x294c00000 + N*0x1000), attributes 0x483. HYPOTHESIS: the firmware's own MMU table. It is identical before and after the re-probe. |
| ASC +0x00 / +0x08 / +0x40 / +0x44 / +0x48 | 1 / 0x12345678 / 1 / 0x10 (RUN) / 0x4c | Identical before and after the re-probe. 0x48 is HYPOTHESIS: a CPU status word. Bits 2, 3 and 6 are not decoded yet; t10 reads the running NVMe coprocessor (ANS) for comparison. |
| wrapper +0x00 / +0x04 / +0x90 | 0x94c00001 / 2 / 0x61 | Boot base is SRAM TEXT with bit 0 = enable. Unchanged. |
| PS_PROT +0x20 / +0x48 | 1 / 1 | Every other word in 0..0x100 is 0 except +0 = 0x0501a040. At an 8-byte stride, +0x20 and +0x48 are slices 4 and 9, which are USB DART slices (dart-usb0 = 4, 5, 3, 4; usb2 = 8, 9, 7, 8). Slices 12 (AOP, +0x60) and 13 (MTP, +0x68) are 0. HYPOTHESIS: 1 = protection enabled on a live DART. |

## What blocks RUN (ranked hypotheses)
1. **The CPU took an exception early and is spinning in the vector `b .`.** It would never reach mailbox setup, which fits all the evidence: nothing is consumed and no DART fault is logged. The stub firmware writes ESR/FAR/ELR only into its own registers, so we can't see them.
2. **The CPU never executes at all.** RUN is accepted but the core is held in reset or has no clock.
3. **The firmware is in a post-iBoot state that a re-wake can't recover from.** This is aurora's QUIESCED finding (report 37).

## t10 (READ-ONLY, one boot, about 2 min)
- **SRAM checksums (new `op=sum`):** crc32 and non-zero word count of SRAM TEXT, DATA and the rest, taken twice before and once after the stock re-probe (RUN plus wake).
  - Any change in DATA or the rest means the CPU ran, which points to #1 or #3. That is a stack, BSS or log write.
  - All checksums identical means the CPU never ran, which points to #2.
- **Running comparator:** ANS (NVMe) ASC 0x0..0x100 and wrapper 0x0..0x100. These decode 0x48 and the wrapper words on a coprocessor that is known to run.
- **Module changes:** read-only windows `ansasc` (0x219600000) and `answrap` (0x219050000). These are the first reads outside the MTP block; there are still no writes. vermagic is unchanged (`7.2.2-m5slim+`).

**Next step depends on t10:**
- If checksums change, find where the IOP faulted. Candidates are the DART mappings it expects for DRAM segments (OS_LOG) and the IOP VA 0x1000000 segment-range mapping.
- If they don't change, compare the ANS and MTP wrapper and status words to find the missing release or clock bit (read-only).

## UPDATE 2026-11-05 (task 40)
t10 NATIVE produced no logs at all, and the Mac reset back to macOS about 141 s after the push. A hard crash about 20 s into boot fits that. The suspect is the ANS reads, the first reads outside the MTP block. I removed the ANS windows. t10b reads only the MTP block, skips SRAM beyond DATA (0xc0000+, not backed by an ADT segment), and saves the log to the ESP before each insmod.
