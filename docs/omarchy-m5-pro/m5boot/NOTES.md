# m5boot NOTES

## Sources (all in `ref/`, gitignored; fetched 2026-11-04)
| Source | Rev | License | AI instructions |
|---|---|---|---|
| apple-oss-distributions/xnu: `pexpert/pexpert/arm64/boot.h`, `pexpert/pexpert/device_tree.h`, `osfmk/arm64/start.s` | f6217f89 | APSL 2.0 (`APPLE_LICENSE`) | none (no CLAUDE/AGENTS/GEMINI.md) |
| AsahiLinux/docs | 5acb80f6 | CC BY 3.0 (`LICENSE`); attribute when quoting | none |
| dgibson/dtc (libfdt) | 54e54717 | libfdt: GPL-2.0-or-later OR BSD-2-Clause; we take **BSD-2-Clause** (`src/libfdt/BSD-2-Clause`) | `CLAUDE.md`/`AGENTS.md`: govern *contributions* to dtc (Assisted-by trailer, no Signed-off-by, never run release scripts). We only vendor, unmodified; nothing applies. |
| Linux `Documentation/arch/arm64/booting.rst` | torvalds/master | GPL-2.0 (docs) | none |
| Linux `drivers/watchdog/apple_wdt.c` | torvalds/master | GPL-2.0-only OR MIT | none |
| Linux `arch/arm64/kernel/smp_spin_table.c` | torvalds/master | GPL-2.0-only | none |
| Linux `lib/fonts/font_8x16.c` | torvalds/master | GPL-2.0 | none |

**License flag for PM:** `src/font8x16.c` is glyphs 0x20–0x7e extracted from the Linux GPL-2.0 font, so the m5boot binary is GPL-2.0 as long as it's linked. If m5boot needs a non-GPL license, swap the font.

Also: `spec/m5boot-spec.md` and `spec/inputs.md` (PM). Test-only: Debian stable arm64 netboot kernel
(`ref/testkernel/Image`, GPL-2.0, VM payload only, never shipped).

## Layout
- `src/start.S`: 2048-byte pad, `_start` at 0x800. Masks DAIF and saves x0, CurrentEL, SCTLR and PC.
  - If SCTLR.M or SCTLR.C is set: clean+invalidate all D-cache by set/way, then clear M and C.
  - Then sets up the stack, clears bss and calls `main(x0, el, sctlr, pc)`.
  - Also holds `dcache_civac_range` (by VA, to PoC) and `jump_kernel`.
- `src/link.ld`: linked at 0 and PC-relative only.
  - The build fails if any object has an ABS64/ABS32 relocation.
  - bss and the 64 KiB stack are **inside** the file as zeros, so the payload appended at `_payload` (the 64-byte-aligned end of the file) can't overlap them.
- `src/bootargs.[ch]`: our own offsets table for XNU boot_args (spec §2), decoded byte-wise with LE reads.
- `src/adt.[ch]`: bounds-checked ADT walker covering path, compatible, `reg` with `ranges` translation, and `{u64,u64}` range lists.
- `src/fdtpatch.[ch]`: libfdt patching covering `/memory`, `/reserved-memory`, `/chosen` (bootargs, initrd, framebuffer).
- `src/place.[ch]`: lowest-fit placement that avoids reserved ranges.
- `src/payload.[ch]` + `tools/mkpayload.py`: payload header format.
- `src/main.c`: steps 1–7 with on-screen `[m5boot] step N:` messages and `PANIC in step N`.
- `src/fb.c`: 8x16 console. It **wraps to the top instead of scrolling**: scrolling MBs of uncached FB is slow.
- Builds:
  - `make` builds `build/m5boot-code.bin` (HW) and `build/m5boot-vm-code.bin`.
  - `make build/m5boot.bin` runs `tools/check-inputs.sh`: every input's SHA-256 must appear in `spec/inputs.md`.
  - `make test` runs the host tests.
  - `tests/qemu-boot.sh IMAGE [INITRD]` runs the VM test.

## Payload format v2 (src/payload.h)
The header sits at the 64-byte-aligned end of the code, so `_payload` == the code file size. It is 64 bytes, little-endian:
- `"M5BOOTPL"`, version u32 = 2, hdr_size u32 = 64;
- then u64 `dtb_off, dtb_size, image_off, image_size, initrd_off, initrd_size`, with offsets from the header start;
- the blobs follow, each at a 64-byte-aligned offset;
- then a 16-byte trailer at align64(end of the last blob): `"M5PLEND!"` + u64 own offset.

`payload_parse` rejects:
- a wrong magic, version or header size;
- an offset that isn't 64-byte aligned or is past the caps;
- overlapping blobs;
- a missing DTB or Image;
- a trailer that is missing or doesn't match. That proves the data really extends as far as the header claims (review MINOR 6).

## Boot flow (after task 03)
1. **Entry** (start.S). Masks DAIF and saves x0, EL, SCTLR and PC.
   - If SCTLR.M or SCTLR.C is set:
     - clean+invalidate the D-cache by set/way;
     - then clear **only M and C**: the mask lives in callee-saved x23, and every other bit, including RES1, EE and I, is kept (review MAJOR 1).
     - I stays as found: booting.rst allows the I-cache on, and we `ic iallu` before the jump.
     - **Set/way is best-effort:** it maintains the PE's architected caches only, not system-level caches beyond them.
     - HYPOTHESIS H-ID: the mapping is identity.
2. **Step 1, reads only.** Decode boot_args.
   - CommandLine with no NUL inside BOOT_LINE_LENGTH → cmdline ignored, checked at parse time before any use (MINOR 5).
   - The console needs every one of these (MINOR 4):
     - memSizeActual known (layout matched);
     - 30 or 32 bpp;
     - w, h < 16384;
     - `w*4 ≤ stride ≤ 65536` (so stride*height can't overflow);
     - the whole FB inside `[physBase, physBase+memSizeActual)`, after VA → PA conversion.
   - Otherwise there is no console and m5boot runs silently.
   - Prints entry SCTLR and the current SCTLR.
3. **Step 2 = WDT, as early as possible** (MAJOR 2).
   - It needs only the ADT pointer/length check (inside DRAM) and the ADT lookup.
   - Interlock unchanged: write only if the ADT address == spec `0x2_8836_C000`, the size covers WD1_CTRL and the address isn't in DRAM.
   - The result is read back: "disabled" only if RESET_EN (bit 2) is clear afterwards.
4. **Step 3.** CNTFRQ ≠ 0, memSize valid with no overflow, topOfKernelData, `/chosen/memory-map` and carveouts.
   - Entries whose base+size overflows are skipped and counted (MINOR 7).
5. **Step 4.** Payload v2 + Image header checks. Image fields are capped.
6. **Step 5.** Placement. `place()` treats an overflowing avoid range as reaching the top and rejects wrapping windows (MINOR 7).
7. **Step 6.** **`dc ivac` over the kernel, FDT and initrd destinations BEFORE copying** (MAJOR 3), then copy, then patch the FDT.
8. **Step 7.** `dc civac` the same ranges, `ic iallu`, jump with x0 = FDT.

**Every panic** prints `PANIC in step N`, then `watchdog: <disabled | NOT disabled (...)>`, then halts in `wfe` with DAIF masked, with no writes.
- With no usable framebuffer the halt is **silent**.
- If the WDT was not disabled (interlock, or a failure before step 2), the WDT can reset the Mac and iBoot relaunches m5boot: a possible reset loop. **Recovery: hold power → Startup Options → Macintosh HD** (spec §10).

Unchanged from task 02 (still true):
- Usable RAM is `[align_up(topOfKernelData,2M), align_down(physBase+memSize,2M))`. The spec diagram vs H5 conflict is resolved to the smaller value.
- `/reserved-memory` `no-map` covers memory-map, carveouts, FB and m5boot + payload.
- The FB placeholder is reused.
- The format is x8r8g8b8 at 32 bpp and x2r10g10b10 at 30 bpp.
  - **New evidence for spec H8:** the J714s kernel itself writes `0x3ff00000`, which is pure red in x2r10g10b10, to its hard-coded FB (see below). That suggests the panel is 10-bit, so the bars may show it.
- stdout-path untouched; HW bootargs = the inputs.md suggestion minus `earlycon=efifb`.

## Decisions / findings
- **`-mstrict-align` (required).** With the MMU off, all data accesses are Device memory and unaligned accesses fault. The VM proved this: the first build took an alignment Data Abort (ESR 0x96000061) on an `stp` into `struct fb`. Keep the flag at least until the MMU is on.

## HYPOTHESES (settle at runtime on hardware)
- Spec H1–H9 apply. Each runtime check is in the step 1–3 printout.
- H-ID: see flow item 1.
- H-STALE: see flow item 8.
- H6b: carveout values are `{base,size}`.
- The stack/bss are now inside the image, so the task-01 H2 (free RAM after the image) is gone.

## Tests
- **Host** (`make test`; ASan/UBSan):
  - fb console;
  - boot_args, including both line lengths, no-match, and an unterminated cmdline;
  - FB validation: no memSizeActual, stride bounds, stride×height wrap, 30/16 bpp, FB past the end of DRAM, VA;
  - ADT walk/translation, truncation at every length, and overflowing ranges/reg;
  - placement, including an overflowing avoid range and a wrapping window;
  - FDT patching, including the J714s placeholder and the real J714s DTB;
  - payload v2 round-trip, truncated/misaligned/overlapping/oversized payloads.
- **VM** (`make qemu INITRD=...`; QEMU virt, NOT hardware), Debian test kernel, 5 runs:
  - EL1, EL2, **EL1 with MMU+caches on** and **EL2 with MMU+caches on**. The last two use the identity-map pre-stub `tests/mmu-prestub.S`, which also dirties lines in the kernel window.
    - SCTLR: EL1 `c5183d` → `c51838`, EL2 `1005` → `1000`. Only M and C are cleared.
    - All four reach `Run /init`.
  - The fake WDT is now outside the fake DRAM window (QEMU RAM at 0xbef00000, preloaded with RESET_EN), so the **real write path runs**: `WD1_CTRL before: 4`, `after: 0`, "watchdog disabled".
  - An **early-panic** run (no `/chosen/memory-map`) shows `PANIC in step 3` + `watchdog: disabled` + `halted`.
  - The VM build mirrors console text to the PL011 (`-DVM` only), so logs contain the step messages.
  - QEMU doesn't model caches, so the ivac-before-copy ordering is exercised but not *proven* in the VM.
- **VM, real J714s Image** (`tests/qemu-j714s.sh`, task item 9).
  - **Why it faulted before:** not the page size. The kernel already ran with `-cpu max`. Disassembly at Image offset 0x2285120 shows a loop that writes `0x3ff00000` in a 16×256 block to the **hard-coded PA `0x10bd3110000`**, stride `0x2f40` (3024 px × 4). QEMU had no memory there.
  - Gave QEMU 1100 GiB of sparse RAM (`memory-backend-ram,reserve=off`; m5boot's `/memory` still limits Linux to the fake window) and used QEMU's virt DTB.
  - Result: the J714s kernel boots through m5boot at **EL1 and EL2** to `Run /init`, unpacks our initramfs and starts `/init`.
  - **/init then dies:** `setsid: can't execute 'cttyhack'`, then `Kernel panic: Attempted to kill init! exitcode=0x7f00`. The initramfs busybox (1.37.0) has no `cttyhack` applet, yet `/init` line 20 does `exec setsid cttyhack sh`.
    - **This will happen on hardware too.** It is a PM artifact issue, not m5boot, and was reported, not changed.
  - **For the PM (safety):** the J714s kernel writes to a fixed physical FB address very early, whatever the boot_args say. If iBoot's FB isn't at `0x10bd3110000` on a given boot, that is a write to unknown memory.

## Spin-table (review INFO 8)
Read Linux `arch/arm64/kernel/smp_spin_table.c` (fetched into `ref/linux/`):
- `smp_spin_table_cpu_init` only reads `cpu-release-addr` with `of_property_read_u64`. A value of 0 parses fine.
- `smp_spin_table_cpu_prepare` then does `if (!cpu_release_addr[cpu]) return -ENODEV;` **before** any `ioremap_cache`/`writeq_relaxed`.

So `cpu-release-addr = <0 0>` gives no write to PA 0. The secondary CPU just fails to come up. `maxcpus=1` avoids even that. DTB not changed.

## Release artifact (FINAL, task 04)
`build/m5boot.bin` (not committed, local-only: the Image has no redistribution grant, per inputs.md).
- **49,034,128 bytes, sha256 `039adce60427abf1d121ba321409c5132caecbf0f599c8fb5a872abdd09cbe55`**
- Code at fc09744 (includes review R1: the payload trailer read is bounded by `physBase+memSize`, with host tests).
- Inputs: the updated `spec/inputs.md`, all verified by `tools/check-inputs.sh` at build time.
  - Image `9c377f51…b5e6`: kernel with the fixed-address fb marker disabled.
  - initramfs.cpio.gz `37237b5c…e48b`: fixed `/init`.
  - DTB `23dabefb…1d6d`: unchanged.
  - The superseded hashes are listed without a path in inputs.md, so `check-inputs.sh` (path + hash on one line) cannot accept them.
- VM (QEMU virt, NOT hardware), `tests/qemu-j714s.sh` with these inputs:
  - EL1 and EL2: m5boot steps 1–7 (watchdog disabled), kernel, `Run /init`, initramfs shell prompt.
  - **dropbear running** (`[71] Not backgrounding`).
  - No `Attempted to kill init`.
- The same kernel also boots to the shell with plain 2 GiB QEMU RAM, which confirms the hard-coded FB write at `0x10bd3110000` is gone.
- Superseded builds: `19c80486…` (task 02) and `629958d5…` (task 03, old Image/initramfs).

## Task 05: native reset loop → probe, spin and gz builds
**Native evidence (PM):** about 6 cycles of a brief Apple logo followed by power-off, with no m5boot output. `spec/native-panic-1.json` shows the iBoot stages `... fuos` (load start/end), then `iBoot Panic: 3bdace14b1a9a68:1026` (mBoot-18000.161.10). So our code most likely never ran: iBoot died after loading the 49 MB fuOS and before the hand-off. The same trace shows `0x1ff8000` (~32 MiB), possibly a fuOS size limit (**HYPOTHESIS H-SIZE**; the spin/probe/gz builds below test it).

All three builds start the same way (`src/early.inc`, start.S `PROBE`), before any boot_args parsing:
1. Set VBAR to our own vectors (`probe_vectors`). Any exception paints a full-screen colour and prints ESR/ELR/FAR, then halts in `wfe`. It never returns to iBoot's vectors.
2. Do the single WDT write: `0` to `0x2_8836_C01C` (spec §4/§5 [OURS], from our ADT dump of this Mac), reading the register before and after.
3. ~~Fill the whole fallback FB at the hard-coded `0x10bd3110000`~~. **REMOVED in task 06 (review G1 BLOCKER):** that address lies outside this Mac's DRAM (ADT dram-base `0x100_0000_0000` + 24 GiB ends at `0x106_0000_0000`). See the task 06 section.

**Probe** (`make build/m5boot-probe.bin`, `-DPROBE -DPROBE_HALT`, 2× font):
- The console source was replaced in task 06 by one DRAM-bounded check (`src/probefb.c`); there is no fallback.
- The screen shows:
  - EL, SCTLR, CurrentEL, image base, VBAR;
  - WD1_CTRL before/after;
  - a hex dump of the first 0x180 bytes of boot_args;
  - bootFlags/memSizeActual under both line lengths;
  - the ADT, memory-map counts;
  - steps 4–6 run on the real DTB plus a 64-byte stub Image.
- Step 2 only verifies the WDT; it makes no second write.
- Each step paints a bar in its own slot in a reserved right-hand strip.
- Ends with `PROBE COMPLETE`, then `wfe`.

**Spin**: rewritten in task 06 (see there).

**gz** (`build/m5boot-gz.bin`): the same probe instrumentation, but the payload is the real `Image.gz` + DTB + initramfs.
- Inflated by `src/inflate.c`:
  - our own DEFLATE/gzip decoder written from RFC 1951/1952 (IETF specs; no code copied);
  - every read and write is bounds-checked;
  - ISIZE is verified, CRC32 is not;
  - host test `tests/test_inflate.c` compares against Python gzip at levels 0/1/9 and against the real Image.gz, and checks that truncation and a short output buffer fail.
- The kernel is inflated to scratch RAM chosen by `place()`, then copied (ponytail: one extra pass).
- The build fails if the object is ≥ 24 MiB.
- A 10-second on-screen countdown runs before the jump. `jump_kernel` re-masks DAIF, because the probe unmasked SError.
- Inflating with the MMU (and therefore the D-cache) off will be slow (**HYPOTHESIS**: tens of seconds). The step 5 text says so.

Task 05 hashes, **SUPERSEDED by task 06 (G1 BLOCKER: do not install)**:

| Build | Bytes | SHA-256 |
|---|---|---|
| `build/m5boot-probe.bin` | 192,656 | `d1cdc4f0b53ded9d6c2905d5b25f119590f9dc283d3d49780a0445c946839eb0` |
| `build/m5boot-spin.bin` | 2,140 | `0e2e68af03bee4364ecb83c6b17884bc543dfa2d076d2391aae22589a7d066d9` |
| `build/m5boot-gz.bin` | 18,893,840 | `37c4dd7c89ce5ff72c18ada0465f8bf69873a33483ce3d50816bea083c2e1846` |

The inputs are verified by `check-inputs.sh`: DTB `23dabefb…`, Image.gz `63835275…` (which inflates to exactly Image `9c377f51…`), initramfs `37237b5c…`. None of the builds are committed; the gz build is local-only like the Image.

**VM (QEMU virt, NOT hardware)**, `tests/qemu-probe.sh`:
- probe EL1 and EL2: `PROBE COMPLETE`.
- bad layout (no plausible memSizeActual): the console comes from the geometry-only tier, and the run still reaches `PROBE COMPLETE`.
- forced `brk`: the vectors print `ESR f2000055 ELR …4950 FAR 0` and halt.
- no memory-map: `PROBE HALTED`.
- spin: WD1_CTRL goes 4 → 0, and the FB is filled exactly to its last pixel.
- gz: m5boot inflates the real Image.gz (16,331,363 → 46,483,968 bytes), runs steps 4–6, shows the summary and the 10 s countdown, then jumps. Linux reaches `Run /init`, the shell, and dropbear (`Not backgrounding`).

**Reading a native run:**

| Screen | Meaning |
|---|---|
| No colour at all | Our first instructions never ran: iBoot load/hand-off, not our code |
| Spin shows colour, gz/probe don't | Size or format |

## Task 06: review G1 (BLOCKER) + G5 fixed
- **G1:** the unconditional entry paint at `0x10bd3110000` and the hard-coded fallback console are **deleted** (`early.inc` now does the WDT write only; no `FBF_*` anywhere).
  - The probe, gz and spin builds take a framebuffer only from `src/probefb.c:probe_fb()`, which is layout-independent:
    - boot_args Video, which sits at fixed offsets 40..87;
    - `ba_fb_check` geometry: 30/32 bpp, w,h < 16384, w*4 ≤ stride ≤ 65536;
    - the **whole** `[base, base+stride*height)` must lie inside DRAM. DRAM is ADT `/chosen` `dram-base`/`dram-size` (spec §3 [OURS]; the ADT is found through deviceTreeP/Length at fixed offsets 96/104). It is used only if it contains physBase; otherwise DRAM is `[physBase, physBase+memSize)`.
  - The solid full-screen colour is painted only after that check (`probe_con` in main.c, and `src/spin.c`).
  - With no valid FB, the build runs silently: the WDT is already off, and it halts in `wfe` (recovery: hold power).
- **G5:** the old `1<<44` tier-2 bound is gone; the DRAM range above is the only bound.
- **Spin** is now `start.S` (VBAR + the WDT write) + `src/spin.c` (validated fill, then `wfe`). It is 75 KB, mostly the 64 KiB zeroed stack.
- **New host test `tests/test_fbsafe.c`** (ASan/UBSan, FB_SCALE 1 and 2):
  - `probe_fb` accepts an FB inside ADT DRAM above memSize;
  - it rejects an FB that straddles the DRAM end, lies past it (the G1 case, 47 GiB above dram-base), lies below physBase, or has bad geometry;
  - with no ADT DRAM props, it checks the exact physBase+memSize edge;
  - the paint paths (full fill, clipped and out-of-range `fb_rect`, 2000 wrapped console lines beside the bar strip) leave the guard bytes before/after the FB and the stride padding untouched.
- **VM (QEMU virt, NOT hardware)**, `tests/qemu-probe.sh`; the fake ADT now has `dram-base`/`dram-size`:
  - probe EL1/EL2/bad-layout reach `PROBE COMPLETE`, and the console comes via ADT DRAM;
  - the fault run prints ESR/ELR/FAR;
  - the no-memory-map run gives `PROBE HALTED`;
  - **FB reported outside DRAM:** no console, `PROBE COMPLETE` on the serial port only;
  - gz inflates, counts down and reaches `Run /init` and dropbear;
  - spin with a valid FB: WDT 4→0, FB filled to the last pixel;
  - **spin with the FB outside DRAM: WDT 4→0 and zero FB writes.**

| Build (task 06) | Bytes | SHA-256 |
|---|---|---|
| `build/m5boot-probe.bin` | 192,720 | `b3dbc9620427b390188b31401f107cf53b01f9cea8ded34d650cf85a83c35586` |
| `build/m5boot-spin.bin` | 75,424 | `046e376bb262936bf682906d6ce5cae8d228906b6be94b767bafe06941c2b561` |
| `build/m5boot-gz.bin` | 18,893,904 | `dfab8d046940ce22f7a4af60bbfd36115c0c362c20645ef2871b3a3ec46e86fb` |

The inputs are unchanged and verified by `check-inputs.sh`.

**Reading a native run:**

| Screen | Meaning |
|---|---|
| Solid colour | Our code ran and iBoot's FB passed the check |
| Black and no reset loop | Our code may have run (WDT off) but found no valid FB, or iBoot never handed off. The SOCD panic log tells which |

## Task 07: H-ENTRY / H-ALIGN
The 192 KB probe also hit the iBoot panic natively, so size is not the cause. Two new hypotheses, both tested by these builds:
- **H-ENTRY (HYPOTHESIS):** iBoot starts executing at file offset 0, not at `--entry-point 2048`.
  - **Change:** the 0x800 header (start.S `.header`) is now 512 × PC-relative `b _start`, so a start at offset 0 or at any word in the pad lands on the real entry at 0x800. The entry itself is unchanged: VBAR, then the WDT write, then the boot_args/DRAM-validated paint (the G1 fix stays).
  - **Applies to every build** (normal, probe, gz, spin), since they all share start.S.
- **H-ALIGN (HYPOTHESIS):** the file size must be a multiple of 16 KiB.
  - **Change:** `mkpayload.py` zero-pads after the trailer. The trailer is found through the header, so the padding is never parsed. Spin is padded with `truncate -s %16384`.
- **Host test `tests/test_header.py`** (run on all built images): every word in [0, 0x800) decodes as A64 `B` landing on 0x800, the word at 0x800 is `msr daifset,#0xf`, and size % 0x4000 == 0. `test_core` now allows zero padding after the trailer.
- **VM (QEMU virt, NOT hardware):**
  - The probe started at offset 0 and at offset 0x7fc both report entry `PC=40200800` and reach `PROBE COMPLETE`.
  - All the task 06 runs still pass (EL1/EL2/bad-layout/fault/no-memory-map/FB-outside, gz to dropbear, spin valid/outside).

| Build (task 07) | Bytes | SHA-256 |
|---|---|---|
| `build/m5boot-probe.bin` | 196,608 | `67223e7071f0faf59b14090b226d82a8c4429915403db750e93af3b7590131fc` |
| `build/m5boot-spin.bin` | 81,920 | `235e5110684495a85c8963305ef217fbcfa2fd2382e8c1a3863924fc8e9bc9e2` |
| `build/m5boot-gz.bin` | 18,907,136 | `b88591143d6e418599434c8ca4799525ecb1408812440339828fe54e02b09ddb` |

> **CORRECTION 2026-11-04 (PM): the "native" results reported for tasks 08–11 are INVALID.**
> - The fast-cycle installs never happened: a step2-fast pairing-check refused them. **probe2, gz2, beacon and beacon3 never ran natively.** The black screens were shutdowns, not our code.
> - **H-ENTRY (iBoot enters at file offset 0) is UNTESTED**, not confirmed. The branch header (task 07) stays: it is harmless if entry is at 0x800.
> - **The "beacon reset after ~10 s" (task 11) is INVALID** as evidence. The exception-path conclusion and "MMIO reachable" are unproven.
> - **Not covered by this correction:** task 05's native result (the 49 MB m5boot `039adce6…` → iBoot panic after loading fuos, `spec/native-panic-1.json`) and task 07's "the 192 KB probe also panicked". Whether those installs really happened is for the PM to confirm. The task 08–11 code changes (vram tiers, beacon, MMU-off first, stage-coded beacon) were made on those wrong premises, but each one is still a safe, defensive change, and its VM tests stand.
> - The original text below is kept as history; the affected lines are marked **[INVALID, see correction]**.

## Task 08/09: first native foothold → vram FB tiers; gz2 (slim kernel)
**[INVALID, see correction] NATIVE (probe2 `67223e70`):** no iBoot panic, no loop, power stays on, black screen. **H-ENTRY confirmed:** iBoot enters at file offset 0, and the task 07 branch header fixes it. Our code ran and halted with the WDT off, but the task 06 DRAM check rejected the FB.

**FB selection (`src/probefb.c`, used by the probe, gz and spin builds), in this order:**
- (a) the boot_args Video base, if the whole FB lies inside the runtime ADT `/vram` reg (translated) and the geometry is sane;
- (b) the runtime `/vram` base with the boot_args geometry, if it fits;
- (c) last resort: the **OBSERVED-BY-US** vram region `0x105_D311_0000 + 0x57AC000` (task 09, from our ADT dump of this Mac) with 3024×1964, stride 3024×4, x2r10g10b10.

The selected FB always lies wholly inside a vram region. The tier used, the ADT ptr/len, whether it parsed, and the `/vram` reg are shown on screen, next to the existing dumps:
- boot_args hex (0x180 bytes);
- every line-length decode;
- physBase/memSize/memSizeActual;
- EL/SCTLR, image base, VBAR;
- WD1_CTRL before/after.

**Tests:**
- **Host:** `tests/test_fbsafe.c` covers:
  - tier a, including an FB ending exactly at the vram end;
  - tier b, when the Video base is outside /vram (the G1 address, straddling the end, below it);
  - tier c (no /vram, /vram too small, bad geometry);
  - an invariant check that the whole FB lies inside its region;
  - the paint-path guard checks.
- **VM** (QEMU, not hardware): the fake ADT has `/vram` at `0xb8000000 +2 MiB`. The VM build's tier c region is `0xb9000000`.
  - The probe at EL1/EL2, entry at offset 0 and 0x7fc, bad layout: tier a, `PROBE COMPLETE`.
  - Video base outside /vram: tier b at the /vram base.
  - No /vram: tier c at the VM-observed region.
  - The fault run still prints ESR, and the no-memory-map run gives `PROBE HALTED`.
  - Spin tiers a/b/c paint exactly the expected region (first/last pixel set, the next byte and the other region untouched); WDT 4→0.
  - gz with the main Image.gz reaches `Run /init` and dropbear.

**gz2 (task 08) = the gz code with the slim inputs** (spec/inputs.md, task-17 slim section, all verified):
- DTB `23dabefb…`;
- slim Image.gz `b3c6bfa6…`, which inflates to exactly slim Image `09c771f1…`;
- initramfs-slim `1e0f73cc…`.

`check-inputs.sh` now also accepts paths without backticks (the slim table has none); the match is still exact on path + hash on one line. The build target is `make build/m5boot-gz2.bin IMAGEGZ2=… INITRD2=…`.

**VM limits for gz2:**
- m5boot inflates the slim kernel (3,105,641 → 7,907,336 bytes), places it, patches the FDT, counts down and jumps.
- The slim `.config` has **no PL011/earlycon** (allnoconfig + m5-slim), so QEMU cannot show its console. The VM shell + dropbear check therefore runs the same gz code with the main Image.gz.
- **Slim-kernel boot is unverified in the VM**; it is decided natively.

| Build (task 09) | Bytes | SHA-256 |
|---|---|---|
| `build/m5boot-gz2.bin` | 5,455,872 | `df5f8d41bf4217466a7773689cab5ff125b9d2270a2a22ae481c28e87537b512` |
| `build/m5boot-probe3.bin` | 196,608 | `25b87f4c83c25a0def477ba701f7d77d4a36ff50ff4aac3bd94438394d4540fa` |
| `build/m5boot-spin.bin` | 81,920 | `dd4bab1ba81d32c9d00cddc586c2b3c84dad1b6ceaee1d2fe45762010a4de392` |

## Task 10: beacon (screen-independent output via a timed WDT reset)
**[INVALID, see the 2026-11-04 correction above Task 08/09] NATIVE:** gz2 `df5f8d41` and probe2 both run (no panic, power on), but the screen stays black.

`build/m5boot-beacon.bin` = start.S entry (branch header at 0, VBAR, then the WDT disable) + `src/beacon.c`:
1. Compute the code.
2. Re-arm WD1 to bite after **T = 20 + 10·code s**.
3. Try the vram-bounded paint (tiers a/b/c, as in task 09).
4. `wfe`.

The exception handler beacons code 15.

- **WDT sequence:** from Linux `drivers/watchdog/apple_wdt.c` (`ref/linux/apple_wdt.c`, GPL-2.0-only OR MIT): `set_timeout` = CUR_TIME←0, BITE_TIME←rate·T; `start` = CUR_TIME←0, CTRL←RESET_EN (bit 2).
- **Rate = 24 MHz [SRC]:** the J714s DTB in spec/inputs.md has `watchdog@28836c000 clocks = <&clock-ref>`, a fixed-clock with `clock-frequency = 0x16e3600`. 170 s × 24 MHz < 2³², so it fits the 32-bit BITE register.
- **Owner-authorised exception (task 10)** to the CLAUDE.md "WDT-disable register only" rule: the beacon also writes WD1_CUR_TIME (+0x10) and WD1_BITE_TIME (+0x14), and CTRL (+0x1c) = 4, at `0x2_8836_C000`. Nothing else changes.

**SUPERSEDED by the addendum below**. First version (`a1815077…`), code = `stage*3 + layout`:
- **layout:** 0 = none plausible, 1 = BOOT_LINE_LENGTH 608, 2 = 1024. `bootargs_parse` can only detect 608/1024, so "other" reads as 0.
- **stage:**
  - 0 = boot_args not sane (revision/version not 1/2, memSize 0, physBase 0, or overflow);
  - 1 = sane, but the ADT pointer is invalid or doesn't parse;
  - 2 = ADT parsed, no `/vram`;
  - 3 = `/vram` found, but the Video base is not inside it;
  - 4 = Video base inside `/vram` (tier a).
- **15** = exception (VBAR handler).

| T (s) | code | stage | layout |
|---|---|---|---|
| 20 / 30 / 40 | 0 / 1 / 2 | 0 boot_args insane | none / 608 / 1024 |
| 50 / 60 / 70 | 3 / 4 / 5 | 1 ADT bad | none / 608 / 1024 |
| 80 / 90 / 100 | 6 / 7 / 8 | 2 no /vram | none / 608 / 1024 |
| 110 / 120 / 130 | 9 / 10 / 11 | 3 Video not in /vram | none / 608 / 1024 |
| 140 / 150 / 160 | 12 / 13 / 14 | 4 Video in /vram | none / 608 / 1024 |
| 170 | 15 | exception | — |
| no reset (power stays on) | — | the beacon never armed (died before main, or iBoot never entered) | — |

**Reading it:**
- Time from power-on to the first reset includes iBoot's own boot time before our entry, which is a few seconds (**HYPOTHESIS**; its exact length is unknown).
- Codes are 10 s apart, so round down to the nearest row: the offset is safe as long as it is under 10 s.
- The 24 MHz rate is [SRC] from the DT. If the Mac resets much faster or slower than any row, the rate assumption is wrong.
- **After the bite, iBoot relaunches the beacon, which resets again** (a periodic loop). Take the first interval, then hold power → Startup Options → macOS.

**Tests:**
- **Host:** `tests/test_beacon.c` covers the packing for every stage/layout, `T = 20 + 10c` < 2³²/24e6, and the clamp to 15. On a fake MMIO block it checks CUR=0, BITE=24e6·T, CTRL=4, and that no other register is touched.
- **VM** (`tests/qemu-beacon.sh`, entry at file offset 0), the fake WDT BITE register matches in every case:
  - full: code 14 → `0xe4e1c000`;
  - bad layout: 12;
  - Video outside /vram: 11;
  - no /vram: 8;
  - forced `brk`: 15 → `0xf32fdc00`.

  CTRL = 4. The FB is painted when a vram tier exists.

### Task 10 addendum (PM; from `~/m5-omarchy/reports/20-fb-after-handoff.md`, read as allowed)
1. **Fixed-offset boot_args FB:** Video at 0x28 base / 0x38 rowBytes / 0x40 width / 0x48 height / 0x50 depth (XNU boot.h; the same offsets `bootargs_parse` always used). It is painted only if strictly sane: 3024×1964, stride 12096, depth low byte 30/32, and the whole range inside DRAM (runtime ADT `/chosen` dram-base/size, else spec §3 [OURS] `0x100_0000_0000 + 24 GiB`). Otherwise the vram tiers a/b/c are used.
2. **Cache:** after the paint, `dc civac` over the painted range + `dsb sy` (`dcache_civac_range`). The SCTLR bits come from the value start.S reads at entry for the current EL, **before** it clears M/C.
3. **Order:** compute the code (cheap reads) → arm the WDT → paint → clean → `wfe`. Arming first keeps the paint time (seconds, if uncached) out of T.

**Code (4 bits, PM priority order).** Entry reached is implied by any reset.

| Bit | Weight | Meaning |
|---|---|---|
| 3 | 8 | MMU on at entry (SCTLR.M) |
| 2 | 4 | D-cache on at entry (SCTLR.C) |
| 1 | 2 | boot_args Video base == ADT `/vram` base (runtime ADT; if not found, the observed `0x105_D311_0000`) |
| 0 | 1 | Video geometry sane (3024×1964, stride 12096, 30/32 bpp) |

**Dropped (did not fit 16 values):** layout matched, boot_args sanity. **T = 20 + 10·code s** (20..170). **Exception: T = 10 s.** It sits below every data code, because 16 → 180 s would overflow the 32-bit BITE register at 24 MHz.

| T (s) | code | MMU | D$ | base==vram | geom |
|---|---|---|---|---|---|
| 10 | exc | — | — | — | — |
| 20 | 0 | 0 | 0 | 0 | 0 |
| 30 | 1 | 0 | 0 | 0 | 1 |
| 40 | 2 | 0 | 0 | 1 | 0 |
| **50** | **3** | 0 | 0 | 1 | 1 ← expected if all is as believed |
| 60 | 4 | 0 | 1 | 0 | 0 |
| 70 | 5 | 0 | 1 | 0 | 1 |
| 80 | 6 | 0 | 1 | 1 | 0 |
| 90 | 7 | 0 | 1 | 1 | 1 |
| 100 | 8 | 1 | 0 | 0 | 0 |
| 110 | 9 | 1 | 0 | 0 | 1 |
| 120 | 10 | 1 | 0 | 1 | 0 |
| 130 | 11 | 1 | 0 | 1 | 1 |
| 140 | 12 | 1 | 1 | 0 | 0 |
| 150 | 13 | 1 | 1 | 0 | 1 |
| 160 | 14 | 1 | 1 | 1 | 0 |
| 170 | 15 | 1 | 1 | 1 | 1 |
| no reset | — | beacon never armed | | | |

The rounding caveat above still applies: iBoot's time before our entry is added, so round down to the nearest row.

**Tests:**
- **Host:** `tests/test_beacon.c` covers:
  - each bit, including depth rotate bits being ignored;
  - the fixed-FB DRAM bound: exact end accepted, +4 rejected, below the base rejected, the G1 `0x10b_d311_0000` rejected;
  - 20+10c and the exception's 10 s;
  - WDT sequence on a fake block, with only CUR/BITE/CTRL touched.
- **VM** (`tests/qemu-beacon.sh`, entry at offset 0; VM geometry 640×480), BITE = 24e6·T and CTRL = 4 in every case:

  | Case | Code | T |
  |---|---|---|
  | plain | 3 | 50 s; fixed-offset FB painted |
  | Video base outside DRAM/vram | 1 | 30 s; tier b painted |
  | forced `brk` | exc | 10 s |
  | MMU+D-cache on at entry (identity-map pre-stub) | 15 | 170 s |

| Build | Bytes | SHA-256 |
|---|---|---|
| `build/m5boot-beacon.bin` (task 10, first version: SUPERSEDED) | 81,920 | `a1815077aa6e8d452310d55b031d93713cbb624809c8105b4c9b0ea7cf17d024` |
| **`build/m5boot-beacon.bin` (task 10 + addendum)** | 81,920 | `11e5d666a4158b12bc9ca0cbb102186281fd18e5bbb7f64176ff8faf327b99f1` |

## Task 11: MMU-off FIRST + beacon3 (stage-coded)
**PM hypothesis:** iBoot enters with the MMU (and D-cache) on, and its page tables don't map MMIO. The old order (VBAR → WDT store → …, MMU off later) faults on the first MMIO store, and the handler faults again.

**[INVALID, see the 2026-11-04 correction above Task 08/09] NATIVE:** beacon `11e5d666` reset after ~10 s, which is its exception code. So an exception was taken early, and the handler's WDT re-arm worked. *(The beacon never ran: this 10 s result is not ours.)*

**Change (start.S, all builds).** The first instructions after the offset-0 branch are:
1. Mask DAIF.
2. Read CurrentEL and the matching SCTLR_ELx (kept in x21 for reporting).
3. If M or C is set: clean+invalidate the D-cache by set/way (all levels from CLIDR, `dsb sy`), then clear **M, C and I**, `isb`, `ic iallu`, `dsb`, `isb`.
4. **Only then** set VBAR, do the WDT write, and everything else.

The exception handler also clears M/C/I before touching MMIO or the FB. The pre-jump MMU-off path is unchanged and is now a no-op.

**Repro (VM):** `tests/mmu-prestub.S -DDRAM_ONLY` maps only [1G,2G) (m5boot, boot_args, ADT) with M|C|I on. The fake WDT/FB at 0xb8…/0xbe… are unmapped. It enters at file offset 0. `tests/qemu-mmufirst.sh`:
- **OLD code** (beacon/probe from 1812efc): WD1 BITE stays 0 and the FB stays 0. The first MMIO store faults, so it is never armed and never painted. This reproduces the hypothesis.
- **NEW code:** the beacon arms and paints. The probe reaches `PROBE COMPLETE` and reports entry `SCTLR=c5183d` (M, C, I set) → now `c50838`.

### beacon3: stage-coded exception beacon (+ the owner's early green paint)
A `beacon_stage` word lives in `.data`, not bss, so the bss clear can't reset it. Stages 0–4 are set in start.S and 5–16 in `src/beacon.c`, each **before** its operation.
- **On exception, or on a failed check** at stage s: WD1 bites after **T = 10 + 10·s**. A failed check uses the same timing as a fault at that stage.
- **Full success:** **T = 175 s**.
- **Stage 5 (owner):** right after the WDT disable and **before boot_args is touched**, the beacon paints **bright green** (x2r10g10b10 `0x000ffc00`) over the OBSERVED vram region `0x105_D311_0000`, 3024×1964, stride 12096, then `dc civac` + `dsb sy`. A static assert keeps the painted size within the region (`0x57AC000`).

| T (s) | stage | operation started (fault/failed check here) |
|---|---|---|
| 10 | 0 | offset-0 branch landed (before VBAR: a fault here goes to iBoot, no beacon) |
| 20 | 1 | SCTLR/CurrentEL read (same caveat) |
| 30 | 2 | MMU-off sequence (same caveat) |
| 40 | 3 | VBAR set |
| 50 | 4 | WDT disable |
| 60 | 5 | GREEN paint of the observed vram region + clean |
| 70 | 6 | x0 sanity (non-zero, 8-aligned, inside the observed DRAM `0x100_0000_0000 + 24 GiB`) |
| 80 | 7 | boot_args header (Revision/Version must be 1 or 2) |
| 90 | 8 | Video fields read (`bootargs_parse`) |
| 100 | 9 | FB sanity (3024×1964, stride 12096, 30/32 bpp, inside the observed DRAM) |
| 110 | 10 | boot_args-FB paint started (magenta; skipped if not sane) |
| 120 | 11 | paint + clean done |
| 130 | 12 | deviceTreeP (inside boot_args DRAM, length fits) |
| 140 | 13 | ADT header (nProps/nChildren ≤ 0x10000) |
| 150 | 14 | ADT walk (`/chosen` found) |
| 160 | 15 | `/vram` lookup |
| 170 | 16 | final arm |
| **175** | — | **success: everything done** |
| no reset | — | the beacon never armed (death before stage 3, or after the success arm failed) |

Stages 0–2 run before our VBAR is set, so a fault there goes to iBoot's vectors, not ours. Those rows only appear if a later stage's handler reads a stale value; they are kept for completeness.

**Tests:**
- **Host:** `tests/test_beacon.c` checks 10+10s for s = 0..16, the clamp, success 175, and that all fit in 32 bits at 24 MHz.
- **VM** (`tests/qemu-beacon.sh`). A VM-only hook (u32 at 0x44020000 = s+1) makes `STAGE(s)` execute `brk`. BITE = 24e6·T and CTRL = 4 in every case:

  | Case | T | Screen |
  |---|---|---|
  | success | 175 s | green region filled to its last pixel, next byte 0; magenta FB |
  | fault at stage 5 | 60 s | nothing painted |
  | fault at stage 6 | 70 s | green |
  | fault at stage 10 | 110 s | green, no magenta |
  | fault at stage 14 | 150 s | green + magenta |
  | no `/vram` (failed check, stage 15) | 160 s | |
  | DRAM-only MMU-on entry at offset 0 | 175 s | |

| Build (task 11) | Bytes | SHA-256 |
|---|---|---|
| `build/m5boot-beacon3.bin` | 81,920 | `b40d853284ef39ec13f2721c99efc983c36ae09ba2579820b090ec1303ac4ed8` |
| `build/m5boot-probe3.bin` (MMU-first) | 196,608 | `844af44821fbb8761d266f02e2e5e3672c15130f454c0684a9e63a626eef3981` |
| `build/m5boot-gz2.bin` (MMU-first, slim inputs) | 5,455,872 | `600ce059b9dc78d3dd21a90f035694147dc16c53adc3402e76ebe83ce1ac7ff3` |

## NATIVE 2026-11-04 (owner-verified): beacon3 painted the screen GREEN
- **Build:** `build/m5boot-beacon3.bin` `b40d853284ef39ec13f2721c99efc983c36ae09ba2579820b090ec1303ac4ed8` (commit 837dcc7), installed via the proven finish-install flow, on mBoot-18000.161.10 (macOS 26.6.2).
- **Observed:** the whole screen turned bright green, which is beacon3 **stage 5**.
- **What this establishes:**
  - **Our code runs natively.** iBoot hands off to the raw object.
  - **Stages 0–4 completed natively:** the MMU-off-first sequence, the VBAR install and the WDT disable write ran without a fatal fault. Stage 5 runs only after them, with no boot_args access before it.
  - **The OBSERVED vram region `0x105_D311_0000` (3024×1964, stride 12096, x2r10g10b10) is the visible scanout FB.** `0x000ffc00` displays as green, which confirms the 2:10:10:10 layout with green in bits 10–19. The display stays lit after the hand-off; no panel/backlight action is needed.
- **Still open / not yet established:**
  - **Entry offset (H-ENTRY):** the branch header covers both 0 and 0x800, so this result doesn't say which one iBoot used.
  - **Was the MMU on at entry?** Not known yet: beacon3 doesn't report it, though probe3/gz3 print SCTLR at entry.
  - **How far after stage 5 it got:** pending the owner's **reset time**, read against the beacon3 table in Task 11 (175 s = everything done; 10 + 10·s = stopped at stage s).
- **gz3 stays ready:** `build/m5boot-gz3.bin` `f689052a9a1a84c851d0bd43a66ce23bb0f08ce0fc1c7ddb9645066e8cfc5385` (5,455,872 bytes, commit 0da8d10). It has the same entry/stage-5 green path and puts its console and simple-framebuffer on the boot_args FB if strictly sane, else on this now-confirmed vram region.

## Task 12: gz3 = gz2 + beacon3 robustness
`build/m5boot-gz3.bin` = the gz code built with `-DGZ3 -DBEACON` + the slim payload (DTB `23dabefb…`, slim Image.gz `b3c6bfa6…`, initramfs-slim `1e0f73cc…`, all verified by `check-inputs.sh`).

**What gz3 adds:**
- **Entry** as in task 11: branch header at offset 0 → MMU/D-cache/I-cache off first → VBAR → WDT disable. The stage word is set in start.S for stages 0–4.
- **Stage 5:** the owner's bright GREEN over the OBSERVED vram region (`0x105_D311_0000`, 3024×1964, stride 12096, bounded by a static assert), then `dc civac`, before boot_args is touched.
- **Stage-coded beacon up to the jump:** an exception (VBAR handler) **or a failed check (`panic`)** at stage s arms WD1 for **10 + 10·s s**. The WDT is armed before any console/FB work in the handler.
- **Countdown:** the 10 s on-screen countdown is kept.
- **Before the jump:** WD1_CTRL ← 0 again (`apple_wdt_stop`), then the cache clean and the jump.
- **Console + FDT `simple-framebuffer`:** the boot_args FB if strictly sane (fixed offsets: 3024×1964, stride 12096, 30/32 bpp, inside the observed DRAM); otherwise the OBSERVED vram region, where stage 5 painted green. Format: x2r10g10b10 for 30 bpp and the observed region.
- **Bug fixed (affects the probe/gz builds since task 05):** the FDT framebuffer width came from the console, which is 112 px narrower (the bar strip). It now uses the full FB geometry. That is why the probe3 hash changed.

| T (s) | stage | gz3 step started (fault or failed check here) |
|---|---|---|
| 10–30 | 0–2 | entry, SCTLR read, MMU-off (before our VBAR: a fault here goes to iBoot) |
| 40 | 3 | VBAR set |
| 50 | 4 | WDT disable |
| 60 | 5 | GREEN paint of the observed vram + clean |
| 70 | 6 | step 1: boot_args parse, console, on-screen dumps |
| 80 | 7 | step 2: ADT pointer, watchdog node verify |
| 90 | 8 | step 3: CNTFRQ, memSize, topOfKernelData, memory maps |
| 100 | 9 | step 4: payload header/trailer, Image header |
| 110 | 10 | step 5: RAM window, inflate-scratch placement |
| 120 | 11 | inflate Image.gz |
| 130 | 12 | kernel/FDT/initrd placement |
| 140 | 13 | step 6: copy Image/initrd, FDT patch |
| 150 | 14 | 10 s countdown |
| 160 | 15 | WDT disable again, cache clean, jump |
| no reset | — | reached Linux (or died before stage 3) |

Linux itself doesn't feed the WDT, but we disable it before the jump, so a working boot doesn't reset.

**VM (QEMU virt, NOT hardware)**, `tests/qemu-gz3.sh` with the main Image.gz + initramfs (the slim kernel has no QEMU console):
- VM hooks at stage 7 / 11 / 13 → BITE = 24e6 × 80 / 120 / 140, CTRL = 4.
- A panic (no memory-map, stage 8) → 90 s.
- In every case the green region is filled to its last pixel and the next byte is untouched.
- **Full run:**
  - console on the strict boot_args FB;
  - `watchdog disabled again before the jump`;
  - Linux `simple-framebuffer b8000000.framebuffer: [drm] fb0: simpledrmdrmfb`;
  - `Run /init`, the shell, dropbear `Not backgrounding`.
- Host tests all pass.

| Build (task 12) | Bytes | SHA-256 |
|---|---|---|
| **`build/m5boot-gz3.bin`** | 5,455,872 | `f689052a9a1a84c851d0bd43a66ce23bb0f08ce0fc1c7ddb9645066e8cfc5385` |
| `build/m5boot-probe3.bin` (FDT FB width fix) | 196,608 | `f59cd0f834696fb45e016fe9a8cfb3c7a595fd5abc6b5bad479a9935c7ac94de` |
| `build/m5boot-beacon3.bin` (unchanged) | 81,920 | `b40d853284ef39ec13f2721c99efc983c36ae09ba2579820b090ec1303ac4ed8` |

## NATIVE 2026-11-04: gz3 console on the real Mac (`spec/native-gz3-screen.jpg`, gz3 `f689052a`) → task 13
**Native facts (photo, owner):**
- Entry x0 = `0x100065bc000`, **EL2**.
- **SCTLR_EL2 = `0x30000180`: MMU, D-cache and I-cache OFF at entry.** So H1 holds natively, and the task 11 "MMU on" hypothesis is false here. The MMU-off-first code is a no-op natively and stays as defence.
- boot_args **Revision 3**, Version 2. Revision 3 is newer than the XNU headers we cite (1/2). It's flagged "UNKNOWN revision" but is harmless: every field we use decodes plausibly.
- BOOT_LINE_LENGTH = **1024** (H3 holds): memSizeActual@0x478 = `0x600000000` (24 GiB). cmdline "".
- virtBase `0x15ae4000`, physBase `0x10003ae4000`, memSize `0x5c701c000`, topOfKernelData `0x100065cc000`, flags 0.
- Video `0x105d3110000` 3024×1964, stride 12096, depth `0x1001e` (30 bpp + scale bit 16). It equals ADT `/vram` reg `0x105d3110000 +0x57ac000`, and the strict fixed-offset FB check passes.
- deviceTreeP `0x17884000` is a VA (H4) → PA `0x10005884000`, 737,280 bytes, parsed.
- WDT verified at `0x28836c000`; WD1_CTRL before 4, after 0.
- memory-map: 9 ranges (63 skipped); carveout-memory-map: 164 ranges (165 skipped).
- **Halt:** step 4, "no room to inflate Image.gz".

**Root cause (reproduced on the host).** The carveout-memory-map contains **region-id-24 = `0x10003ae4000 + 0x5c701c000` = exactly [physBase, physBase+memSize)**, the kernel's own RAM window.
- The value is identical in our ADT dump, `~/m5-omarchy/reports/04-j714s-full.txt`, which was read for this node only, per the task.
- We treated it as a reservation, so every hole in the window overlapped it. It would also have marked all RAM `no-map` in the FDT.
- The skipped entries are not the cause. In the dump, the carveout node has 89 16-byte `{base,size}` props and 91 one-byte props (flags, correctly skipped). The memory-map's values are scrubbed in the dump; its 63 skipped are non-16-byte props.
- The 9 memory-map ranges are now printed on screen in every build, so the next native photo shows them.

**Fix (`src/place.c` `drop_ram_window`, used for both memory-map and carveouts):** drop only ranges **exactly equal** to [physBase, physBase+memSize), and print each drop. Every other carveout stays reserved (and `no-map` in the FDT).

**Regression:**
- `tests/test_native13.c` with the native values + `tests/native-j714s-carveouts.txt` (the 89 dumped carveouts):
  - without the drop, placement fails (reproduces the halt);
  - with it, the main.c sequence (inflate scratch 7,907,336, kernel + 64 MiB headroom, FDT 2 MiB, initrd 2,143,952) places at `0x10024000000 / 0x10024800000 / 0x10029200000 / 0x10029400000`, inside the window, overlapping no carveout, the FB, boot_args or the ADT.
- **VM:** `tests/mkfake.py --ram-carveout` adds the same kind of carveout. The gz3-code full run prints `dropped 1 carveout(s) equal to the kernel RAM window` and boots to the shell + dropbear. The stage-hook and panic beacon runs still pass.
- **Bonus:** the screen already shows the inflate address (step 5 "inflating … at"), kernel/FDT/initrd (step 5), and the SUMMARY line before the countdown.

| Build (task 13) | Bytes | SHA-256 |
|---|---|---|
| **`build/m5boot-gz4.bin`** (gz3 code + fix, slim inputs) | 5,455,872 | `09a4a35004b0c9450357dda5ec1eba7203251216482893b691c667c4f4c461dc` |

## NATIVE 2026-11-04: gz4 (`09a4a350`) ran steps 1–6 and the jump (`spec/native-gz4-screen.jpg`)
The placement fix works natively:
- `dropped 1 carveout(s) equal to the kernel RAM window 10003ae4000 +5c701c000`;
- inflate 3,105,641 → 7,907,336 at `0x10072400000`;
- kernel `0x10072c00000`, FDT `0x10073400000`, initrd `0x10073600000`, console `0x105d3110000`;
- all 9 memory-map ranges shown (`0x10004…`–`0x10005…`);
- the countdown, then the jump.

Linux then died before fbcon and the Mac rebooted (PM). This boot's x0 was `0x10005258000` and the ADT VA `0x20520000`; both vary between boots.

## Task 14 (prepared; build waits for the task-23 kernel in spec/inputs.md): gz5
- **Cmdline built by m5boot (`src/cmdline.c`, gz5 only via `-DEARLYCON_M5FB`):** `<DEFAULT_BOOTARGS>[ <iBoot cmdline>] earlycon=m5fb,0x<fb>,<w>,<h>,<stride>,<bpp> panic=0 initcall_debug ignore_loglevel`.
  - The FB values are the ones m5boot itself uses (natively `0x105d3110000,3024,1964,12096,30`). With no FB, the earlycon argument is omitted.
  - **HYPOTHESIS:** the task-23 driver parses base = 0x-hex, the rest decimal. Check against that driver.
  - If the line doesn't fit (2 KiB), m5boot halts with a beacon rather than truncating.
- **Bug found and fixed in `src/fmt.c` (all builds):**
  - `PUT(c)` evaluated its argument only when the buffer had room, and `%s` passes `*s++`, so **any truncated `%s` looped forever**.
  - gz5's longer bootargs line would have passed `pr()`'s 256-byte buffer and **hung natively before the countdown**.
  - Now: evaluated exactly once. `pr()`'s buffer is 512 bytes, and there is a regression test in `tests/test_cmdline.c`.
  - Already-built objects (gz4 `09a4a350`) predate the fix. Their longest line is the ~150-char bootargs, so they didn't hit it.
- **Tests:**
  - **Host:** `tests/test_cmdline.c` covers the native values, the iBoot cmdline join, no FB, the overflow → -1, and the fmt truncation regression.
  - **VM:** gz5 code + main Image.gz. Linux `Kernel command line: … earlycon=m5fb,0xb8000000,640,480,2560,32 panic=0 initcall_debug ignore_loglevel`; it boots to the shell + dropbear. The main kernel ignores the unknown earlycon.
- **To build** once inputs.md lists the kernel: `make build/m5boot-gz5.bin IMAGEGZ5=<Image.gz> INITRD5=<initramfs>`. check-inputs verifies the hashes.
- **Built (inputs.md "Slim kernel v2", task 23):**
  - inputs: slim Image.gz `f992dada…` (inflates to exactly Image `df9887b5…`), initramfs-slim `1e0f73cc…`, DTB `23dabefb…`, all verified by check-inputs;
  - the task-23 driver's format `earlycon=m5fb,<base hex>,<w>,<h>,<stride bytes>,<bpp 30|32>` matches ours;
  - the required tokens are all present: `keep_bootcon panic=0 initcall_debug ignore_loglevel loglevel=8 maxcpus=1 console=tty0 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0`, from DEFAULT_BOOTARGS + the appended part;
  - natively the line will read `maxcpus=1 keep_bootcon console=tty0 loglevel=8 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0 earlycon=m5fb,0x105d3110000,3024,1964,12096,30 panic=0 initcall_debug ignore_loglevel`.
  - **VM limit:** the slim kernel has no PL011, so QEMU can't show its console. The gz5 code path was VM-tested with the main kernel (above).

| Build (task 14) | Bytes | SHA-256 |
|---|---|---|
| **`build/m5boot-gz5.bin`** | 5,718,016 | `3bceded200788f7dae2e68179505f9021ea63e4acc6cbf04c13f5b71e5b05aa7` |

## NATIVE 2026-11-04 (PM): gz5 (`3bceded2`) booted Linux
- **m5boot's job is done natively:** the jump works, Linux runs, and the `earlycon=m5fb` console draws on the FB m5boot passed.
- The kernel then panicked on an **SError after the MTP DART init**. That is a kernel/DT matter: task 24 is producing a new DTB.

## Task 15: gz6 = gz5 + the task-24 DTB
- Same code as gz5 (`build/m5boot-gz5-code.bin`), slim kernel v2, initramfs-slim; only the DTB changes.
- Target: `make build/m5boot-gz6.bin DTB6=<task-24 dtb> IMAGEGZ5=… INITRD5=…`. check-inputs verifies all three against spec/inputs.md.
- **Inputs:** task-24 DTB `ce5bd290…` (66,098 B; MTP + DART, DockChannel/HID, USB 1–2 + DARTs disabled), slim v2 Image.gz `f992dada…`, initramfs-slim `1e0f73cc…`. All verified.
- check-inputs now also ends a token at `,` or `.`, because the task-24 entry is prose. Exact path + hash on one line are still required, and an unlisted file is still refused.
- **Host:** the FDT patch test (`test_core`) passes on the new DTB. The cmdline is unchanged from gz5.

| Build (task 15) | Bytes | SHA-256 |
|---|---|---|
| **`build/m5boot-gz6.bin`** | 5,718,016 | `21d62e37ba3dccfd247dba027e6224153bc13cb136812371466126503a07435d` |

## Task 16: gz7, dump + disable every watchdog
**NATIVE (PM):** gz6 Linux ran ~45 s and then reset while idle (no panic, panic=0, apple_wdt off). Suspect: another armed watchdog. Our ADT dump's wdt node: wdt-version 3, reg = main block `0x2_8836_C000 +0x4000` + 4 single registers `0x2_8833_5260`, `…_0008`, `…_002C`, `…_0020`.

**`src/wdt.c` (gz7 only, `-DWDT_ALL`):**
- Register layout from Linux `apple_wdt.c` (`ref/linux/apple_wdt.c`, GPL-2.0-only OR MIT):
  - "three separate watchdogs. WD0 resets the machine to recovery mode … WD1 and WD2 trigger a normal machine reset";
  - WDx CUR/BITE/CTRL at 0x00/0x04/0x0c, 0x10/0x14/0x1c, 0x20/0x24/0x2c; WD0 BARK 0x08;
  - RESET_EN = bit 2.
- **Step 2:** if the ADT block equals `0x2_8836_C000` and its size ≥ 0x30:
  1. Read and print WD0/WD1/WD2 CUR/BITE/CTRL + WD0 BARK.
  2. Read the 4 extra registers **read-only**, and only if the runtime ADT reg[1..4] translates to exactly our dump's addresses (otherwise "not read").
  3. **Write 0 to each WDi_CTRL that reads RESET_EN set**, then read back and print.
- **Before the jump:** the same re-read, re-print and re-disable (after the existing WD1 write).
- **Writes:** only CTRL registers inside the main block. The 4 extra registers are never written.
- **Owner-authorised exception (task 16):** this goes beyond the CLAUDE.md WD1-only rule.

**Tests:**
- **Host:** `tests/test_wdt.c` on a fake 0x4000 block. Armed WD0/WD2 are disabled; WD1 already off and an IRQ_STATUS-only CTRL are not written; nothing else changes; it is idempotent.
- **VM** (`tests/qemu-gz7.sh`): fake WD0/WD2 armed, 4 extra registers preloaded.
  - Serial shows `WD0 … ctrl 4 | WD1 … ctrl 0 | WD2 … ctrl 4`, then `extra regs [bef00100]=11 … =44`, then `disabled 2 armed`.
  - Pre-jump: `disabled 0 armed`.
  - The monitor reads CTRLs 0/0/0 and the extra registers unchanged (0x11/0x22/0x33/0x44). Linux reaches `Run /init` and dropbear.

**Inputs: same bytes as gz6, taken from gz6 itself.** Between gz6 and gz7 another session overwrote both files at their listed paths with unlisted builds: the slim DTB at 22:32 (now `fef5c3c4…`, 66,086 B) and the slim Image.gz (now `d8fb2c2b…`). check-inputs correctly refused both. I extracted the gz6 payload blobs and verified each against spec/inputs.md:
- DTB `ce5bd290…` (task 24);
- Image.gz `f992dada…` (slim v2);
- initramfs `1e0f73cc…`.

gz7 is built from those exact bytes. **For the PM:** the files at the listed paths no longer match inputs.md.

| Build (task 16) | Bytes | SHA-256 |
|---|---|---|
| **`build/m5boot-gz7.bin`** | 5,734,400 | `786359c9ca01769f917eacc6f50afb7e278f7b23dac43cd8bcd8d6fc42d81bdc` |

## Task 17: gz8 = gz7 + slim v3 + fb DTB + ESP log + ATC0 PS reads
- **Inputs** (spec/inputs.md "Slim v3", all verified by check-inputs):
  - DTB gz6+fb `47e993cf…` (66,187 B);
  - Image.gz `6e63c511…`, which inflates to exactly Image `e88a6fae…`;
  - initramfs-slim `15f6a6f3…`.
- **Watchdogs:** the gz7 logic is unchanged (`-DWDT_ALL`).
- **Cmdline** (`build_cmdline`; new optional x-offset field and extra token):
  - natively: `maxcpus=1 keep_bootcon console=tty0 loglevel=8 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0 earlycon=m5fb,0x105d3110000,3024,1964,12096,30,1512 panic=0 initcall_debug ignore_loglevel m5.esplog=1`;
  - x offset = width/2, which is 1512 natively, as in inputs.md;
  - `m5.esplog=1` is PM-approved (task 17): the initramfs writes only `m5log/boot-N.txt` on our ESP.
- **FB node:** the slim-v3 DTB has an enabled `/chosen/framebuffer@0` simple-framebuffer. `fdt_patch` reuses that node (it never adds a second one), writes m5boot's reg/width/height/stride/format, and sets `status = "okay"`. `test_core` passes on this DTB.
- **PMGR PS reads (read-only, before the jump, `-DPMGR_PS`):**
  - `atc0_usb` = pmgr@`0x2_8830_0000` + 0x150, `atc0_usb_aon` = same block + 0x148, `atc0_common` = pmgr@`0x2_8060_0000` + 0x208. Blocks and offsets come from the slim-v3 Linux DT's power-controller nodes.
  - Each one is read **only if** that block base is one of the runtime ADT `/arm-io/pmgr` reg entries (which index is printed); otherwise "not read".
  - The raw 32-bit value is printed. **No PMGR writes.**
- **Tests:**
  - **Host:** `test_cmdline` covers the x offset + `m5.esplog=1` and the no-FB case; all other host tests pass.
  - **VM** (gz8 code + main Image.gz; the fake ADT has `/arm-io/pmgr` reg = 0xbef10000, 0xbef20000 with preloaded values):
    - `PMGR PS atc0_usb: ADT pmgr reg[0] bef10000 + 150 = 10ff`, `atc0_common: reg[1] bef20000 + 208 = 30ff`, `atc0_usb_aon: … 148 = 20ff`;
    - WDT step 2 / pre-jump as in gz7;
    - Linux `Kernel command line: … earlycon=m5fb,0xb8000000,640,480,2560,32,320 … m5.esplog=1`, simpledrm on the FB, then `Run /init` and dropbear.

| Build (task 17) | Bytes | SHA-256 |
|---|---|---|
| **`build/m5boot-gz8.bin`** | 5,767,168 | `c6d66c70525019111cae82ed5f7726900cf231d3d39c172ee3bc1fe32e053ba1` |

## Task 18: camera-free native logging (initramfs-slim-v4log) + gz9
**NATIVE (PM):** gz8 Linux ran, but `/m5log` on the ESP was never created.

**Root cause (found in the listed initramfs-slim `15f6a6f3…`, reproduced in QEMU):** `/sbin/sfdisk` is **dynamically linked against libfdisk.so.1, libsmartcols.so.1 and libncursesw.so.6, none of which are in the initramfs's /lib**, so it never runs.
- The v3 `m5-esplog` used `sfdisk --part-type` for every partition and got empty types, so it found "no ESP" and exited; the reason went only to kmsg.
- QEMU with the v3 initramfs: `part type=` empty for all 6 partitions.
- The v3 script also gave up after 60 s without `nvme0n1`, again with only one kmsg line.
- `install-rootfs.sh` also calls sfdisk → **broken the same way (for the PM)**.

**Checked, not the cause:**
- vfat, cp437, iso8859-1 and nvme_apple are built into the slim v3 Image (`strings`).
- FAT32 with 4096-byte logical sectors mounts and writes fine in the VM.
- The DTB's `nvme@45dcc0000` (ANS2, SART, mailbox) is enabled.
- Whether **nvme_apple actually probes natively** is not known: the logger now reports it either way.

**Fix: `initramfs-v4log/bin/m5-esplog` (v4), packed by `tools/mkinitramfs-v4log.sh`.**
- **Packing:** the listed initramfs-slim bytes unchanged, plus an appended newc cpio overlay that replaces only that script. Linux unpacks concatenated archives in order. `/init` is unchanged and starts it at line 19 when `m5.esplog=1`.
- **Partition detection:** no sfdisk. The GPT is read with busybox `dd`/`od`: the header at LBA 1 in the device's logical block size, then each entry's type GUID; the entry's first LBA is cross-checked against the kernel's sysfs start.
- **Waiting:** it waits for `nvme0n1` indefinitely. Every 5 s it logs the nvme class, `/proc/partitions`, and the last nvme/ans2/sart/rtkit/mailbox dmesg lines to kmsg (so they show on the m5fb earlycon).
- **Channel 2 (raw, first):** the start of the partition with GPT type Linux filesystem and **size == 120,000,000,000**, used only if its first 4 MiB are all zero or start with `M5LOG`; otherwise it refuses (logged).
  - Every 5 s it writes the full 4 MiB (`dd … oflag=direct conv=fsync`): `M5LOG v1 boot=<n> uptime=<s>`, then the logger's own log, uptime, `/proc/interrupts`, and dmesg, zero-padded.
  - The magic is re-checked before each write, and `boot=` counts up across boots.
- **Channel 1 (ESP):** `m5log/boot-<n>.txt` on the single EFI-type 200–1100 MB vfat, every 30 s. Mount, write, rename, sync and umount errors are logged.
- **Every step** goes to kmsg → earlycon.

**VM (QEMU, NOT hardware)**, `tests/qemu-v4log.sh`:
- **Setup:**
  - Disk: `tests/mkdisk-j714s.sh`, a sparse 1 TB image with **4096-byte logical blocks**; s4 EFI FAT32 499,998,720 B and s5 Linux 120,000,000,000 B are exact, and the Apple partitions s1–s3/s6 are approximate.
  - The main kernel has no NVMe-PCI driver, so the disk is virtio-blk with 4096-byte blocks and the VM-only `m5.logdisk=vda`.
- **Results:**
  - **fresh:** all 6 types read; `raw … first 4 MiB all zero: ok`; s5 begins `M5LOG v1 boot=1 uptime=…` followed by `--- logger`, `--- uptime`, `--- interrupts`, `--- dmesg`; ESP has `/m5log/boot-1.txt`.
  - **second boot:** `existing M5LOG (boot=1)` → `boot=2`, and `boot-2.txt`.
  - **junk in s5:** `REFUSE raw … neither zero nor M5LOG`; s5 untouched; the ESP is still written.
  - **No disk:** `waiting for /dev/nvme0n1 …` every 5 s, forever.
  - **Writes stay in place:** the sparse image's allocated extents after the runs lie only in the GPT, s4 and s5.

**Artifacts:**
- `spec/inputs.md` § Slim v4-log: `~/m5boot/build/initramfs-slim-v4log.cpio.gz`, 2,148,208 B, `a8aa2cb5e09c096e6dac8923e55612cebd122b97c2715638f9be4ca7af07af7a`.
- The kernel is unchanged.
- That spec file also holds the PM's uncommitted edits, so I left it uncommitted.

**gz9 = gz8 + this initramfs.** It uses gz8's code (`build/m5boot-gz8-code.bin`). The slim-v3 Image.gz at its listed path was overwritten by the slim-v4 build (inputs.md note), so the DTB and Image.gz were **extracted from `build/m5boot-gz8.bin`** and verified against inputs.md (DTB `47e993cf…`, Image.gz `6e63c511…`). The cmdline is unchanged from gz8 (includes `m5.esplog=1`).

| Build (task 18) | Bytes | SHA-256 |
|---|---|---|
| **`build/m5boot-gz9.bin`** | 5,767,168 | `48338f2f76e729bf46070e8fc7cddc51d18a5530e7cfe2a18b13ae448daa4c99` |

**macOS read commands (read-only).** First confirm the identifiers: `diskutil list disk0` should show s4 = EFI ~500 MB and s5 = Linux Filesystem 120.0 GB. Then:
```
# channel 2 (raw): the first 4 MiB of disk0s5, NULs stripped
sudo dd if=/dev/rdisk0s5 bs=4194304 count=1 2>/dev/null | tr -d '\000' > ~/Desktop/m5log-raw.txt
head -1 ~/Desktop/m5log-raw.txt          # M5LOG v1 boot=<n> uptime=<s>
# channel 1 (ESP), mounted read-only
sudo mkdir -p /tmp/m5esp && sudo mount -r -t msdos /dev/disk0s4 /tmp/m5esp
ls -l /tmp/m5esp/m5log && cat /tmp/m5esp/m5log/boot-*.txt > ~/Desktop/m5log-esp.txt
sudo umount /tmp/m5esp
```
(Terminal may need Full Disk Access to read `/dev/rdisk0s5`.)

### Addendum 18 / 18b
- **Owner:** the logger said it wrote to /mnt, yet the raw ESP (first 64 MiB) has no `m5log`/`boot-` trace, so the vfat mount failed silently and the writes went into the initramfs `/mnt`.
- **Fix:** `esp_write` now requires both `mount` rc 0 **and** `^$ESP /mnt/esp vfat ` in `/proc/mounts` before writing.
  - **On failure** it logs `esp mount … FAILED (rc=…): <mount's error>; /proc/mounts: …`, plus whether vfat is in `/proc/filesystems` and the last fat/vfat/msdos dmesg lines. These go to kmsg/earlycon **and** into the raw s5 log (the logger's own log is part of every raw write). Then it skips the write.
  - **On success** it logs `esp write ok: m5log/boot-<n>.txt <bytes> bytes on <dev> (vfat, verified mounted)`.
  - VM case `badesp` (FAT boot sector wiped): `esp mount /dev/vda4 FAILED (rc=255): … Invalid argument`, which also appears in the raw s5 log; no ESP files. fresh/second/junk still pass.
- **New initramfs:** `initramfs-slim-v4log` `676b5300…` (2,148,496 B). inputs.md was updated, and the first build `a8aa2cb5…` is marked superseded.
- **gz9 rebuilt on the task-26 "A+C" set (18b):**
  - slim-v4 kernel Image.gz `21c706f5…`, which inflates to exactly Image `73b4f4fa…`;
  - **DTB C** `8c1ce5c6…`;
  - cmdline base + **`m5_pmgr_ro`** + `m5.esplog=1` (ESP logging approved);
  - all inputs verified by check-inputs.
  - The x offset, watchdog logic and PMGR PS reads are as in gz8. `test_core` passes on DTB C.
  - VM (gz9 code + main kernel): `Kernel command line: … earlycon=m5fb,…,320 panic=0 initcall_debug ignore_loglevel m5_pmgr_ro m5.esplog=1`, then `Run /init`, then `m5log: v4 start`.
- **Natively** the cmdline will read: `maxcpus=1 keep_bootcon console=tty0 loglevel=8 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0 earlycon=m5fb,0x105d3110000,3024,1964,12096,30,1512 panic=0 initcall_debug ignore_loglevel m5_pmgr_ro m5.esplog=1`.

| Build | Bytes | SHA-256 |
|---|---|---|
| `build/m5boot-gz9.bin` (first, gz8 inputs + a8aa2cb5 initramfs): **SUPERSEDED** | 5,767,168 | `48338f2f76e729bf46070e8fc7cddc51d18a5530e7cfe2a18b13ae448daa4c99` |
| **`build/m5boot-gz9.bin` (A+C + verified-mount logger)** | 5,767,168 | `0c2fe5f40d8a03e0e405be93d1a7bbed7d3371afe630684640967d506cac169a` |

## Task 19: gz10 = gz9 + secondary-WDT clear
**Provenance (third-party, kept as the PM asked):** a Discord DM from betizzel's agent, 2026-11-04 23:23, describing a loader's *behaviour* from their boot logs (not code). Summary: their loader clears a second watchdog word at 0x288330008 on J714s, logs it as disabled on every boot, and they consider writing 0 there safe.
- **Clean-room note:** this is second-hand information derived from m1n1's behaviour. It is used on the PM/owner's explicit instruction. **We read no m1n1 code, log or repository.**
- The address agrees with our own ADT dump: wdt reg[2] = `0x2_8833_0008`, and wdt-version 3 [OURS].

**Code (`-DSECWDT`, gz10 only):**
- **Step 2** (the first point where the ADT is parsed): read wdt reg[1..4] (each only if the runtime ADT translates it to exactly our dump's address), wait ~1 s on CNTPCT, read and print them again.
- **The write:** if the ADT `wdt-version` is 2 or 3 **and** reg[2] translates to exactly `0x2_8833_0008`, write a 32-bit 0, read it back, and print.
- **Before the jump:** the same write again.
- **Never written:** reg[1], reg[3] and reg[4].
- **Cmdline:** `m5.wdt2=0x<before>,0x<after>` (the step-2 values), or `m5.wdt2=none` if the conditions weren't met. The v4 logger records it through dmesg's "Kernel command line".
- **Owner-authorised exception** to the WDT-only write rule: exactly this one register.

**Tests:**
- **Host:** all suites pass. The SECWDT path is only in main.c (MMIO), so it is covered by the VM tests.
- **VM** (`tests/qemu-gz10.sh`; fake extra registers 0x11/0x22/0x33/0x44, VM secondary register = reg[2] = 0xbef00104):
  - **wdt-version 3:** both reads print 11/22/33/44; `SECWDT step 2: before 22, wrote 0, after 0`, then the pre-jump repeat; memory afterwards `11 00 33 44`, so the other three are untouched; Linux cmdline `… m5_pmgr_ro m5.esplog=1 m5.wdt2=0x22,0x0`.
  - **No wdt-version:** `conditions not met: NOT written`; memory `11 22 33 44`; `m5.wdt2=none`.

**gz10 inputs = gz9's exactly:** slim-v4 Image.gz `21c706f5…`, DTB C `8c1ce5c6…`, initramfs-slim-v4log `676b5300…`, all verified by check-inputs. The cmdline is gz9's + `m5.wdt2=…`.

| Build (task 19) | Bytes | SHA-256 |
|---|---|---|
| **`build/m5boot-gz10.bin`** | 5,767,168 | `b23bf78bed1ec702a4d7e5ef3ec34e5441174e82d6065e2c672889d7890c1f0d` |

## Task 20: gz11 = gz10 + desktop-v1 kernel + m5.root=s5
- **Kernel:** desktop-v1 Image.gz `0a4835b8…`, which inflates to exactly Image `9d5d3e83…`. **It contains the `m5_pmgr_ro` patch:** the same `m5_pmgr_ro` parameter string and `m5 pmgr: %s %s off=0x%x val=0x%x` write logging as slim-v4 (`strings`).
- **DTB:** C `8c1ce5c6…`; `test_core` passes on it.
- **Initramfs:** task 20 named r27 `1e0882c6…`, but those bytes were replaced in place during the task. Per the PM it's now **r28a `a8d3caf1…`** (= r27 + `/lib/firmware/apple/tpmtfw-j714s.bin` only; PM-verified and approved).
  - It is used from the PM's frozen copy `~/m5boot/build/initramfs-slim-r28a.cpio.gz`, verified by hash against inputs.md. That path isn't listed, so it was checked by hash rather than by check-inputs path. The other two inputs passed check-inputs.
  - The firmware file is unused under DTB C, since MTP is off there.
- **Cmdline:** gz10's + `m5.root=s5`: `… earlycon=m5fb,0x105d3110000,3024,1964,12096,30,1512 panic=0 initcall_debug ignore_loglevel m5_pmgr_ro m5.esplog=1 m5.root=s5 m5.wdt2=0x<b>,0x<a>`. All gz10 loader logic is kept.
- **Rootfs check (read-only):** `rootfs-omarchy.ext4` has 4096-byte blocks and label `omarchy`, as m5-root requires, so it can mount on the 4096-byte-sector NVMe.
- **VM (`tests/qemu-gz11.sh`):**
  - **Setup:** gz11 code + main kernel (the desktop kernel has no virtio) + the r28a initramfs. The disk is J714s-like, with 4096-byte virtio blocks; s5 holds a small stub ext4 (label omarchy, 4 KiB blocks, busybox `/sbin/init`). `m5.logdisk=vda` goes in via the fake iBoot cmdline.
  - **Results:** SECWDT cleared, then cmdline `… m5.root=s5 m5.wdt2=0x22,0x0`, then `m5root: root /dev/vda5 (label omarchy) mounted on /newroot`, then the logger (raw channel OFF, ESP write verified), then `switch_root`, then `M5ROOTFS-STUB: switch_root reached /sbin/init on /dev/vda5`.
  - The first attempt failed only because the test stub used 1 KiB ext4 blocks (`EXT4-fs: bad block size 1024`). Fixed with `-b 4096`.

| Build (task 20) | Bytes | SHA-256 |
|---|---|---|
| **`build/m5boot-gz11.bin`** | 6,455,296 | `8b7ec61b902780dbe571892e2d46f08b47fe82012bd75a3054ab41e8d4cb1806` |

## Task 21: gz12 = gz11 code/cmdline + Input v1 (internal keyboard/trackpad, DTB I1)
- **Code and cmdline:** exactly gz11's (`build/m5boot-gz11-code.bin`): `… m5_pmgr_ro m5.esplog=1 m5.root=s5 m5.wdt2=…`. **No `m5_pmgr_allow`** (that's U1, later).
- **Inputs (spec/inputs.md § Input v1), frozen under `~/m5boot/build/frozen-input-v1/` because the main worker rebuilds in place;** each copy's hash matches inputs.md:
  - Image.gz `0c79ce5b…`, which inflates to exactly Image `002bc8d5…`. It still contains `m5_pmgr_ro`.
  - **DTB I1** `c4388a37…` (= C + MTP/DART/DockChannel/HID on, USB off).
  - initramfs r28a `a8d3caf1…`, which includes the trackpad firmware `tpmtfw-j714s.bin`; under I1 the MTP driver can now load it.
- **Tests:**
  - **FDT:** `test_core` passes on DTB I1.
  - **VM:** `tests/qemu-gz11.sh` with the frozen r28a and the main kernel, since the m5boot code is identical: SECWDT cleared, `… m5.root=s5 m5.wdt2=0x22,0x0`, `m5root: … mounted`, ESP write verified, `M5ROOTFS-STUB: switch_root reached /sbin/init on /dev/vda5`.
  - **Not testable in QEMU:** I1's MTP/HID nodes and the input-v1 kernel. Natively, look for the MTP/DockChannel/HID probe in the ESP log.

| Build (task 21) | Bytes | SHA-256 |
|---|---|---|
| **`build/m5boot-gz12.bin`** | 6,455,296 | `10345b69044fe8b37a07349a1a721c51229b70bbaee29e2f0039f07f0d6da600` |

## Task 22: gz13 = gz12 + DTB U1 + m5_pmgr_allow (USB power test)
- **Code:** gz12's with one cmdline change (`-DCMDLINE_EXTRA` adds `m5_pmgr_allow=atc0_common,atc0_usb_aon,atc0_usb,atc0_phymxwrap`, the four ATC0 labels from inputs.md § Input v1 "U1 cmdline").
  - Natively: `… panic=0 initcall_debug ignore_loglevel m5_pmgr_ro m5.esplog=1 m5.root=s5 m5_pmgr_allow=atc0_common,atc0_usb_aon,atc0_usb,atc0_phymxwrap m5.wdt2=0x<b>,0x<a>`.
  - **Nothing new is armed or written by m5boot**: the loader logic is identical to gz12's.
- **Inputs (frozen in `build/frozen-input-v1/`, hashes = inputs.md):** **DTB U1** `52da5db5…` (= I1 + dwc3_0 + DARTs on the ATC0 chain; experimental), input-v1 Image.gz `0c79ce5b…`, initramfs r28a `a8d3caf1…`.
- **Tests:**
  - **FDT:** `test_core` passes on U1.
  - **VM:** `CODE=build/m5boot-vmgz13-code.bin tests/qemu-gz11.sh`. Linux gets `… m5.root=s5 m5_pmgr_allow=atc0_common,atc0_usb_aon,atc0_usb,atc0_phymxwrap m5.wdt2=0x22,0x0`; SECWDT, then the m5root mount, then the ESP log, then switch_root to the stub `/sbin/init`.
  - Host tests all pass. QEMU can't exercise U1's USB nodes or the PMGR allow-list.

| Build (task 22) | Bytes | SHA-256 |
|---|---|---|
| **`build/m5boot-gz13.bin`** | 6,455,296 | `d77ffc4db38bd59aa07a44a074c34de1362880759748c14d2a058758a5b57fe9` |

## Open items
- On-hardware runs settle H1–H9, H-ID and H-STALE.
- If spec H9 (size) fails: fall back to a loader kernel (`initramfs-loader.cpio.gz`).
