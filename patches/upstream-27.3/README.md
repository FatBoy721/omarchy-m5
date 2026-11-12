# aurora-silicon base on the 27.3 beta 1 stub (J714s)

Work toward running aurora-silicon's `integration/aurora` kernel and the Aura bootloader on
TripleU613's J714s while it stays on the macOS 27.3 beta 1 stub (26C5035r,
mBoot-20457.60.65.0.1), with the GPU and the internal display handed over as our own kernel and
m1n1 do today.

Status (2026-11-11): **builds, not yet boot-tested.** Do not ship. The first staging attempt
broke the dev Linux root (a `lib/` modules tarball extracted at `/` replaced the `/lib -> usr/lib`
symlink); `~/m5/tools/rescue-lib-bm.bin` repairs it on the next boot and `stage-up273.sh` stages
under `/usr` instead.

| Patch | Applies to | What |
| --- | --- | --- |
| `0001-linux-integration-aurora-pr1173-pr1174-merged.patch` | aurora-silicon/linux `integration/aurora` at f1b79c4beaef (first written on 990e00b72b56) | #1174 as first published (290b7de9f129 + 0cdf8957541b: the full 27.3 method table and swap layout; Jeff Queisser, Rolando Trevino). The updated #1174 (61a1fd086170 + bf43e8cefdf3) has a deliberately partial 27.3 table (the 20 traced methods) and refuses to start a 27.3 DCP ("no ID known for 21 methods"), so it is not used until its table is complete and #1173 (GPU 27.2/27.3 InitData layouts and firmware identity; Rolando Trevino) merged. #1173 conflicted with upstream's `Graph` refactor: each build gets its own `Graph` (`M5_GRAPH_26B123`, `M5_GRAPH_26C5035`, chosen by the firmware's identified layouts), `hw_offset()` and the board graph are kept, and the J813 (common26) keeps its board graph. Compiles with rustc 1.98.0 on ush. |
| `0002-aura-t6050-27.3-gpu-dcp-handoff.patch` | aurora-silicon Aura 1.0.0b11 (main dbf088e151; #173 M5 Pro boot path, #180 DART; first written on 1669cad0) | Aura knows 27.2 and 27.3 beta 1; its T6050 GPU handoff admits the 27.0, 27.2 and 27.3 beta 1 GPU builds (digests and boot-filled ranges from #1173); its T6050 DCP handoff accepts 27.3 beta 1, takes the DCP image the ADT names and publishes `apple,firmware-compat <27 3 0>` (what #1174 keys its 27.3 table by). Only the firmware gate, image check and compat key are changed; our m1n1's notch rows and display-default handling (m1n1-installer 0006/0007) are not ported, so the full 3024x1964 panel is unverified. |
| `0003-aura-notch-default-and-m5-max-27.3-gpu.patch` | after 0002 | The notch rows by default on M5 (T6050/T6051): without a config line Aura keeps iBoot's full framebuffer and sets `/chosen/asahi,show-notch = "1"`; `chosen.asahi,show-notch=0` opts out. And joshuaswarren's M5 Max 27.3 GPU digest (aurora-silicon/aura #172, the upstream equivalent for the Max of 0002's G17S entries) as one more entry in 0002's build table, so there is a single digest check. |
| `0004-linux-t6050-ane-ave-27.3-firmware.patch` | after 0001 | The T6050 Neural Engine and video encoder on the macOS 27.3 firmware, beside 27.0. Each driver gets a table of admitted builds, and the segment layout the loader hands off selects the build. ANE (`ane_fw_platform`): 27.0 TEXT 0xc0000 and DATA 0x2ac000 at DVA 0x100000c0000; 27.3 TEXT 0xec000 and DATA 0x280000 at 0x100000ec000, each with its own TEXT sha256 pin (27.3: `11557586...66dc6066`). AVE (`ave_t6050`): 27.0 TEXT 0x154000 with CRC 87279429; 27.3 (26C5035r) TEXT 0x158000 with CRC c25b4ddb; DATA is 0x134000 in both. The 27.3 encoder has no qualified command layout, so it probes without one and encoding is refused. `apple-ave.ave_t6050_try_26a428=1` drives it with the 27.0 layout for testing by hand. The H17 ANE backend also sizes its IPC from the firmware's boot request instead of a fixed 64 KiB/0xc441: 27.3 asks for 0x10441 bytes, as the H16 backend already handles. `ane_t6021.boot_stages=N` (default 5) holds the bind's bring-up after N stages, so the rest can be stepped from `firmware_stage`. The recipe ships it as `t6050-ane-ave-27.3.patch` (pkgrel 3). |

Kernel: `0001` is on `integration/aurora` f1b79c4beaef (after #1595 ANE, #1600 DCP HDR, #1577 AVD, #1597 AVE), cross-built on ush, which the image's kernel recipe (`installer/recipes/linux-aurora-upstream`) builds. Kernel branch: `build/linux-up` branch `up-273c` (merges 0929f4f5c93b, 8a0eb8647062, fix
e0516e36058b). Aura branch: `~/m5/work/up/aura` `up-273-image-b11` (0002 + 0003 on main dbf088e1), packaged by `installer/recipes/m1n1-aurora-upstream`.

Still to check on the Mac: GPU firmware up, DCP modeset 3024x1964@120 with the notch rows,
Wi-Fi (`CONFIG_APPLE_CENTAURI_T6050=m`), trackpad, NVMe.

## Boot test on TripleU613's J714s (27.3 beta 1 stub, 2026-11-11)

Aura (0002, test watchdog) chainloaded from the stage-1 m1n1 proxy, kernel `7.3.0-j714s-up+` (0001):

- GPU: `GPU firmware build: 26C5035r for T6050 G17S` (the 27.3 firmware); Vulkan `Apple M5 Pro (G17S B1)`, Borealis.
- Internal display: DCP handed over, `eDP-1` 3024x1890 at 120 Hz (`set_digital_out_mode ... 120`); notch rows not shown yet (m1n1 0007's default is not in Aura yet). External DCPs and `DP-1`..`DP-4` registered.
- Wi-Fi (N1) up, trackpad (`Touch MT ready`), NVMe, USB (a device enumerates, Type-C ports 0/1), SEP firmware reserved by Aura, USB4 router (acio) present, AOP sensors.
- Notch rows: with `chosen.asahi,show-notch=1` in Aura's config the panel runs 3024x1964 at 120 Hz.
- Sound: with `CONFIG_SND_SOC_APPLE_T8152_AOP_AUDIO=m` (off in our config) the `AppleJ714` card (speakers, headphone jack) and `AppleJ714HPAI` (microphones) come up; the speakers stay locked until speakerguardd (shipped in the image) takes them, not tried on the dev Linux.

## Packaged kernel boot test (2026-11-12, RAM, Aura 1.0.0b11)

linux-aurora 7.3.0.aurora17.up273-2 (f1b79c4b + this 0001) from RAM via Aura b11 with the test watchdog: GPU 26C5035r, DCP `eDP-1` 3024x1964 at 120 Hz on apple-drm (the notch rows), Hyprland running, Wi-Fi up. The up273-1 build with the updated #1174 had no DCP (simpledrm only). Not working on 27.3 yet: the ANE (the kernel pins the 27.0 TEXT digest and the preloaded TEXT reads as zeros) and the AVE encoder ("unexpected firmware segment sizes").

## ANE and AVE on 27.3 (0004, 2026-11-12)

iBoot 20457.60.65 (27.3 beta 1) preloads both firmwares, and Aura #169/#171 hand them over intact. On the dev Linux, the reserved ANE TEXT/DATA and AVE TEXT/DATA read back through `/dev/mem` (mmap) as real firmware: RTKit 3514.60.8, AppleAVE2FW. Aura's `aurora,ave-text-crc32`/`aurora,ave-data-crc32` (c25b4ddb/f4e9dda8) match. The all-zero "preloaded TEXT sha256" in the up273-2 log is not the memory. `ane_fw_handoff_present()` hashes TEXT only after the layout check passes, so on the 27.3 layout it printed its zero-initialised buffer. Apple moved 0x2c000 bytes from DATA into TEXT; the span still ends at 0x36c000, so the heap tail, pool and IPC DVAs are unchanged. The AVE TEXT grew by 0x4000, so its build is new.

Upstream (aurora-silicon/linux, aura, 2026-11-12) has no 27.3 ANE/AVE work; #1595/#1597 and aura #169/#171 are 27.0 only.

RAM boot test of up273-3 (f1b79c4b + 0001 + 0004, `7.3.0-17.up273-3-ARCH`, built on ush with rustc 1.98.0 and clang 23.1.3, config identical to up273-2's) through Aura b11 (`loader-up273b-b11-bm.bin`), 2026-11-12 02:29. Aura was chainloaded at 02:30:03, but the Mac was not back on Wi-Fi within 5 minutes. No new m1n1 proxy appeared either, so the 170 s test watchdog did not reset it before Linux took the watchdog over. No kernel log was captured. Not retried. The likely suspect is the first real start of the 27.3 ANE firmware: with 0004 the hand-off verifies and the H17 backend powers the engine and boots it. Under up273-2 it was left off. The AVE 27.3 build only probes (no command layout), and that path only reads memory. The next try should isolate the cause: `modprobe.blacklist=ane` or `apple-ave` on the command line, or start the ANE from its `firmware_stage` file after boot. The up273-2 Image/dtb from `m5local/up273b` are kept at `/root/up273b-backup-up273-2` on p5.

Finding the hang (2026-11-12). The 02:30 boot was reset by the test watchdog at 02:36:13, and the catcher brought the daily kernel back. With `module_blacklist=ane_t6021,ane` (`loader-up273b-noane-bm.bin`), up273-3 boots: AVE `firmware build 26C5035 (TEXT 0x158000 CRC c25b4ddb, DATA 0x134000)`, probe only, `/dev/video0` apple-ave, DCP 3024x1964@120, Hyprland, Wi-Fi. `loader-up273b-anestep-bm.bin` has `modprobe.blacklist=ane_t6021,ane` instead, which leaves `modprobe` by hand possible. With it, `/root/anestep.sh` on p5 loads `ane_t6021 boot_stages=0` and steps probe, map, boot, startup and program from `firmware_stage`, syncing `/var/log/anestep.log` after every step. Probe and map passed. Boot reached READY and then returned -EPROTO (no hang in this run): scratch1 (the IPC size minus one) read 0x10440 where the backend required 0xc440. Every other request cell matched (8 channels, heap 0xf00000, mode 0). With the IPC sized from the request (the whole 0x14000 window up to the heap, 0x10441 in the init block), all five stages pass: `H17 ANE: READY; IPC 0x10441 bytes requested`, startup, `H17 accel node ready (ABI 3...)`, `/dev/accel/accel0`. No inference workload was run: the dev Linux has no ANE program.

Full RAM boot with the fix (`loader-up273b-b11-bm.bin`, no blacklist, 2026-11-12 02:47). The ANE comes up at bind on its own: `H17 ANE: loader hand-off verified (27.3 build, TEXT sha256 115575864d4c8d02d48d83077170e7e16079aaf70dadd608c71910ac66dc6066)`, `READY; IPC 0x10441 bytes requested`, `up at boot, accel node ready`, `/dev/accel/accel0`. AVE: `firmware build 26C5035 ... probe only`, `/dev/video0`. GPU `27.3 (26C5035r), G17S`; DCP `eDP-1` 3024x1964 at 120 Hz; Hyprland; Wi-Fi associated. No SError/Oops. Still open: an ANE inference run (no workload on the dev Linux) and qualifying the AVE 27.3 command layout (`apple-ave.ave_t6050_try_26a428=1` plus an encode). The p5 modules of `7.3.0-17.up273-3-ARCH` carry this fixed `ane_t6021.ko`; the first build's module is kept at `/root/ane_t6021-up273-3-orig.ko`.
