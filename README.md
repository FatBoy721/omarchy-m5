# Omarchy-M5-Pro

> *"It boots."* — us, 47 times, about 11 of which were true.

Native Linux, then [Omarchy](https://omarchy.org), on a **14-inch MacBook Pro with M5 Pro** (board **J714s**, Mac17,9, SoC **T6050**), bare-metal next to macOS. No VM, no emulator. This is a lab notebook with a commit history, not a product: every result is labelled, and claims that turned out wrong are corrected in place.

**Labels:**
- **NATIVE** = seen on this J714s.
- **REPORTED** = someone else's claim.
- **offline** = built and reviewed, not run.

## Current status (as of 2026-11-07 21:01 America/New_York)
> **Right now:**
> - The owner is updating the **main macOS to 27.3**; the update is still in progress.
> - **All Mac actions are on hold.**
> - The Linux stub's loader is still the **all-core prototype object (`4f318f1b`)** from the 2026-11-08 trial. Restoring the original loader is **pending**, so the tested Linux baseline below **can't be booted until that restore is done**.
> - The startup disk is still set to the stub; the owner will set it back to macOS.
> - Whether the stub's own firmware changes with the macOS update is not proven.
>
> Every result below was measured on **macOS 26.6.2**, with the stub at mBoot-18000.161.10.

### Tested baseline (NATIVE, kernel 7.2.2 #32)
| Area | State |
|---|---|
| Boot | Our raw loader (m5boot) → kernel #32. One-shot boots; macOS is normally the default; a hardware watchdog returns to macOS on failure |
| Desktop | Omarchy (SDDM → Hyprland), **software rendering only** |
| Access | Root shell and SSH over USB-C |
| Storage / memory | NVMe ext4 root and zram swap. Scoped memtest and I/O checks passed (not a guarantee) |
| CPU | **One core** (frequency scaling works) |
| Keyboard | **Owner-confirmed typing** on earlier kernels (FT9 / FT14 / FT18-r2); not re-tested on #32 |
| Trackpad | **Owner-reported working** on the kernel #30 boot (2026-11-06); not re-tested since |
| Wi-Fi / Bluetooth | **Not working.** The first activation attempt (build 3408) reset the machine; cause unknown. A staged diagnostic is prepared, not run |
| GPU acceleration | **No** (see the GPU gate below) |
| Battery / sensors / lid, suspend, USB host, camera, speakers, Touch ID | Not working or not verified |

### Experimental all-core path (not the baseline)
- **One extra core (NATIVE, macOS 26.6.2):**
  - booted as an aura-wrapped Mach-O object, one secondary core ran our reset code at EL2 and **parked within 6 µs**;
  - it was never handed to Linux;
  - booted as a raw object instead, no core acknowledged.
- **All 15 cores: not achieved.**
  - The prototype combines public [aura `5211a863`](https://github.com/aurora-silicon/aura/commit/5211a863fc3f2c8eb56b5feae64cf05cc9a1dca6), [aurora-silicon/linux #985](https://github.com/aurora-silicon/linux/pull/985) and our unpublished T6050 patch.
  - **One native attempt (2026-11-08):** aura's USB proxy device appeared, but **Linux was not reached**. Cause not determined.
- **Input on this path is not assumed.** Keyboard and trackpad results above come from the baseline kernels, not the prototype; its 7.3 kernel has no module tree on our rootfs.

### GPU gate
Graphics are unaccelerated. Two things are missing:
1. **A J714s GPU voltage table.**
   - Our J714s ADT differs from the J716s table in [aurora-silicon/linux #1173](https://github.com/aurora-silicon/linux/pull/1173) in 13 of 14 states, and their table sits below this part's values at several states.
   - Our ADT's SRAM entry is a constant `1385`, whose meaning is unknown.
2. **G17S GPU firmware from macOS 27.x in the stub.**
   - #1173's source supports 27.2 and 27.3 firmware, but its only hardware result is 27.3 beta 1 on a J716s (REPORTED).
   - Updating the main macOS doesn't by itself prove the stub changes.

No promise of GPU acceleration is made here.

## Read more
- **[STATUS-2026-11-08.md](STATUS-2026-11-08.md):** detailed status and chronology (CPU, GPU, Wi-Fi, RAM/storage), with limits and rollback.
- **[SOURCES.md](SOURCES.md):** public sources we used (adopted / candidate / incompatible), licences, AI-instruction notes, and **tasks a helper can take on**.
- [HISTORY.md](HISTORY.md): the previous front page (early milestones, the FT-series status table, the logbook, earlier source-audit notes).
- [JOURNEY.md](JOURNEY.md): every build and its native outcome.
- [keyboard/STATUS-2026-11-05.md](keyboard/STATUS-2026-11-05.md): keyboard bring-up findings and corrections.
- [PLATFORM-PORT.md](PLATFORM-PORT.md): the platform (SMC/battery/sensors) port.

## How it boots, and cautions
1. **Stub macOS.** A small APFS volume group next to macOS, created with betizzel's stub scripts ([betizzel/omarchy-m5](https://github.com/betizzel/omarchy-m5)).
   - The stub alone is set to Permissive in its paired recoveryOS; **macOS itself stays at Full Security**.
2. **m5boot** (`m5boot/`). Our raw ARM64 boot object: it reads iBoot's boot arguments and ADT, handles the watchdogs, builds a device tree and starts Linux.
3. **Linux.** An Asahi 7.2 base + betizzel's T6050 patches + ours. An initramfs logs to the ESP and switches into the 120 GB Linux partition (label `omarchy`).
4. **Omarchy rootfs.** Built from signed packages (Arch Linux ARM + Omarchy's channel).

**Cautions:**
- Every boot-policy, partition or Recovery step is an owner decision; Recovery visits are done by hand.
- Changing the stub's boot object needs a stub-paired Recovery visit.
- This repo ships **no binaries**: no boot objects, kernels, DTBs, initramfs, rootfs images or Apple firmware. Hashes are listed only to match results to builds.
- It is an experimental bring-up, not an installer.

## How we work, AI, and licensing
- **Who does what:**
  - The owner makes every destructive or physical decision.
  - One AI operator session at a time touches the Mac.
  - Other AI sessions do source analysis and builds off-device.
- **AI and upstream rules:**
  - We follow each upstream's AI instructions; our AI sessions don't use upstream AsahiLinux/m1n1, whose instructions ask AI tools not to.
  - Code taken from forks or other projects keeps its source and per-file licence, and is not described as clean-room work.
  - Nothing here is submitted to Asahi Linux, per their LLM policy.
- **Licences:**
  - `m5boot/` is GPL-2.0.
  - `m5-omarchy/` has no licence file yet, so all rights are reserved by the owner, except files with their own SPDX header (e.g. kernel patches GPL-2.0).
  - Third-party sources and their licences are listed in [SOURCES.md](SOURCES.md).

## Credits
- **betizzel** ([betizzel/omarchy-m5](https://github.com/betizzel/omarchy-m5)): the J714s bring-up we built on, the stub scripts, T6050 kernel patches and DT.
- **Asahi Linux**: the kernel, docs and installer work.
- **Aurora Silicon** ([aura](https://github.com/aurora-silicon/aura), [linux](https://github.com/aurora-silicon/linux)): the CTXR/EL2 and M5 work we build on.
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
