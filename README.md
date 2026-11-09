# omarchy-m5

Bringing [Omarchy](https://omarchy.org) - Arch Linux ARM + Hyprland - to the
**M5 Pro MacBook Pro**: Apple **T6050 "Sotra"**, Mac17,9 / J714s, dual-booted
beside macOS, Asahi-style.

This is frontier J714s bring-up, built on
[m1n1](https://github.com/AsahiLinux/m1n1) and
[linux-asahi](https://github.com/AsahiLinux/linux). A Linux ThinkPad drives the
Mac over USB-C. The installed raw m1n1 boots Linux on **all 15 cores** now that
the Omarchy stub carries Apple's fixed firmware (macOS 27.3 beta 1 or later).
A pinned [Aura](https://github.com/aurora-silicon/aura) Mach-O Stage 1 is also
packaged as an alternative; it has not been tested on hardware.

A separate, pinned [Aurora Linux](https://github.com/aurora-silicon/linux)
kernel now drives the **internal display through DCP**, including a readable
console, brightness control and display off/on. This is a kernel alternative,
not the Aura bootloader trial; it uses the existing raw-m1n1 boot path.

> **Reviewing this?** Start with **[`FOR-AURORA.md`](FOR-AURORA.md)** - the three
> things worth your time, and what to skip.

## Status - verified on hardware

Unless noted, this table describes the default `vendor/linux` kernel.
The experimental Aurora/DCP path and its limits are described below.

| Area | State |
| --- | --- |
| Boot chain | ✅ iBoot → m1n1 → Linux kernel, **all 15 cores** (stub firmware ≥ mBoot-20457.60) |
| Root filesystem | ✅ Arch on the **internal SSD** (`nvme0n1p5`), dual-boot, macOS preserved |
| Storage | ✅ NVMe (ANS2 + NVMMU + SARTv4) |
| Console / display | ✅ simpledrm fallback (`eDP-1`); experimental Aurora DCP (`eDP-2`) with brightness and display off/on. Patched Hyprland 0.57.1 works on DCP at 3024x1890 / 120 Hz, software-rendered (no GPU) |
| Input | ✅ built-in keyboard **and** trackpad (DockChannel MTP + `tpmtfw`) |
| Keyboard backlight | ✅ `fpwm0` + pwm-leds (`/sys/class/leds/kbd_backlight`) |
| CPU frequency | ✅ all three clusters on schedutil; P cores measured 1307 MHz before, about 4.22 GHz after |
| CPU idle | ✅ WFI on all 15 cores, no `idle=nop` (patches 0012 + 0013): idle draws 5.6 W in total (SoC 1.6 W) against 15.3 W with `idle=nop` |
| SMC | ✅ hwmon (both fans, temperatures, power rails); lid opens wake the Mac from sleep; RTC registers |
| Networking | ✅ USB-C gadget (CDC EEM) - host reaches the Mac over the cable |
| m1n1 on upstream `main` | ✅ USB enumeration unblocked on T6050 (`patches/m1n1/0005`) |
| **SMP - secondary CPUs** | ✅ 15/15 online (2026-11-06): stub rebuilt from macOS 27.3 beta 1 (`scripts/refresh-stub-firmware.sh`), kernel patches 0009 + 0010 |
| Sleep (s2idle) | ✅ On the default kernel, `systemctl suspend` or closing the lid sleeps, and opening the lid wakes it (patch 0011 fixes a resume SError in the debug UART). With cpuidle registered (patch 0013) the tick and timekeeping stop during sleep. The default simpledrm path leaves the panel lit |
| Battery / charger | Verified on Aurora: battery telemetry, charging/discharging and charger notifications. Still disabled on the default fallback kernel |
| Wi-Fi / Bluetooth (N1) | Not yet qualified on J714s; a separate driver/firmware trial is pending |
| GPU | Native GL/compute and Vulkan-backed Zink checks pass on this J714s, using an isolated simpledrm trial with Linux DCP off. Accelerated desktop, GPU+DCP and sustained-load qualification remain open |

Today the machine boots Arch from the internal SSD on **all 15 cores**; the
kernel is staged over the USB tether (`boot-m5.sh`). Apple fixed the
single-core raw-boot-object bug in macOS 27.3 beta 1, but the fix only reaches
Linux once the Omarchy stub is rebuilt from that macOS: the stub supplies its
own stage-2 firmware.

## SMP: fixed by Apple's firmware

On stub firmware cloned from macOS 26.5, every secondary failed to start
([probe log](docs/research/probe-logs/t6050-cpu-impl-0100-2026-11-04-j714s.log)).
Apple fixed "only a single core is available when you boot Linux ... from a
custom raw boot object" on M5 Pro/Max/Ultra in macOS 27.3 beta 1 (26C5035r).
The stage-2 firmware that loads m1n1 comes from the Omarchy stub's own restore
bundle, so after updating macOS the stub has to be rebuilt:
[`docs/bringup.md` -> Stub firmware refresh](docs/bringup.md#stub-firmware-refresh-all-cores).
With `mBoot-20457.60.65.0.1` the unchanged installed m1n1 starts 14/14
secondaries.

Linux also needs patch 0009 with `arm64.nowfxt` (cores lose state in WFIT; a
kernel without the override panics in `__delay` on CPU1), patch 0012 (WFI
loses x0-x30 and FP/SIMD on every core except the boot CPU, so the idle path
saves them; `idle=nop` is gone) and patch 0010 (the ANS firmware can take
about 3 s to answer RTKit on an all-core boot). The October SPTM attribution
does not explain the failure: the fix is in mBoot, with m1n1 unchanged.
[`docs/smp-t6050-findings.md`](docs/smp-t6050-findings.md) keeps the
measurements of the broken firmware, with that history labeled.

## Internal DCP display (experimental Aurora kernel)

`make kernel-aurora` builds Linux 7.3 from pinned Aurora commit
`5b0f106acdd71de11400464adfeb8c87a83b20b0` plus
[`patches/linux-aurora/`](patches/linux-aurora/). The default `make kernel`
and its artifacts stay separate. Package it with
`KERNEL_FLAVOR=aurora scripts/mktether.sh`; see the
[build and fallback instructions](docs/bringup.md#aurora-kernel-with-internal-dcp-experimental).

Verified on J714s with stub firmware **mBoot-20457.60.65.0.1**:
all 15 CPUs, internal SSD root, USB networking, trackpad motion and clicks,
DCP framebuffer console, brightness changes and display off/on.
The console needed both fbdev damage
submission and ARGB pixels: this firmware treats the fourth XRGB byte as
alpha, so otherwise valid console text was invisible.

SMC power samples on this DCP boot averaged **9.09 W at brightness
setting 300**, versus **5.55 W with the display blanked**, with keyboard
backlight still at 200/255 (15 samples each). These are awake measurements,
not sleep power; the earlier simpledrm brightness was not controlled.

This does **not** provide GPU acceleration. A basic software-rendered
Hyprland desktop and native Wayland terminals are now verified on DCP at
3024x1890, 120 Hz, using the
[alpha-only scanout fix](patches/hyprland/0001-output-support-alpha-only-scanout.patch).
Unpatched Hyprland 0.57.1 assumes XRGB during mode tests and crashes on this
alpha-only primary plane; the fix selects an advertised format and permits
ARGB/ABGR. The user config and packaged compositor are unchanged; the tested
build is a local override described in the
[runbook](docs/bringup.md#aurora-kernel-with-internal-dcp-experimental).
Lid suspend/resume still needs qualification on DCP. Keep the default kernel
as the tested fallback; do not infer sleep or GPU support from the desktop.

## M5 Pro GPU trial (isolated J714s)

The isolated GPU trial now performs real rendering on this J714s. Two boots of
`7.3.0-g929e67a1da3e` passed native GL/compute and Vulkan-backed Zink smoke
checks, plus all 14 indexed-rendering cases in each mode, with no new kernel
messages during the tests. The GPU reports **Apple M5 Pro (G17S B1), 16 enabled
cores**. This is short functional coverage, not Vulkan conformance or general
application/thermal qualification.

The working profile uses **simpledrm, with Linux DCP disabled**. It combines
Aurora Linux PR #1173, Mesa PR #194 and the minimal m1n1 GPU handoff, retaining
**this Mac's own voltage bins**, not the other J714s's draft voltage profile.
`make kernel-aurora-gpu-simpledrm` and `make m1n1-gpu-simpledrm` use private
build trees; `scripts/build-mesa-gpu.sh` packages Mesa and its Vulkan loader
under `/opt`, without replacing system graphics libraries.

Both original recovery bundles and the installed boot object are unchanged.
The corrected trial loader also passed a live watchdog-preservation check.
Touch firmware reached READY on both GPU boots, but physical input and an
accelerated Hyprland session still need checking. The
[GPU runbook](docs/bringup.md#gpu-trial-isolated-j714s) records the tested
artifacts, source pins, live calibration guard, earlier control findings and
remaining limits. **GPU + DCP is not yet qualified.**

## Aura Mach-O Stage 1 (optional, untested on hardware)

`make aura-test` packages a pinned Aura v1.0.0b4 Mach-O Stage 1 with our
kernel/DT and a RAM-only diagnostic image. SMP no longer depends on it. See
[`docs/bringup.md` -> Aura Mach-O diagnostic trial](docs/bringup.md#aura-mach-o-diagnostic-trial-j714s)
for preflight, approval, testing and rollback.

## Repo map

- **[`docs/`](docs/)** - everything written down; **[`docs/README.md`](docs/README.md)**
  indexes it (current state, SMP RE, build guide, Phase-0 research).
- `dt/` - the T6050 device trees, authored from **this machine's real ADT**
  (`scripts/adt2pmgr.py`), not guessed.
- `patches/m1n1/`, `patches/linux/` - the default bootloader and kernel changes;
  `patches/linux-aurora/` - the separate pinned Aurora/DCP port.
- `scripts/` - the dev harness (build / install / tether) and
  `scripts/probes/` (the hardware RE tooling).
- `configs/` - kernel configs · `tools/` - tiny on-device C helpers ·
  `Makefile` - `make setup fetch m1n1 dtbs kernel`.

## Build & dev loop

See **[`docs/bringup.md`](docs/bringup.md)**. Short version:

```sh
make setup fetch m1n1 dtbs kernel   # toolchain, vendor clones, m1n1, DTBs, kernel
```

The original on-device install (partitioning + `kmutil`) is in
`docs/bringup.md` -> *"One-time on-device step"*. After a macOS update, rebuild
only the stub (`scripts/refresh-stub-firmware.sh`); do not repeat the
installation. Kernel uploads are memory-only, but the normal tether workflow
subsequently boots the SSD root filesystem.

## Credits & upstreams

Built on the Asahi Linux project and the omarchy-mac / Aurora Silicon ecosystem.
The hardware reverse-engineering here is interoperability work on the author's
own Mac.

- [m1n1](https://github.com/AsahiLinux/m1n1) ·
  [linux-asahi](https://github.com/AsahiLinux/linux) ·
  [Asahi feature support](https://asahilinux.org/docs/platform/feature-support/)
- [omarchy-mac](https://github.com/omacom/omarchy-mac) ·
  [Aurora Silicon](https://github.com/aurora-silicon)
- [rolotrealanis98/m5pro-linux](https://github.com/rolotrealanis98/m5pro-linux) -
  found that the 27.3 beta 1 SMP fix needs a rebuilt stub, and the RTKit timeout.
- [edimoldovan/linux-aurora](https://github.com/edimoldovan/linux-aurora) - J714c
  platform work ported here (P-cluster DVFS, eDP connector, keyboard backlight,
  T6050 fan keys).
- [antiapplefox/m5-linux](https://github.com/antiapplefox/m5-linux) - the SPTM
  static-RE / XNU-shim track behind the earlier SMP investigation.
