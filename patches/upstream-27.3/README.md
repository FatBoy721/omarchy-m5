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
| `0005-linux-t6050-isp-j714s-camera-27.3.patch` | after 0004 | The front camera's image quality on T6050, from edimoldovan's J714c camera (omacom/linux-aurora #422), on top of aurora-silicon's own T6050 ISP driver (#1252/#1253, Erik Bourget) and J714s camera DT (#1306), which `integration/aurora` already has. Three of Eduard Moldovan's driver commits, unchanged apart from the hardware table: IMX958 setfile `isp_2226_02XX.dat` instead of 2224_01 (38993598aa9a), the noise-reduction radial gains computed from the setfile's lens-shading table (162531436bd8), and the lens-shading target 84% plus the face-detection scene metering (cb9cbb2b470f). His camera light (5a3e9d8a5f0b, 04606609e94c): the driver drives the light pin to its on level before every stream, refuses to stream unless it reads back, and feeds the eic ISP watchdog only while the light is on. On the J714s the pin is in the eic's own GPIO block (`cil` at 0x2dc000234, config 0x474002, active high). And his J714c presets on the J714s: 1920x1080 and 2560x1440 in firmware configuration 6, 1280x720 in configuration 7, centre crops (from e8233e1bbe91/8916070002f4). |
| `0006-aura-t6050-isp-27.3-j714s-camera.patch` | Aura, after 0002 + 0003 | The camera hand-off on 27.3. Aura's T6050 camera hand-off (`dt_set_t6050_isp`) admitted only macOS 27.0. Jens Axboe's board table from aura #188 (9ece8137fa, K116s on 27.2, ported by Thomas Glanzmann), plus a J714s row for 27.3 beta 1: its ADT isp0 keeps sensor type 0x74 and the same two segments (TEXT 0xc1c000 at phys 0x100010cc000, DATA 0x13d0000 at 0x100026a4000). A board may have one row per firmware. |

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

## Front camera on 27.3 (0005, 0006, 2026-11-12)

The J714s camera is an IMX958, the same sensor as edimoldovan's J714c. Most of what his PRs carry is already in our base. All 27 commits of omacom/linux-aurora #421 (aurora-silicon's ISP driver) are in `integration/aurora` f1b79c4b: 22 by patch-id, and the other 5 under the same subjects, which he adjusted for conflicts. aurora-silicon has its own T6050 support (#1252/#1253/#1254), and #1306 enables it on the J714s. #1306 was tested on a J714s on 27.0: 90/90 frames at 1920x1080, 30 fps. On 27.3 the node stayed `disabled`, because Aura's camera hand-off refused any firmware other than 27.0. His static reserved-memory DT for the J714c is not used: the firmware's physical addresses differ per board (J714c TEXT 0x10001224000, J714s 0x100010cc000), and Aura publishes them from the ADT.

RAM tests on TripleU613's J714s (Aura b11 + 0002/0003/0006 with the test watchdog, `loader-up273b-isp-bm.bin`; `loader-up273b-isp-noisp-bm.bin` also blacklists `apple_isp`):

- **Test 1:** up273-3 kernel unchanged, `modprobe.blacklist=apple_isp`.
  - Aura: `isp@580000000` `okay`, `apple,platform-id` 0x74, text/data reserved at the ADT addresses, 32 MiB main memory.
  - `modprobe apple-isp`: `/dev/video2` "FaceTime HD Camera" (1920x1080 NV12).
  - 30 real frames: auto exposure ramps the luma mean from 16 to 88, no two consecutive frames are identical, 29.9-30.0 fps.
  - Sensor tuning: `isp_2224_01XX.dat` (the driver asks for exactly this file, so the sensor is 0x958). The image has heavy grain and a colour cast.
- **Test 2:** kernel `7.3.0-17.up273cam-1-ARCH` (f1b79c4b + 0001 + 0004 + 0005's driver commits, built on ush in `~/m5-build/up273-cam`).
  - `apple-isp` binds at boot.
  - 60 frames at 30.3 fps with `isp_2226_02XX.dat`.
  - Flat-wall noise (mean neighbour difference in the luma) 2.0, against 8.8 with 2224_01.
- **Test 3:** the same kernel plus 0005's J714s presets (dtb only).
  - `--list-formats-ext` offers 1920x1080, 1280x720 and 2560x1440.
  - Each streams 60 NV12 frames at 30.1-30.6 fps.
  - Frames show the full, centred field of view.

In each test the GPU (27.3, G17S), DCP `eDP-1` 3024x1964, Hyprland and Wi-Fi were up while streaming. The ANE (`/dev/accel/accel0`) was checked in test 3 only, and the kernel log had no SError or Oops in tests 2 and 3. Test 1 ended in a kernel crash after the captures. It came from a raw `/dev/mem` read of the gpio0 register at 0x29c000234 (see test 4), not from the camera. One test 3 boot had no Wi-Fi: PCIe port 0, the N1 Wi-Fi chip, was not adopted from the loader, and m5.deadman reset the Mac after 300 s. The repeat boot was fine. The same failure also happened once under the original b11 loader: the up273-3 boot of 02:30 EST that this README put down to the ANE had no port 0 either. In the dev root's journal, 2 of the last 25 boots lack it.

Setfiles: Apple firmware, not in this repo. They are extracted with installer #208's `omarchy_isp.extract()`, unmodified, from macOS 27.3 (26C5035r) `/usr/sbin/appleh16camerad` on the Mac's own System volume. On the dev root (p5) they are in `/usr/lib/firmware/apple`: `isp_1925_03XX.dat`, `isp_2224_01XX.dat` and `isp_2226_02XX.dat` (0x7000 each for the IMX958 files). The local 26.6.2 IPSW has AEA-encrypted system images. The camera streams without a setfile (`streaming without sensor tuning`), but badly.

- **Test 4:** kernel `7.3.0-17.up273cam-2-ARCH`, all of 0005, including edimoldovan's camera light.
  - aurora-silicon's driver only fed the eic ISP watchdog. edimoldovan found that on the J714c the light stays off unless the driver drives it.
  - The light pin is ADT eic `cil-gpio-offset` 141, config 0x474002. The offset is in the eic's own GPIO block (eic `mmio-gpio` 0x2dc000000, as edimoldovan has it), not the AP's gpio0 (0x29c000000).
  - Any read of 0x29c000234 brings the Mac down: a `/dev/mem` read during test 1, and the first try of this test, whose driver read it at probe. Neither left a trace in the synced log, and the watchdog and catcher recovered both.
  - With `cil` at 0x2dc000234, the driver binds at boot. Before every stream the pin reads back at its on level (the driver refuses to stream otherwise).
  - 1920x1080 and 2560x1440 stream at 30.2-30.6 fps. GPU, eDP 3024x1964, Wi-Fi and the ANE are up, with no SError or Oops.
  - Nobody looked at the light itself. The read-back is the evidence.
  - With `camera_light` set for every T6050, as in #422, a T6050 board whose DT has no `cil` (J716c, K116s in this tree) no longer probes its camera. This doesn't matter for the J714s-only image.

Open:
- Lid sleep with the camera was not tried. The 2226_02 setfile, the radial gains, the 84% lens-shading target and the scene metering apply to every T6050 (as in #422). They are verified on the J714c and J714s only.

Dev Mac state: p4 `m5local/up273b` now holds up273cam-2 (Image.gz and the dtb with `cil`), not up273-3. up273-3's files are in `/root/up273b-backup-up273-3` on p5. Modules for `7.3.0-17.up273cam-1-ARCH` and `-2-ARCH` are in p5's `/usr/lib/modules`. The setfiles are in p5's `/usr/lib/firmware/apple`. A patched apfs-fuse (read-only, keybag errors ignored), used to read macOS, is in `/root/build`.

What the image needs:
- `linux-aurora-upstream`: add `0005` after `t6050-ane-ave-27.3.patch` and bump pkgrel. `CONFIG_VIDEO_APPLE_ISP=m` is already set.
- `m1n1-aurora-upstream`: apply `0006` after 0002 + 0003. Regenerate `aura-up273-image.patch` and its sha256, and bump pkgrel.
- Setfiles on an installed system: omacom/omarchy-mac-installer #208 (cffff8b5ed2c, edimoldovan) adds the IMX958 2224_01 and 2226_02 entries to the installer's `omarchy_isp.py`. It applies on c07e54c, the base of our installer patches. The installer's firmware collection then extracts them from macOS's `appleh16camerad` into the vendor firmware it installs. The driver requests `apple/isp_2226_02XX.dat` (2224_01 on T6040/T8142) from the firmware search path. Check on the first installed image that the file lands where the kernel finds it.
