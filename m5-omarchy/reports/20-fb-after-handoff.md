# 20 — Framebuffer after the raw hand-off: what the working T6050 setups did

Sources (public, allowed):
- betizzel/omarchy-m5 @15cd70c1, local clone (MIT scripts; patches have no license grant, read only).
- edimoldovan/kernel `README.md`, edimoldovan/linux-aurora branch `t6050-j714c` `arch/arm64/boot/dts/apple/t6050-j714c.dts`.
- rolotrealanis98/m5pro-linux @aa42195e.
- XNU `pexpert/arm64/boot.h` (APSL, our `src/xnu-ref/boot.h`).
- Asahi docs @5acb80f.

No m1n1 code was read. Facts about m1n1 behaviour are second-hand from these repos' docs and are marked as such.

## Bottom line
1. **Nobody reads the FB from the ADT.** The working setups use **iBoot's boot_args `Video` fields**: m1n1 reads them and prints them as its `fb init:` line (REPORTED; betizzel's `scripts/mkinitramfs.py:42`: `FB_BASE=… # 0x10bd3110000, from m1n1's "fb init:" line`).
2. **J714s values (REPORTED, betizzel, macOS 26.5):**
   - base **0x10bd3110000**;
   - row bytes **0x2f40 = 12096** (= 3024 × 4);
   - **3024 × 1964**;
   - pixel **x2r10g10b10 in 32-bit words** (`0x3FF00000` = red; patch 0001 line 142);
   - STRICT_DEVMEM note: the FB "sits above the usable-RAM window m1n1 reports".
3. **iBoot leaves the display lit for fuOS; no display boot-arg and no backlight action are needed.** [Inference from REPORTED facts] edimoldovan's README: "m1n1 enables the framebuffer node only inside its per-chip display setup, which returns early for T6050". So on T6050, m1n1 does **no** display or DCP setup, yet betizzel gets "framebuffer console at native 3024x1964" (`docs/bringup.md:156`) and rolotrealanis98 photographs a console (`docs/smp-t6050-raw-path.md`). The panel and backlight stay as iBoot left them (logo on). No source mentions an SMC/backlight step. **The backlight being off is unlikely to explain our black screen.**

## Answers
**(1) Address/format source: boot_args (x0 at entry).** From XNU `boot.h`, `struct boot_args` (LP64, natural alignment):
| Offset | Field |
|---|---|
| 0x00 | `u16 Revision`, `u16 Version` |
| 0x08 | `virtBase` |
| 0x10 | `physBase` |
| 0x18 | `memSize` |
| 0x20 | `topOfKernelData` |
| **0x28** | **`Video.v_baseAddr`** |
| 0x30 | `v_display` |
| **0x38** | **`v_rowBytes`** |
| **0x40** | **`v_width`** |
| **0x48** | **`v_height`** |
| **0x50** | **`v_depth`** (bits 0–7 depth; 8 rotate; 16 scale; 24 boot-rotate) |
| 0x58 | `u32 machineType` |
| 0x60 | `deviceTreeP` |
| 0x68 | `u32 deviceTreeLength` |
| 0x6c | `CommandLine[]` |

The offsets are computed from the header, not observed on the device. [HYPOTHESIS] `v_depth` low byte = 30 on this panel; the ADT's "30bpp" matches x2r10g10b10 (4 bytes per pixel).

**(2) Display state / boot-args / panel:**
- No public note of iBoot blanking the display for fuOS, of a required display boot-arg, or of any backlight/SMC step.
- For **Linux later** (edimoldovan dts): `framebuffer0 { compatible = "apple,simple-framebuffer", "simple-framebuffer"; reg filled by the loader; status = "okay"; power-domains = <&ps_disp_cpu>; }`. The FB node must hold the **display power domain**, or PMGR may turn the display off once Linux runs. Our DT and `pd_ignore_unused` need checking for this.

**(3) Format/stride on T6050:** x2r10g10b10, 4 B per pixel, stride 12096 B, 3024 × 1964 (REPORTED, J714s). No other T6050 format is reported.

## Our address vs betizzel's [HYPOTHESIS, arithmetic only]
Ours (ADT vram) is 0x105D3110000; betizzel's is 0x10bd3110000, a difference of 0x6_0000_0000 = 24 GiB. Both are exactly **0x2CEF0000 below the top of DRAM** for a 24 GB machine (ours: 0x100_0000_0000 + 24 GiB) and a 48 GB machine respectively. betizzel's RAM size isn't stated. If that's right, **our address is plausibly correct**, and the black screen is caused by something other than the address.

## Candidate causes for our black screen, cheapest check first
1. **Read boot_args instead of the ADT.** Paint at `[x0+0x28]` with stride `[x0+0x38]`, and paint only if the values look sane. This removes address and stride doubt in one step.
2. **Writes stuck in the cache** [HYPOTHESIS]: if the MMU or D-cache is on at the offset-0 entry (not yet measured), stores to the FB may never reach memory. Clean with `dc civac` over the painted range plus `dsb sy`, or check `SCTLR_EL{1,2}.M/C` first and report them.
3. **Stride/format:** must be 32-bit words with stride 12096, not packed 30-bit. A value with the top 2 bits only (e.g. 0xC0000000) shows black.
4. **Exception level:** read `CurrentEL` and use the matching SCTLR. If code isn't running at all, nothing paints. probe2 not panicking doesn't prove it reached the paint loop. A watchdog-reset canary would prove execution (the WDT is already within m5boot's allowed writes).
5. Backlight/panel: unlikely per (2). Only test it after 1–4 are excluded, because touching SMC is outside the safety limits.


## CORRECTION 2026-11-04: the probe2 NATIVE claims above are RETRACTED
The owner photo shows step2-fast.sh printed "This is not the recoveryOS paired with Omarchy … Press enter to shut down" on **every** fast cycle. **probe2, gz2, beacon and beacon3 were never installed** (kmutil never ran); the black screen was the shutdown. Therefore:
- "H-ENTRY confirmed (entry at file offset 0)": **RETRACTED; H-ENTRY is UNTESTED**.
- "H4-firmware refuted" and "our code runs natively": **RETRACTED**; no new NATIVE evidence exists.
- The last real NATIVE results are still m5boot / m5boot-gz / probe v1 (iBoot panic after the `fuos` load).
- Cause of the failed cycles: report 18, correction section.
- For this report: the black-screen analysis assumed our code ran. It didn't. The boot_args/format findings (REPORTED) still stand and apply to the next real install.
