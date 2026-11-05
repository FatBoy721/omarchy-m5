# m5boot spec v0: cited facts for the implementer

The target is J714s (MacBook Pro 14", M5 Pro, Mac17,9, chip-id 0x6050) on macOS 26.6.2 / mBoot-18000.161.10. m5boot is a raw boot object that iBoot starts via `kmutil configure-boot --raw`. It boots our Linux on one core.

**Rules for this spec:**
- It contains **nothing learned from m1n1 or aura**.
- Every fact gives a **source + quote** and is labelled:
  - **[SRC]**: from a cited source;
  - **[OURS]**: from our own scrubbed dumps (`~/m5-omarchy/reports/02-j714s-dump.txt`, `04-j714s-full.txt`);
  - **[HYPOTHESIS]**: unsourced, with the native test that decides it.
- Don't follow links from any doc into an m1n1 repository.

**Sources and terms:**
- **XNU:** `github.com/apple-oss-distributions/xnu` @ `f6217f891ac0`, APSL 2.0, no AI instruction files. Read for interface facts only, and write your own definitions (copying APSL files would make them APSL).
- **AsahiLinux/docs** @ `5acb80f`, no AI files.
- **Linux:** `~/m5-omarchy/src/linux-asahi-wip72` @ `236788cd`, GPL-2.0, no AI files in tree.
- **libfdt:** `scripts/dtc/libfdt/` in that tree, `GPL-2.0-or-later OR BSD-2-Clause`; upstream dtc's AGENTS.md allows AI use.

## 1. Hand-off from iBoot
- **[SRC] Entry, MMU, x0.** AsahiLinux/docs `docs/fw/macho-boot-protocol.md`: "iBoot enters us at the entrypoint … Entry is with the MMU off. `x0` points to the boot_args structure". (That page documents the Mach-O case.)
- **[SRC] XNU behaves consistently with that.** `osfmk/arm64/start.s`, `start_first_cpu`: the comment is "x0 - Boot args". It loads `BA_VIRT_BASE`, `BA_PHYS_BASE`, `BA_MEM_SIZE`, `BA_BOOT_FLAGS` through x0 before creating its page tables, and turns PC-relative addresses into kernel VAs by adding `virtBase − physBase` ("Convert to KVA").
- **[SRC] Raw objects.** AsahiLinux/docs `docs/platform/introduction.md` (fuOS): "Custom kernel images can be flat ARM64 executable images; the entrypoint and (virtual; mostly meaningless) load address are specified when the image is configured." The installer uses `--raw --entry-point 2048 --lowest-virtual-address 0` (AsahiLinux/asahi-installer `src/step2/step2.sh:125`, MIT, no AI files).
  - So: **entry = byte 2048 of the image**, and the load address is unknown, so **all code must be position-independent**.
- **[SRC] RVBAR.** macho-boot-protocol.md: "iBoot sets and locks the RVBAR of the boot CPU to be the top of the page that the entrypoint lives in. This cannot be changed after boot". Treat the page containing the entry as resident.
- **[HYPOTHESIS H1]** A `--raw` object gets the same entry state (MMU off, x0 = boot_args). *Test:* the first instructions save x0, `CurrentEL`, `SCTLR_ELx` and PC, and print them first.
- **[HYPOTHESIS H2]** The exception level at entry is EL2. No public source found. *Test:* print `CurrentEL`, and support both EL2 and EL1 paths.

## 2. boot_args (XNU `pexpert/pexpert/arm64/boot.h` @f6217f89) [SRC]
Field order exactly as declared:

| Field | Type |
|---|---|
| `Revision` | `uint16_t` |
| `Version` | `uint16_t` |
| `virtBase` | `uint64_t` |
| `physBase` | `uint64_t` |
| `memSize` | `uint64_t` |
| `topOfKernelData` | `uint64_t`, "Highest physical address used in kernel data area" |
| `Video` | `struct Boot_Video` = `v_baseAddr`, `v_display`, `v_rowBytes`, `v_width`, `v_height`, `v_depth`, each `unsigned long` (8 bytes on arm64) |
| `machineType` | `uint32_t` |
| `deviceTreeP` | `void *` |
| `deviceTreeLength` | `uint32_t` |
| `CommandLine` | `char[BOOT_LINE_LENGTH]` |
| `bootFlags` | `uint64_t` |
| `memSizeActual` | `uint64_t` |

Normal LP64 C alignment applies.
- Revision constants: `kBootArgsRevision 1`, `kBootArgsRevision2 2` ("added boot_args.bootFlags"); versions 1/2.
- `v_depth`: bits 0–7 = bits-per-pixel (`kBootVideoDepthMask 0xFF`, shift 0), rotate at shift 8, scale at 16, boot-rotate at 24. XNU's `pexpert/arm/pe_init.c` decodes it the same way.
- **[SRC] `BOOT_LINE_LENGTH`:** `608` in XNU tags `xnu-7195.50.7.100.1` and `xnu-8019.41.5`; `1024` in `xnu-10002.1.13` and `xnu-11215.1.10`. Current XNU takes it from a non-public iBoot header (`IBOOT_MAX_ENV_VAR_DATA_SIZE`).
- **[HYPOTHESIS H3]** It's 1024 on macOS 26. *Test:* `memSizeActual` at the 1024 layout must be plausible (≥ `memSize`, a whole number of GiB, about 24 GiB here). Otherwise try 608. Print which one matched.
- **[SRC] Address translation.** macho-boot-protocol.md: "a vaddr is just `paddr + ba.virt_base - ba.phys_base`".
- **[HYPOTHESIS H4]** x0, `topOfKernelData` and `Video.v_baseAddr` are physical; `deviceTreeP` may be a VA in the `virtBase` window (XNU's `pe_init.c` stores it as-is for use after XNU's MMU is on). *Test:* classify each pointer at runtime. Inside `[physBase, physBase+memSize)` means a PA; inside `[virtBase, virtBase+memSize)` means convert it. Print the classification.

## 3. Physical memory layout
- **[SRC]** macho-boot-protocol.md, from its diagram:
  - "`<-- boot_args->phys_base`": the Device Tree (`/chosen/memory-map.DeviceTree`), Trust Cache, the loaded image, SEP firmware and BootArgs follow;
  - "`<-- boot_args->top_of_kdata`";
  - "(Free memory) (incl. iBoot trampoline)";
  - "`<-- boot_args->top_of_kdata + boot_args->mem_size`";
  - "Video memory, SEP carveout, and more".
- **[OURS]** `/chosen` `dram-base` = `0x0000010000000000`, `dram-size` = `0x0000000600000000` (24 GiB), from `04-j714s-full.txt` lines 1306 and 1227.
- **[HYPOTHESIS H5]** Usable RAM for Linux is `[topOfKernelData, physBase+memSize)`, minus every range in `/chosen/memory-map`, minus `/chosen/carveout-memory-map`, minus the framebuffer. *Test:* print the computed window and every excluded range before relocating anything.

## 4. ADT format [SRC: XNU `pexpert/pexpert/device_tree.h`, `pexpert/gen/device_tree.c` @f6217f89]
- **Node** = `{uint32_t nProperties; uint32_t nChildren;}`, then its properties, then its child nodes, recursively.
- **Property** = `{char name[32] /* kPropNameLength */; uint32_t length;}`, then the value.
- **Next property** = `(prop + 36 + length + 3) & ~3`. `device_tree.c` `next_prop_region` uses `os_add3_overflow(prop, prop->length, sizeof(DeviceTreeNodeProperty) + 3, &next)` then `next &= ~(3ULL)`.
- Bounds-check every step against `deviceTreeLength`. XNU asserts that headers and values stay inside the DT region.

**[OURS] What v0 needs from the ADT:**
- **`/chosen/memory-map`:** each property is one reserved range. Our dump lists names only, because macOS zeroes the values after boot: `TrustCache*`, `SPTM-*`, `TXM-*`, `BootKC-*`, `AuxKC*`, `CL4-*`, `DeviceTree-*`, `ExclaveOSIntegrityCatalog`, `MemoryMapReserved-4..15`, … (`04-j714s-full.txt` from line 1567).
  - **[HYPOTHESIS H6]** Each value is `{u64 base, u64 size}` (16 bytes), and the bases are physical. *Test:* print them all; they must fall inside DRAM.
- **`/chosen/carveout-memory-map`:** properties `region-id-N` with 16-byte values. Our dump has 164 `region-id-` entries, e.g. `region-id-68` = `0000e0ff05010000 0000020000000000`.
  - **[HYPOTHESIS H6b]** These are also `{u64 base, u64 size}` and must be reserved. Same test.
- **`/arm-io` `ranges`** (#address-cells 2, #size-cells 2 under a root that also uses 2/2, 24-byte entries). First entry: child `0x0` → PA `0x2_0000_0000`, size `0x3_c000_0000`. Full decode: 19 entries, in `04` at the arm-io node.
- **Watchdog `wdt@8836C000`:** `compatible = "wdt,t8101","wdt,s5l8960x"`. macOS `IODeviceMemory` reg0 = `address 10875224064` = **PA `0x2_8836_C000`**, length 0x4000. That agrees with the arm-io ranges above.

## 5. Watchdog disable [SRC: Linux `drivers/watchdog/apple_wdt.c`, `GPL-2.0-only OR MIT`]
- Registers: `WD1_CUR_TIME 0x10`, `WD1_BITE_TIME 0x14`, `WD1_CTRL 0x1c`; `CTRL_RESET_EN BIT(2)`.
- `apple_wdt_stop()`: `writel_relaxed(0, wdt->regs + APPLE_WDT_WD1_CTRL);`. That is the **only** WDT write m5boot does: one 32-bit 0 to `0x2_8836_C01C`.
- **[HYPOTHESIS H7]** The WDT is armed at entry. *Test:* read and print `WD1_CTRL` before writing.

## 6. Framebuffer
- **[SRC]** boot_args `Video`: `v_baseAddr` ("Base address of video memory"), `v_rowBytes`, `v_width`, `v_height`, and `v_depth` bits-per-pixel (§2).
- **[HYPOTHESIS H8]** The framebuffer is live at entry, `v_baseAddr` is physical, and 32 bpp means 30-bit `x2r10g10b10` (10 bits each, red high). *Test:* draw R, G and B bars plus a white bar and look at the colours. Then hand Linux a `simple-framebuffer` with the matching `format` (`x2r10g10b10` or `a8r8g8b8`) and reserve its memory.

## 7. Linux handoff [SRC: `Documentation/arch/arm64/booting.rst` in our tree]
- **Image header:** `text_offset`, `image_size`, `flags`. "The Image must be placed text_offset bytes from a 2MB aligned base"; "At least image_size bytes from the start of the image must be free". `image_size` includes BSS.
- **Registers:** "x0 = physical address of device tree blob (dtb) in system RAM", x1 = x2 = x3 = 0.
- **PSTATE:** "All forms of interrupts must be masked in PSTATE.DAIF". "either in EL2 (RECOMMENDED …), or in EL1".
- **MMU and caches:** "The MMU must be off." "The address range corresponding to the loaded kernel image must be cleaned to the PoC … cache maintenance by VA rather than set/way". The instruction cache must not hold stale entries for the image.
- **Timers:** "CNTFRQ must be programmed with the timer frequency … If entering the kernel at EL1, CNTHCTL_EL2 must have EL1PCTEN (bit 0) set".
- **FDT:** booting.rst line 53: "The device tree blob (dtb) must be placed on an 8-byte boundary and must not exceed 2 megabytes in size. Since the dtb will be mapped cacheable using blocks of up to 2 megabytes in size, it must not be placed within any 2M region which must be mapped with any specific attributes." (The 512 MB constraint applies only to kernels before v4.2.) It must also not overlap the kernel's `image_size` window, the initrd, or any reserved range.
- **initrd:** `/chosen` `linux,initrd-start` / `linux,initrd-end` (physical).

**DT patching v0 (libfdt) on our input DTB:**
- `/memory` reg = the usable window from H5.
- `/reserved-memory` `no-map` children for every carveout and the framebuffer.
- `/chosen` `bootargs`.
- `/chosen` `linux,initrd-start/end`.
- A `/chosen/framebuffer@…` `simple-framebuffer` node (`reg`, `width`, `height`, `stride`, `format`), plus `stdout-path` if wanted.

## 8. Hardware-safety limits (owner, hard rules)
- m5boot writes **only**: the WDT disable (§5), its own RAM, and the framebuffer.
- No PMGR/clock/power writes, no SMC, no NVMe/storage, no NVRAM, no other MMIO writes. No reads beyond §5's `WD1_CTRL` and the ADT/boot_args in RAM.

## 9. Size
- **[HYPOTHESIS H9]** There's no kmutil/iBoot limit below about 65 MB for `--raw` objects. The planned payload is 46 MB `Image` + 72 KB DTB + 2.4 MB initramfs. No public source was found.
- *Test:* if the first native boot shows **no m5boot output at all**, retry with a minimal object (just the console + a test pattern). Then use the loader-kernel fallback: a small kernel that kexecs the real one.

## 10. Recovery (state verbatim to the owner)
- A hang means: hold power → Startup Options → **Macintosh HD** (macOS's own LocalPolicy, untouched).
- Uninstall: delete the stub (`~/m5-omarchy/reports/08-stub-runbook.md` §4).
- **The DFU path is verified only as far as device detection/identification. A TSS signing check (`idevicerestore -t`) is planned. Revive/restore is untested.**

## 11. Arming the stub
`~/m5-omarchy/src/omarchy-m5/scripts/finish-install.sh` (SPDX MIT) accepts any file as `--m1n1 PATH`:
- Its only checks are that the file exists and a build-config grep (lines 129–135). The grep runs only for the vendor path `vendor/m1n1/build/m1n1.bin`.
- Line 308 copies it to `Resources/boot.bin`.
- `step2.sh` (lines 278–279) runs `kmutil configure-boot -c "$resources/boot.bin" --raw --entry-point 2048 --lowest-virtual-address 0 -v "$system_dir"`.

So `sudo scripts/finish-install.sh --m1n1 /path/m5boot.bin` is the arming command.
