# Omarchy-M5-Pro

> *"It boots."* — us, 47 times, about 11 of which were true.

Native Linux, then [Omarchy](https://omarchy.org), on a **14-inch MacBook Pro with M5 Pro** (board **J714s**, Mac17,9, SoC **T6050**), bare-metal next to macOS. No VM, no emulator. This is a lab notebook with a commit history, not a product: every result is labelled, and claims that turned out wrong are corrected in place.

**Labels:**
- **NATIVE** = seen on this J714s.
- **REPORTED** = someone else's claim.
- **offline** = built and reviewed, not run.

## Current status (2026-11-08)

**All 15 CPUs and native GPU acceleration now work in Omarchy, including a fresh login with persistent isolated Mesa integration.** Linux `7.3.0-j714s-dvfs-thermal-future-g34f2f5bb4d03-dirty` now boots through the refreshed-stub/public m1n1 route. Each CPU passed a pinned, affinity-checked known-answer test on the preceding GPU profile; Aurora reports **16 enabled GPU cores**. Four public rendering/pixel/compute tests passed, and Hyprland itself reports **Apple M5 Pro (G17S B1)** with the isolated Mesa libraries loaded.

The stub now uses **26C5035r / firmware 20457.60.65.0.1**. Its enrolled stage1 loads a small ESP stage2, which loads the kernel, DTB and initrd as separate files. Macintosh HD was verified as the persistent default before this one-shot Linux boot. Earlier statements below about an unrefreshed stub or an unbootable one-core baseline are historical.

| Area | Current evidence and limit |
|---|---|
| CPU / desktop | **15 online CPUs (`0-14`)**; all 15 passed pinned SHA-256/gzip checks on the preceding GPU profile. Manual OPP changes and brief **capped schedutil tests passed in all three cluster policies**, then restored `userspace` and the original rates/bounds, with boost off. These are nominal STATUS readings, not measured MHz or stock-maximum qualification. Hardware-rendered Hyprland, active **3024×1890** output and a nonblank desktop verified; the preceding GPU desktop passed 900 seconds with the old guard masked |
| USB access | Standard EEM-only `1d6b:0102`, class `02/0c/07`; native host binding and the scoped direct SSH route verified |
| RAM | **24 GiB physical**; Linux `MemTotal` is **23,896,896 KiB (22.79 GiB)** after reservations. **4 GiB allocated and locked concurrently** across four 1 GiB memtester workers; each completed all 18 checks, exit 0. This qualifies that sample, not all RAM. The earlier 2 GiB/180-second timeout remains partial |
| Storage | **1 TB Apple NVMe**, **120 GB ext4 root**. A new **4 GiB file write/fsync and separate direct CRC32C verification passed**, with stable SHA-256. Short uncapped file burst: fio **1.46 GB/s write / 5.79 GB/s read**, potentially controller-cache influenced; not sustained NAND or whole-device qualification |
| GPU | **NATIVE:** G17S firmware **27.3 / 26C5035r** initialized; actual fuse masks identify **16 enabled cores**. Four public tests passed, including 12-scene rendering/compute coverage. A normal UWSM-managed client also passed all 12 scenes on Apple G17S. Vulkan headless rendering, compute/render submissions and **15,597,568 CPU-model correctness checks** passed on Borealis |
| Input / other hardware | Earlier keyboard/trackpad results are historical; current completeness/latency is under owner trial. Read-only SMC monitoring now exposes named **TCMb**, a computed SoC hotspot; fan manual control stays disabled. Wi-Fi/BT, battery, suspend and other peripherals are not newly qualified |

The first split-payload boot did reach all 15 CPUs, but an old rootfs guard remained eligible and initiated the return around 900 seconds. The fix uses **per-boot `/run/systemd/system.control` masks**, which override the actual regular `/etc` unit files. The current profile keeps ordinary journals persistent and leaves the old guard/logger inactive. [Exact evidence, artifact hashes and handoff](STATUS-2026-11-08.md).

Mesa **`043a4c5`** remains isolated from system Mesa. A private `/opt` package and supported user UWSM hooks survived a fresh graphical login without the earlier runtime overlay; system Mesa remains unchanged. These are bounded functional, RAM-sample and file-I/O results, **not Vulkan conformance, full-memory, thermal-protection or long-soak qualification**. Simpledrm provides panel scanout while Aurora performs rendering; this is not the earlier llvmpipe desktop. The stable CPU rollback remains preserved.

### Historical one-core baseline

The earlier m5boot/kexec path ran kernel #32 on one CPU with a software-rendered desktop and USB access. Its scoped RAM/I/O tests and older input reports belong to that build; they are not measurements of this new 15-CPU profile. The earlier aura prototype also failed to reach Linux. Both records remain in [the status history](STATUS-2026-11-08.md) and [JOURNEY.md](JOURNEY.md).

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
- Boot-policy, partition and physical Recovery operations remain owner decisions.
- Kernel/DTB/initrd changes can use the enrolled ESP path without a new enrollment while stage1 remains unchanged; changing the enrolled stage1 itself is a separate operation.
- The current masks are per boot. No pre-Linux automatic recovery or universal watchdog fallback is promised; keep the owner power-button/macOS fallback available for experimental boots.
- This repo ships **no binaries**: no boot objects, kernels, DTBs, initramfs, rootfs images or Apple firmware. The current local integration is not yet a complete public reproduction bundle.
- This remains experimental bring-up, not an installer or a GPU-qualified daily driver.

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
