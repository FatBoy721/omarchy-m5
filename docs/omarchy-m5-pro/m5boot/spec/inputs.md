# m5boot inputs: artifacts the implementer may use (built 2026-11-04 on ush)

All are built from GPL Linux / verified Alpine and ALARM packages / our own scripts. **None of them involve m1n1 or aura.**
Re-check each SHA-256 before use. Paths are absolute.

| Artifact | Path | Size | SHA-256 |
|---|---|---|---|
| Kernel, uncompressed (the payload m5boot jumps to) | `~/m5-omarchy/build/linux/arch/arm64/boot/Image` | 46,483,968 | `9c377f51e6e9b1266f117f969d7ef2ed14bf1b8f40542e72e9e17c4f01e4b5e6` |
| Kernel, gzip (reference only) | `~/m5-omarchy/build/linux/arch/arm64/boot/Image.gz` | 16,331,363 | `63835275b84f4bd7e0e156ab399cde792bb3f30f7d0db4a32cafe1b7c80a1a37` |
| **Safe** device tree for J714s (input to the libfdt patching) | `~/m5-omarchy/build/linux/arch/arm64/boot/dts/apple/t6050-j714s.dtb` | 65,890 | `23dabefb43d7bb4a51eeca1cb4072f05475cbe148b869ffc7b40af02916d1d6d` |
| First-boot initramfs (busybox, dropbear, CDC-EEM gadget, sfdisk/mkfs.ext4, `install-rootfs.sh`, probe module) | `~/m5-omarchy/build/initramfs.cpio.gz` | 2,369,383 | `37237b5c8693a433b6655136ac52230dc15822786d189fb7895676f6934de48b` |
| Loader initramfs (the above + kexec-tools, `m5-loader`) | `~/m5-omarchy/build/initramfs-loader.cpio.gz` | 2,921,311 | `4a8f0183bc7de8cb9561ea1cf46d18c9741c55a316b87f49fab462a24e55d2ca` |
| Rootfs for the 120 GB partition (ALARM + this kernel's 1389 modules) | `~/m5-omarchy/build/rootfs-alarm.tar.zst` | 586,736,066 | `32f5b7ee35d1e5dcf9a6144e85ef1576c0d730609c6eb5b232c464155ac6e6f3` |
| work's SSH public key (already inside both initramfs + rootfs) | `~/m5boot/spec/work.pub` (copy of `~/m5-omarchy/build/work.pub`) | 94 | `d500c096b835045bade042db1dd4b41a11cccec2b7a159e238155a6eef264938` |
| Read-only probe module | `~/m5-omarchy/tools/t6050-probe/t6050_probe.ko` | — | `e44f9f5828005c9910ed2497270693a2cefbf2a352e7483756097a321a967483` |

**Kernel facts for the loader:**
- Image header (`booting.rst` layout): `text_offset = 0x0`, `image_size = 0x2d50000` (47,513,600 B, includes BSS), `flags = 0xc`, magic `ARMd`.
  - `flags` bits 1–2 = 2, i.e. **16 KiB pages**.
  - Bit 3 = 1: "2MB aligned base may be anywhere in physical memory".
- Kernel release `7.2.2-g236788cd2602-dirty`, clang/lld 23.1.3.

**Suggested bootargs for the first native boot:**
`maxcpus=1 keep_bootcon console=tty0 loglevel=8 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0`
- `earlycon=efifb` is **dropped**. Its screen_info came only from betizzel's fixed-address fb-marker code, which is now disabled (task 14). The console is `console=tty0` via simpledrm on m5boot's `simple-framebuffer` node.
- For the loader initramfs, append `m5.loader=1 m5.root=/dev/nvme0n1pN`.

**How the safe kernel was built:** `~/m5-omarchy/tools/build-kernel.sh` (sha256 `6bf0fe2a55d54059211d8953faeeb3f2276bc2b8075b2948916a5af7bfe1f8a4`).
- Sources: AsahiLinux/linux `asahi-wip-7.2` @ `236788cd` + betizzel/omarchy-m5 @ `15cd70c1` (9 kernel patches, DTs, config fragments).
- Our safety fragment `~/m5-omarchy/tools/kernel/m5-safe.config` (sha256 `d24c012c12687298cd8520801874b2aa7d1894dce3ab6802fbef286b313655a3`), merged last.
- DT edits applied to the copy in the tree.
- `.config` sha256 `2874307d4a8b453baffc42e46b283fee6e0c76343a79826ac9f4dae86c7e5e41`.

**Owner hardware-safety limits, as implemented:**
- **No audio:** `SOUND`, `SND`, `APPLE_SIO` off (so no MCA, TAS2764/2770, CS42L84 or macaudio drivers). The DT has no audio nodes; the only "codec" strings are the PMGR power-domain labels `scodec` and `scodec_streaming`, which have no driver.
- **No SMC:** `MFD_MACSMC` and every `*_MACSMC*` client off; `t6050-smc.dtsi` and the SMC-backed `hwmon-*.dtsi` removed from the DT.
- **No cpufreq:** `ARM_APPLE_SOC_CPUFREQ` off; `t6050-cpufreq.dtsi` removed.
- **No GPU/DCP:** `DRM_APPLE` off and `DRM_ASAHI` absent; no GPU/DCP/PMP nodes in the DT.
- **Kept per PM decision:** PMGR power domains (273 `apple,t8103-pmgr-pwrstate` nodes) with `pd_ignore_unused`. These can write PMGR state at probe.
- Also kept: NVMe (ANS + SART), DockChannel MTP keyboard/trackpad, DWC3 + configfs CDC-EEM gadget, SPMI, simpledrm.
- `maxcpus=1`. The probe module is read-only.

**Licensing:** `Image`/`Image.gz` include betizzel's 8 kernel patches, which have no license grant. **Local use only, do not redistribute** (`~/m5-omarchy/reports/06-licenses.md`). The DT is `GPL-2.0+ OR MIT`.

## Changes in task 14 (2026-11-04)
- **Kernel:** `# CONFIG_OMARCHY_FB_MARKERS is not set` (in `m5-safe.config`). betizzel's patch `0001-t6050-early-fb-markers.patch` had painted red `0x3FF00000` bands at the fixed PA `0x10bd3110000` (stride `0x2f40`), whatever the bootloader reported, and set up `earlycon=efifb` there. All hooks are now empty stubs. The new `Image` has 0 occurrences of that address and no `omarchy_fb*` symbols. The DTB is unchanged.
- **initramfs `/init`:** `cttyhack` doesn't exist in Alpine busybox-static 1.37.0, so the old `exec setsid cttyhack sh` made PID 1 exit (kernel panic). `/init` now never exits: it respawns a console shell forever on the active console device (last entry of `/sys/class/tty/console/active`; tty0 on the Mac). Tested in VM: stays up, respawns after `exit`, dropbear listening on :22.
- **Superseded hashes** (do not use):
  - `Image` `d226395f9c3c4a5112b015267fa56ceed1b7139f20c9b4ac423a69ed843f3065`
  - `Image.gz` `ac7986002af3c1adcbadfd1ca26cbeefd941d340c07854c572fed22406f6740e`
  - `initramfs.cpio.gz` `20eef15588801b43dc75f4dbd570ccebf9d84632ffc753019767318c55db002f`
  - `initramfs-loader.cpio.gz` `f11e0a88cdd42053e921c41c285154b70d03dcd85357928099e38ec28389efa1`
  - `rootfs-alarm.tar.zst` `3959220029acd8d8b329928400c256a254902268f3b2b19a99b5fcc069bc9d5e`, then `965eaec4062c6f8734837cd6744c94b1b7f10ee7cc6b682a32f4ca6249b3dc04` (still had earlycon=efifb in /boot/cmdline)

## Slim first-boot artifacts (task 17, 2026-11-04). Alternative set; the artifacts above remain current
Use these to keep the boot object small (the target is <= 10-11 MiB total). VM/NATIVE boot of the slim kernel: **untested**.
| Artifact | Path (ush) | Size | sha256 |
|---|---|---|---|
| Image | ~/m5-omarchy/build/linux-slim/arch/arm64/boot/Image | 7,907,336 B | 09c771f177de6b3b84566f6e56fec4257e34dac75f91d0a9b10578a349bfdbb2 |
| Image.gz (gzip -9, Kbuild) | ~/m5-omarchy/build/linux-slim/arch/arm64/boot/Image.gz | 3,105,641 B | b3c6bfa66c46a00e13bb1c3bf530d11f9e6e92b0a4f10af685e11d666d46e13d |
| DTB (same as the main set) | build/linux-slim/arch/arm64/boot/dts/apple/t6050-j714s.dtb | 65890 B | 23dabefb43d7bb4a51eeca1cb4072f05475cbe148b869ffc7b40af02916d1d6d |
| initramfs-slim.cpio.gz | ~/m5-omarchy/build/initramfs-slim.cpio.gz | 2,143,952 B | 1e0f73ccc11cbedcb936cfc2183782f6900c1f927254799123806cc1acee7c49 |
- Config: allnoconfig + ~/m5-omarchy/tools/kernel/m5-slim.config; same source pins and safety limits as above. Everything needed for first boot is built in (no modules needed).
- The initramfs is the base set minus e2fsck/fsck.*/econftool; its t6050_probe.ko is built for the slim kernel (sha256 4f31f323…bfc85). /init and the cmdline are unchanged from the main set.
- Projected m5boot-gz payload: 3.11 MB + 2.14 MB + DTB ≈ 5.3 MB plus the shim.

## 2026-11-04 NATIVE: entry at file offset 0
probe2 (196,608 B, branch at file offset 0 → entry) ran on mBoot-18000.161.10 with no iBoot panic. **iBoot enters a raw fuOS at file offset 0**, even with `kmutil --entry-point 2048`. Every boot object (m5boot, m5boot-gz, slim) must have a valid branch to its entry at offset 0. Source: ~/m5-omarchy/reports/15-fuos-launch.md and 19-firmware-matrix.md, update sections.

## CORRECTION 2026-11-04
The "entry at file offset 0" note above is **RETRACTED**: probe2 was never installed (step2-fast failed the pairing check every cycle; see ~/m5-omarchy/reports/18-fast-cycle.md). The entry offset is **untested**. Keep the m5boot design as specified (entry 0x800); a branch at offset 0 to the entry is harmless and covers both cases.

## Slim kernel v2: framebuffer earlycon (task 23, 2026-11-04). Supersedes the slim Image/Image.gz above
| Artifact | Path (ush) | Size | sha256 |
|---|---|---|---|
| Image | ~/m5-omarchy/build/linux-slim/arch/arm64/boot/Image | 8433672 B | df9887b54ca869a36d090247ec468cc99c74dd57c02337bd6cec6862a0d4010a |
| Image.gz | ~/m5-omarchy/build/linux-slim/arch/arm64/boot/Image.gz | 3378711 B | f992dadab3a41ccbeaa238cd5ca63d3c0f4920353be27d89fdc8112b416e95a1 |
- DTB and initramfs-slim are unchanged (hashes above). Build: ~/m5-omarchy/tools/build-slim.sh.
- New: `earlycon=m5fb,<base>,<width>,<height>,<stride bytes>,<bpp>`, where bpp 30 = x2r10g10b10 (white 0x3fffffff) and bpp 32 = xrgb8888. It draws printk text from parse_early_param() on, starting top-left; the screen wraps instead of scrolling, and the two rows below the cursor are cleared. KALLSYMS is on. APPLE_WATCHDOG is off, so the kernel never touches the WDT. PANIC_TIMEOUT=0.
- **Cmdline m5boot should pass** (fill the FB values from what m5boot uses at runtime; base in hex):
  `earlycon=m5fb,<base>,<width>,<height>,<stride>,30 keep_bootcon panic=0 initcall_debug ignore_loglevel loglevel=8 maxcpus=1 console=tty0 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0`
  e.g. `earlycon=m5fb,0x105d3110000,3024,1964,12096,30 …`
- Expect the first line `Booting Linux on physical CPU …` (replayed buffer), then `earlycon: m5fb0 at MMIO …` and `m5: setup_arch reached, earlycon parsed`. A harmless warning "unsupported earlycon uart clkrate option" also appears.
- **DTB updated (task 24):** ~/m5-omarchy/build/linux-slim/arch/arm64/boot/dts/apple/t6050-j714s.dtb, 66098 B, sha256 ce5bd2907cdd700791949cb99f8e40bb3d583079d7cdd27037254d696b0bf1c6. It disables MTP + its DART, DockChannel/HID, and USB controllers 1–2 + their DARTs; dwc3_0 and its DARTs are bound to ps_atc0_usb. Image/Image.gz are unchanged (slim v2 hashes above). Cmdline unchanged.

## Slim v3 (task 25, 2026-11-04). Supersedes slim v2 Image/Image.gz/DTB and initramfs-slim
| Artifact | Path (ush) | Size | sha256 |
|---|---|---|---|
| Image | ~/m5-omarchy/build/slim-v3/Image | 8499208 B | e88a6faee1b9ea868ba6742d8b8660ca9427d02dc4dd388cb3500e4ba8bacdb0 |
| Image.gz | ~/m5-omarchy/build/slim-v3/Image.gz | 3413887 B | 6e63c5118b5e2812335d2501af8105ecc89ef12b139cd2bd3d252a5a5334b636 |
| **DTB gz6+fb (use this)** | ~/m5-omarchy/build/slim-v3/t6050-j714s-gz6.dtb | 66187 B | 47e993cf08f42febb46533e65bbc72b61b8fcb47fbbcb2db001572d4f86b8102 |
| DTB-A (no USB; optional, no static fb node) | ~/m5-omarchy/build/slim-v3/t6050-j714s-A.dtb | 66086 B | fef5c3c4fccaea33164d471a76dee5929bdbba530eaaf8ecce075c9c0536ade8 |
| DTB-B (dwc3_0 no IOMMU; optional, no static fb node) | ~/m5-omarchy/build/slim-v3/t6050-j714s-B.dtb | 66022 B | dd4dde553147576927f314cd2a7be74ed0cd4e70e0f60139a2c0445bb5b797ca |
| initramfs-slim.cpio.gz | ~/m5-omarchy/build/initramfs-slim.cpio.gz | 2145151 B | 15f6a6f3412c138fe08a32bbaedf045870f982e506c2003daf2ac2769bf6feff |
- Kernel: every PMGR write is logged at KERN_EMERG **before** it happens (`m5 pmgr: <domain> <op> off=0x… val=0x…`). The earlycon drains its stores after each write. New optional earlycon field: **x offset** (draw only in the right part). VFAT + NLS 437/8859-1 are built in.
- DTB gz6+fb: the gz6 overrides plus a **static, enabled `framebuffer0` simple-framebuffer** (0x105d3110000, 3024x1964, stride 12096, x2r10g10b10, no power-domains), so simpledrm + fbcon bind for `console=tty0`. If m5boot fills this node itself, its values win; make sure it doesn't leave `status = "disabled"`.
- initramfs: /init mirrors its messages to /dev/kmsg (`m5init: === m5 initramfs ===`, visible on the earlycon). The new `m5.esplog=1` (opt-in) writes dmesg snapshots (5 s, 20 s, 60 s, then every 60 s) to `m5log/boot-N.txt` on the single EFI-type vfat partition of 200–1100 MB.
- **Cmdline:**
  `earlycon=m5fb,<base>,<w>,<h>,<stride>,30,1512 keep_bootcon panic=0 initcall_debug ignore_loglevel loglevel=8 maxcpus=1 console=tty0 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0`
  Add `m5.esplog=1` only with PM/owner approval: it writes to the ESP.

## Slim v4 (task 26, 2026-11-04): reset-fix variants. One kernel for all; the variants differ only in DTB/cmdline
**Note:** the Image/Image.gz files at build/slim-v3/ were overwritten by this build, so use the build/slim-v4/ paths. The v4 kernel = v3 + the `m5_pmgr_ro` switch (default off; without it, v4 behaves like v3).
| Artifact | Path (ush) | Size | sha256 |
|---|---|---|---|
| Image | ~/m5-omarchy/build/slim-v4/Image | 8499208 B | 73b4f4fa83ce0f2b68e0496adafcb0d7cfe59e42de6d1ad05f8ccb9a552a70a3 |
| Image.gz | ~/m5-omarchy/build/slim-v4/Image.gz | 3414120 B | 21c706f59b18c9b487e0cdbb44e3e6df0b390ea708bc507e0a21401f88ec33b5 |
| DTB gz6+fb (A, B) | ~/m5-omarchy/build/slim-v4/t6050-j714s-gz6.dtb | 66187 B | 47e993cf08f42febb46533e65bbc72b61b8fcb47fbbcb2db001572d4f86b8102 |
| DTB C | ~/m5-omarchy/build/slim-v4/t6050-j714s-C.dtb | 66339 B | 8c1ce5c6ea17e45039b823cb2d72af811bb4369aec95841a43b75fe49cc54f24 |
| initramfs-slim | ~/m5-omarchy/build/initramfs-slim.cpio.gz | (unchanged from v3) | 15f6a6f3412c138fe08a32bbaedf045870f982e506c2003daf2ac2769bf6feff |
Base cmdline: `earlycon=m5fb,<base>,<w>,<h>,<stride>,30,1512 keep_bootcon panic=0 initcall_debug ignore_loglevel loglevel=8 maxcpus=1 console=tty0 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0`
- **A:** DTB gz6+fb, base cmdline + `m5_pmgr_ro`.
- **B:** DTB gz6+fb, base cmdline + `m5_pmgr_ro fw_devlink=off deferred_probe_timeout=0`.
- **C:** DTB C, base cmdline.
- **Recommended first, "A+C":** DTB C, base cmdline + `m5_pmgr_ro` (see report 26).

## Slim v4-log (task 18 in ~/m5boot, 2026-11-04): camera-free native logging
| Artifact | Path (ush) | Size | sha256 |
|---|---|---|---|
| initramfs-slim-v4log (addendum 18: ESP mount verified via /proc/mounts) | ~/m5boot/build/initramfs-slim-v4log.cpio.gz | 2148496 B | 676b5300977cb47e73442c9a132f02755732f2bdb211f850d0a5f3650c246566 |
- Superseded (no path, so check-inputs can't accept it): first v4-log build `a8aa2cb5e09c096e6dac8923e55612cebd122b97c2715638f9be4ca7af07af7a` (no mount verification).
- = the slim-v3 initramfs-slim (`15f6a6f3…`, bytes unchanged) + an appended cpio overlay that replaces only `/bin/m5-esplog` (source: `~/m5boot/initramfs-v4log/bin/m5-esplog`, built by `~/m5boot/tools/mkinitramfs-v4log.sh`). /init is unchanged: it still starts the logger when `m5.esplog=1`.
- Root cause of the empty /m5log: `/sbin/sfdisk` in initramfs-slim is dynamically linked against libfdisk/libsmartcols/libncursesw, which are not in /lib, so it never runs. The v3 logger got no partition types and so found "no ESP". `install-rootfs.sh` also uses sfdisk, so check it. The v4 logger reads the GPT itself (busybox dd/od).
- Kernel: unchanged (the slim v3 Image already has vfat + cp437 + iso8859-1 + nvme_apple built in).

## Rootfs boot v1 (task 27, 2026-11-04): Omarchy on disk0s5 via m5.root=s5
| Artifact | Path (ush) | Size | sha256 |
|---|---|---|---|
| Image (slim + m5-desktop.config: systemd/Hyprland needs) | ~/m5-omarchy/build/desktop-v1/Image | 9656328 B | 9d5d3e83d0981b4f8aad920423ad1b52498eb1646ddbe668cf183f00279285b2 |
| Image.gz | ~/m5-omarchy/build/desktop-v1/Image.gz | 4,040,470 B | 0a4835b871eed14205e4723294c41dee7de86d835c181776724c3f7f02e4db83 |
| DTB (= slim v4 DTB C: USB/pinctrl/serial/wdt off, static fb) | ~/m5-omarchy/build/desktop-v1/t6050-j714s-C.dtb | | 8c1ce5c6ea17e45039b823cb2d72af811bb4369aec95841a43b75fe49cc54f24 |
| initramfs-slim (init: m5.root=s5 + switch_root; m5boot's v4 logger, raw channel off with m5.root=s5) | ~/m5-omarchy/build/initramfs-slim.cpio.gz | | 1e0882c6fa7f8485e42970b0fd5bc8549485aae2a9c10a96a42896cf9cca650a |
| rootfs image (for disk0s5, written from macOS) | ~/m5-omarchy/build/rootfs-omarchy.ext4 | 19,441,188,864 B | 927400aad577ef0e6b5c29efd196e8e0861495ffad35e6a72eac91f475614088 |
| same, zstd | ~/m5-omarchy/build/rootfs-omarchy.ext4.zst | 6,112,458,778 B | c35fd888935309ffdabb6abbf95c0d129b50d3ce054ebe2cf08b1e02cd6cba76 |
Cmdline: `earlycon=m5fb,<base>,<w>,<h>,<stride>,30,1512 keep_bootcon panic=0 loglevel=4 maxcpus=1 console=tty0 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0 m5.root=s5 m5.esplog=1` (add `m5_pmgr_ro` per the slim v4 / gz8 result).

## Input v1 (task 28, 2026-11-04): internal keyboard/trackpad (I1), USB power experiment (U1)
| Artifact | Path (ush) | Size | sha256 |
|---|---|---|---|
| Image.gz (desktop config + PMGR allow-list + 10 ms PS poll) | ~/m5-omarchy/build/input-v1/Image.gz | 4040558 B | 0c79ce5b3f41d32c744be31b566e6380a30364e801fbf01638f945229b9701fe |
| Image | ~/m5-omarchy/build/input-v1/Image | 9656328 B | 002bc8d51a33b5bee115156d102e6d012ae50bea3c512c540d22114ec854130f |
| **DTB I1** (= C + MTP/DART/DockChannel/HID on; USB off) | ~/m5-omarchy/build/input-v1/t6050-j714s-I1.dtb | 66319 B | c4388a3792d250862f7fbadd7b68c41790a31fbb418ace25a261c69feeaab419 |
| DTB U1 (= I1 + dwc3_0 + DARTs on the ATC0 chain; experimental) | ~/m5-omarchy/build/input-v1/t6050-j714s-U1.dtb | 66323 B | 52da5db5111da3f6d2499c80f874d4d3d1edff65a65d9a4c80f7346be231f356 |
| initramfs-slim (+ /lib/firmware/apple/tpmtfw-j714s.bin) | ~/m5-omarchy/build/initramfs-slim.cpio.gz | 2207307 B | a8d3caf1aac2af0c6de81a0763fdd02c2338029ca88ef36bd08886f86d3b536d |
| tpmtfw-j714s.bin (Apple's, from the 26.6.2 IPSW; local use only) | ~/m5-omarchy/build/firmware/apple/tpmtfw-j714s.bin | 79956 B | 03a6d272deae424cd4a8e8ca75161079e4da11ffebc012d8b8088b35f1ad719d |
| rootfs v2 (= v1 + firmware) | ~/m5-omarchy/build/rootfs-omarchy.ext4(.zst) | 19441270784 B | ext4 d14bb0d41622eec450c586f39a2e28d55a61e9339825eee0ef4c78a8386bca86 / zst e322231bcde133c41c18937209f0bb2aa74dfee523c3134fc083e45bbcbd5639 |
- **I1 cmdline:** rootfs-boot-v1 cmdline + `m5_pmgr_ro`. MTP needs no PMGR writes.
- **U1 cmdline:** I1's + `m5_pmgr_allow=atc0_common,atc0_usb_aon,atc0_usb,atc0_phymxwrap`.
- rootfs v2 is only needed for the trackpad firmware after switch_root. The initramfs copy covers the built-in driver's probe, so a disk0s5 written with v1 can stay.
| initramfs-slim r28a (= r27 + /lib/firmware/apple/tpmtfw-j714s.bin only; PM-verified diff 23:43) | ~/m5-omarchy/build/initramfs-slim.cpio.gz | | a8d3caf1aac2af0c6de81a0763fdd02c2338029ca88ef36bd08886f86d3b536d |
