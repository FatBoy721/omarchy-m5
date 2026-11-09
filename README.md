# Omarchy-M5-Pro

Native Linux, then [Omarchy](https://omarchy.org), on a **14-inch MacBook Pro with M5 Pro** (board **J714s**, Mac17,9, SoC **T6050**), bare-metal next to macOS. No VM, no emulator. We are turning the verified integrations collected here into a normal installation path through the existing [Omarchy Mac Installer](https://github.com/omacom/omarchy-mac-installer). We reuse demonstrated public work, qualify each model and firmware combination, and publish matching release components. **No installable M5 release is published by this repository yet.** The bring-up record remains available, with results and corrections labelled.

**Labels:**
- **NATIVE** = seen on this J714s.
- **REPORTED** = someone else's claim.
- **offline** = built and reviewed, not run.

## Installer integration

The [integration and release contract](INTEGRATION.md) defines the first release, support admission and remaining blockers. The existing installer already provides the macOS app, signed catalogs, disk planning and Recovery enrollment; the work here is to integrate a tested hardware stack into that path. A working research boot does not admit a machine to a supported release.

## Current status (2026-11-09)

**All 15 CPUs and native GPU acceleration now work in Omarchy, including a fresh login with persistent isolated Mesa integration.** Linux `7.3.0-j714s-dvfs-thermal-future-g34f2f5bb4d03-dirty` now boots through the refreshed-stub/public m1n1 route. Each CPU passed a pinned, affinity-checked known-answer test on the preceding GPU profile; Aurora reports **16 enabled GPU cores**. Four public rendering/pixel/compute tests passed, and Hyprland itself reports **Apple M5 Pro (G17S B1)** with the isolated Mesa libraries loaded.

**Wi-Fi now connects and carries real traffic on J714s.** The public kernel-owned PCIe train boots with `apple_centauri`, all 15 CPUs online and the graphical session active. The intended saved network joined using an equivalent-PMK credential representation through NetworkManager, preserving its WPA-PSK/RSN/cipher/PMF settings. DHCP/default-route checks, device-bound DNS and two interface-bound HTTPS downloads passed. The saved profile remains persistent with autoconnect enabled. This is a bounded functional pass; reconnect-after-reboot, roaming, suspend and long-transfer qualification remain open. The current trial uses `7.3.0-j714s-n1-kerneltrain-review-g34f2f5bb4d03-dirty`. [N1 integration, source/build identity and current limit](STATUS-2026-11-08.md#native-n1-integration-2026-11-09). The CPU/GPU correctness results below remain attributed to their tested profiles.

The stub now uses **26C5035r / firmware 20457.60.65.0.1**. Its enrolled stage1 loads a small ESP stage2, which loads the kernel, DTB and initrd as separate files. Macintosh HD was verified as the persistent default before this one-shot Linux boot. Earlier statements below about an unrefreshed stub or an unbootable one-core baseline are historical.

| Area | Current evidence and limit |
|---|---|
| CPU / desktop | **15 online CPUs (`0-14`)**; all 15 passed pinned SHA-256/gzip checks on the preceding GPU profile. Manual and capped schedutil pilots passed in all three policies. **16 short single-core stock-OPP tests passed**, ending at nominal **4308 / 4308 / 4608 MHz**; original userspace rates/bounds and boost off were restored. Three-second five-core M0/M1 bursts and a separate P automatic-range pilot passed; fixed-4608 P bursts remain stopped/unqualified. STATUS rates are not measured MHz or sustained thermal qualification. Hardware-rendered Hyprland, active **3024×1890** output and a nonblank desktop verified; the preceding GPU desktop passed 900 seconds with the old guard masked |
| USB access | Standard EEM-only `1d6b:0102`, class `02/0c/07`; native host binding and the scoped direct SSH route verified |
| RAM | **24 GiB physical**; the latest test boot reports Linux `MemTotal` **23,884,400 KiB (22.78 GiB)** after reservations. **4 GiB allocated and locked concurrently** across four 1 GiB memtester workers; each completed all 18 checks, exit 0. The standard early test also passed **17 patterns over 22.945 GiB of eligible memory**, zero bad bytes; reserved memory remains excluded. The earlier 2 GiB/180-second timeout remains partial |
| Storage | **1 TB Apple NVMe**, **120 GB ext4 root**. A new **4 GiB file write/fsync and separate direct CRC32C verification passed**, with stable SHA-256. Short uncapped file burst: fio **1.46 GB/s write / 5.79 GB/s read**, potentially controller-cache influenced; not sustained NAND or whole-device qualification. A separate **16 GiB direct CRC/SHA integrity pass** included **64 seconds of paced writes** |
| GPU | **NATIVE:** G17S firmware **27.3 / 26C5035r** initialized; actual fuse masks identify **16 enabled cores**. Four public tests passed, including 12-scene rendering/compute coverage. A normal UWSM-managed client also passed all 12 scenes on Apple G17S. Vulkan headless rendering, compute/render submissions and **15,597,568 CPU-model correctness checks** passed on Borealis |
| Wi-Fi / Bluetooth | **NATIVE Wi-Fi connection, DHCP/default route, device-bound DNS and two interface-bound HTTPS downloads passed**, with the saved equivalent-PMK workaround. Bluetooth remains unqualified |
| Input / other hardware | Earlier keyboard/trackpad results are historical; current completeness/latency is under owner trial. Read-only SMC monitoring exposes named **TCMb**, a computed SoC hotspot; fan manual control stays disabled. Battery, suspend and other peripherals remain unqualified |

The first split-payload boot did reach all 15 CPUs, but an old rootfs guard remained eligible and initiated the return around 900 seconds. The fix uses **per-boot `/run/systemd/system.control` masks**, which override the actual regular `/etc` unit files. The current profile keeps ordinary journals persistent and leaves the old guard/logger inactive. [Exact evidence, artifact hashes and handoff](STATUS-2026-11-08.md).

Mesa **`043a4c5`** remains isolated from system Mesa. A private `/opt` package and supported user UWSM hooks survived a fresh graphical login without the earlier runtime overlay; system Mesa remains unchanged. These are bounded functional, RAM-sample and file-I/O results, **not Vulkan conformance, full-memory, thermal-protection or long-soak qualification**. Simpledrm provides panel scanout while Aurora performs rendering; this is not the earlier llvmpipe desktop. The stable CPU rollback remains preserved.

### Historical one-core baseline

The earlier m5boot/kexec path ran kernel #32 on one CPU with a software-rendered desktop and USB access. Its scoped RAM/I/O tests and older input reports belong to that build; they are not measurements of this new 15-CPU profile. The earlier aura prototype also failed to reach Linux. Both records remain in [the status history](STATUS-2026-11-08.md) and [JOURNEY.md](JOURNEY.md).

The [canonical full-laptop checklist](STATUS-2026-11-08.md#full-laptop-integration-checklist) separates these scoped native results from remaining Wi-Fi/BT, battery, audio, display-control, sleep and recovery/update integration. CPUFreq STATUS reads can reconcile framework state; they are not guaranteed passive measurements.

## Read more

- **[STATUS-2026-11-08.md](STATUS-2026-11-08.md):** detailed status and chronology (CPU, GPU, Wi-Fi, RAM/storage), with limits and rollback.
- **[SOURCES.md](SOURCES.md):** public sources we used (adopted / candidate / incompatible), licences, AI-instruction notes, and **tasks a helper can take on**.
- [HISTORY.md](HISTORY.md): the previous front page (early milestones, the FT-series status table, the logbook, earlier source-audit notes).
- [JOURNEY.md](JOURNEY.md): every build and its native outcome.
- [keyboard/STATUS-2026-11-05.md](keyboard/STATUS-2026-11-05.md): keyboard bring-up findings and corrections.
- [PLATFORM-PORT.md](PLATFORM-PORT.md): the platform (SMC/battery/sensors) port.

## Current boot path, and cautions

1. **Refreshed stub macOS.** The owner completed the paired-Recovery enrollment on the 26C5035r stub. The main macOS security policy is separate.
2. **Public-source-derived m1n1 stage1 → ESP stage2.** The enrolled stage1 remains fixed; the small stage2 uses the public `boot=` storage path to load separate kernel/DTB/initrd files. The oversized monolithic payload was rejected by the live-heap guard; that guard remains intact.
3. **Linux and initrd.** The current GPU profile starts all 15 CPUs and Aurora, validates the existing 120 GB root, applies temporary legacy-unit masks and starts the scoped USB access service.
4. **Existing Omarchy rootfs.** Normal systemd/SDDM/Hyprland runs on the ext4 root. The older `m5boot/` and kexec implementation remains published here as history.

**Cautions:**
- Boot-policy, partition and physical Recovery operations remain owner decisions. The tested N1 start used an orderly filesystem shutdown followed by owner cold power/BootPicker selection. A verified warm next-only attempt returned to macOS; its cause is unresolved. `systemctl poweroff` alone is not proof of physical power removal on the restricted D415 profile.
- Kernel/DTB/initrd changes can use the enrolled ESP path without a new enrollment while stage1 remains unchanged; changing the enrolled stage1 itself is a separate operation.
- The current masks are per boot. No pre-Linux automatic recovery or universal watchdog fallback is promised; keep the owner power-button/macOS fallback available for experimental boots.
- This repo ships **no binaries**: no boot objects, kernels, DTBs, initramfs, rootfs images or Apple firmware. The current local integration is not yet a complete public reproduction bundle.
- The current published artifacts remain experimental bring-up. Installer integration is the new project direction; it does not retroactively qualify this stack for daily use.

## How we work, AI, and licensing
- **Who does what:**
  - The owner makes every destructive or physical decision.
  - One AI operator session at a time touches the Mac.
  - Other AI sessions do source analysis and builds off-device.
- **AI and upstream rules:**
  - We record each upstream's AI instructions. AsahiLinux/m1n1 (and omacom/m1n1 `main`) ask AI tools not to use them. Under an explicit owner project exception (2026-11-08), licensed public m1n1 sources may be read, compared and built locally, with every licence and attribution kept.
  - Code taken from forks or other projects keeps its source and per-file licence, and is not described as clean-room work.
  - Nothing here is submitted to Asahi Linux, per their LLM policy.
- **Licences:**
  - `m5boot/` is GPL-2.0.
  - `m5-omarchy/` has no licence file yet, so all rights are reserved by the owner, except files with their own SPDX header (e.g. kernel patches GPL-2.0).
  - Third-party sources and their licences are listed in [SOURCES.md](SOURCES.md).

## Credits
- **betizzel** ([betizzel/omarchy-m5](https://github.com/betizzel/omarchy-m5)): the J714s bring-up we built on, the stub scripts, T6050 kernel patches and DT.
- **Asahi Linux**: the kernel, docs and installer work.
- **Aurora Silicon** ([aura](https://github.com/aurora-silicon/aura), [linux](https://github.com/aurora-silicon/linux)), including [G17S GPU #1173](https://github.com/aurora-silicon/linux/pull/1173): the kernel and M5 work we build on.
- **rolotrealanis98**: the public [M5 Pro integration and tests](https://github.com/rolotrealanis98/m5pro-linux), [Mesa `043a4c5`](https://github.com/rolotrealanis98/mesa/commit/043a4c58080c4951fea3797fe45fc6898ce77632), and GPU/session recipes reused for this trial; **omacom/m1n1 contributors** for the loader chain.
- **Omarchy / omacom** and the community threads: [omacom/linux-aurora#293](https://github.com/omacom/linux-aurora/issues/293), [omacom/omarchy-mac-installer#149](https://github.com/omacom/omarchy-mac-installer/issues/149). Public findings by edimoldovan, rolotrealanis98, birkskyum and scottjones are cited in the reports.
- Alpine Linux, Arch Linux ARM, and everyone publishing their M5 findings.

## Layout
- `STATUS-2026-11-08.md`, `SOURCES.md`, `HISTORY.md`, `JOURNEY.md`: current status, sources, history.
- `m5boot/`: the boot object (source, tests, spec, notes), GPL-2.0.
- `m5-omarchy/`: research reports, kernel patches and DT overrides, build scripts, initramfs, rootfs overlay.
- `patches/`: kernel diffs and reproduction notes up to build #28.
- `keyboard/`, `usb/`, `wifi-n1/`, `logs/`: findings and scrubbed native logs.
- `tools/`: small host-side helper scripts.
- `SCAN.md`: what was excluded or scrubbed for publication.
