# Installer stones: the J714s kernel and loader from omarchy-mac-installer

TripleU613 is collecting the public M5 work into one J714s system image in
[TripleU613/omarchy-mac-installer](https://github.com/TripleU613/omarchy-mac-installer)
(see [linux-aurora#293](https://github.com/omacom/linux-aurora/issues/293)).
This page brings that image's kernel and loader into this repo as an extra,
isolated build flavor, so both trees live side by side and can be merged here.

Nothing in the default `vendor/linux`, `aurora` or `aurora-gpu` paths changes.

## Build

```sh
make kernel-aurora-installer   # KERNEL_FLAVOR=aurora-installer scripts/build-kernel-aurora.sh
make m1n1-installer            # build/m1n1-installer, chainloadable
```

| Piece | Base | Series | Reproduces |
| --- | --- | --- | --- |
| Kernel | `34f2f5bb4d03` (same base as `aurora-gpu`) | `patches/linux-aurora-installer/` | tree `291ffd1b50cc`; installer patch sha256 `616d8e7f21f6...` |
| Config | full `.config` | `configs/aurora-j714s-installer.config` | installer `kernel/config` |
| m1n1 | **omacom/m1n1** `02785a35e046` (not AsahiLinux) | `patches/m1n1-installer/` | tree `332d560c2f73`; installer patch sha256 `d634a7aba77b...` |

Both series apply byte-for-byte to their bases (checked). The installer's
package recipes pin the same patch hashes, and its ARM CI built
`linux-aurora 7.3.0.aurora15.j714s2` and `m1n1-aurora 1.6.1.aurora22.j714s2`
from them. Not booted through the normal U-Boot/Limine chain yet.

## What this flavor adds over this repo

- **N1 Wi-Fi / Bluetooth** (none of it exists in `patches/linux-aurora*`):
  Centauri kernel-owned PCIe train, `apple_centauri` Wi-Fi, `btcentauri`,
  bindings, `pcie@1cb0000000` + `wlan`/`bluetooth` DT nodes, and the m1n1 N1
  host-tunable admission/copy it depends on.
  Hardware result on J714s, 2026-11-08: association, DHCP, default route,
  device-bound DNS and HTTPS passed
  ([`omarchy-m5-pro/STATUS-2026-11-08.md`](omarchy-m5-pro/STATUS-2026-11-08.md)).
  That run used a different kernel (the local "D415" baseline plus
  [`kernel-n1-integration.patch`](omarchy-m5-pro/patches/2026-11-09/n1-j714s/));
  this flavor's N1 code derives from it, but this exact frozen tree has not
  itself been booted for Wi-Fi.
  Workaround needed: NetworkManager rejects the passphrase/SAE form with
  `CONNECT = -95`; store the network's 64-hex WPA2 PMK instead (derived
  locally from passphrase + SSID, never on a command line). Reconnect after
  reboot and Bluetooth are unqualified.
- **T6050 USB2/USB3/DP PHY** (`drivers/phy/apple/atc-t6050-*`, `usb-t6050/`).
- **G17S GPU J714s board profile + fuse guard** (upstream form:
  [rolotrealanis98/linux#1](https://github.com/rolotrealanis98/linux/pull/1)).
- cpufreq, WFI idle, SMC hwmon/input/gpio, DART, PCIe, NVMe, AOP/macaudio
  match data and audio DT (audio is **disabled** in this config).

## What it lacks compared with this repo

- DCP internal display (`DRM_APPLE` off, DCP nodes disabled), firmware 27.x
  DCP tables, alpha scanout: use this repo's `patches/linux-aurora` 0008-0015.
- Battery / SMC power (`MACSMC_POWER`, `POWER_RESET_MACSMC` off): this
  repo's 0016 + verified Aurora battery telemetry.
- Framebuffer checkpoint markers, AIC VM-timer and pmdomain fixes in 0001-0004.

## Merge map (toward one series)

The two series describe J714s with **different DT layouts**: this repo's
`t6050.dtsi`/`t6050-jxxx.dtsi`/`t6050-pmgr.dtsi`/`t6050-dcp.dtsi`/... versus
the installer's `t6050-base.dtsi`/`die0`/`dieX`/`max`/`ultra` (Rolo's J716s
layout). Pick one layout, then:

**Cherry-pick as-is** (files only the installer series touches): Centauri
Wi-Fi/BT drivers and bindings, `net/bluetooth/*`, `drivers/phy/apple/*`,
`drivers/pci/*`, `include/linux/pci.h`, cpufreq, `arch/arm64/kernel/idle.c`,
SMC gpio/hwmon/input/mfd, DART, NVMe, dwc3, reset-cio, pinctrl, AOP/audio.

**3-way merge, then test on hardware** (both series change them):

```
arch/arm64/boot/dts/apple/Makefile
arch/arm64/boot/dts/apple/t6050-j714s.dts
drivers/gpu/drm/asahi/driver.rs
drivers/gpu/drm/asahi/g17/fw/m5/initdata.rs
drivers/gpu/drm/asahi/hw/t6050.rs
drivers/gpu/drm/sysfb/simpledrm.c
drivers/pmdomain/apple/pmgr-pwrstate.c
drivers/power/supply/macsmc-power.c
drivers/soc/apple/rtkit.c
drivers/soc/apple/sart.c
```

Port the `pcie@1cb0000000` N1 node with its `wlan`/`bluetooth` children into
whichever DT layout wins.

### Done: `aurora-n1` (`patches/linux-aurora-n1`)

This merge now exists as one patch on top of `linux-aurora` + `linux-aurora-gpu`,
keeping this repo's DT layout (`make kernel-aurora-n1`):

- All installer-only files merged as-is. Conflicts: this repo's SARTv4, RTKit
  timeout, macsmc-power work lifetime and simpledrm kept; the pmgr auto-PM
  guard combines both (`m5_pmgr_ro` stays opt-in).
- **GPU voltage bins are per chip, and the two J714s units differ** (ADT
  `e68662cd...` vs `d7feb012...`). `apple,j714s-gpu` keeps betizzel's bins;
  `apple,j714s-gpu-tripleu` (DTB `t6050-j714s-gpu-tripleu*.dtb`) selects
  TripleU613's, behind the fuse-mask guard. A J714s without a per-unit GPU
  compatible now refuses GPU init instead of guessing.
- `t6050-j714s-n1.dtsi`: N1 PCIe host, port, DART, `wifi0`/`bluetooth0`, all
  disabled in the shared tree. The `-tripleu` DTBs enable the host; the
  installer m1n1 enables the port and DART after training.
- Centauri Wi-Fi/BT are modules (`request_firmware_direct` needs the rootfs).

**Status 2026-11-10, TripleU613's J714s, bare metal** (exact series `linux-aurora-n1` 0001-0008, kernel `7.3.0-g6fd53e01a76b`, harness tree `a52459a2430a`): boots with 15 CPUs,
N1 Wi-Fi (associated, DHCP, Tailscale) and Bluetooth, GPU (aurora firmware
initdata acknowledged; Vulkan "Apple M5 Pro (G17S B1)" via the native Mesa
session env) and simpledrm on the internal panel.

How it boots: the installer-family ESP stage-2 m1n1 with
`patches/m1n1-installer/0002` (3-cell AIC for the GPU mailboxes;
`make m1n1-installer-stage2`), DTB `t6050-j714s-gpu-tripleu-simpledrm.dtb`,
the installer's boot args plus `fpwm0` in `m5_pmgr_allow`, and the modules
under `/usr/lib/modules/<release>`.

Bugs found on the way (each now fixed in this flavor or its loader):

| Symptom | Cause | Fix |
| --- | --- | --- |
| hang in `deferred_probe_initcall` | `m5_pmgr_ro` skips power-on of `fpwm0`; the kbd-backlight PWM probe hits an unpowered block | add `fpwm0` to `m5_pmgr_allow` |
| SError when pinctrl probes | DT lacked `gpio-reserved-ranges`; pin 112 is secure | reserved ranges on `pinctrl_ap` (betizzel's `0004`, found independently) |
| N1 port deferred forever | `pinctrl-apple-gpio` was `=m`, PERST# unresolved | `=y` in `aurora-j714s-n1.config` |
| "invalid or missing MSI slice" | pcie-apple only took 4-cell AIC slices | accept 3-cell (betizzel's `0005`, found independently) |
| port/DART left disabled | loader keys kernel-train mode off `apple,manual-availability` | `apple,manual-availability` on `dart_apcie0` (in the shared N1 dtsi) |
| "GPU is disabled ... not filling it" / "mailbox GFX has no usable interrupts" | loader fills only an enabled node and assumed 4-cell AIC | `&gpu` okay (`0008`) + `patches/m1n1-installer/0002` |

**DCP (internal display), 2026-11-10, same unit, under the m1n1 hypervisor only.**
With `chosen.asahi,t6050-display=1`, DTB `t6050-j714s-gpu-tripleu.dtb` (not
`-simpledrm`) and `patches/m1n1-installer/0003`-`0004`, the installer loader
hands off the running DCP (`handed off: framebuffer 0x105d310c000+0x57ac000,
firmware 27.3 beta`), and the firmware-27 driver picks build `27.2.98.1`,
boots the DCP, sees the panel and modesets 3024x1890@120 (`appledrmfb` on
fb0). Before 0003 the loader refused (`a display node has no phandle`: dtc
gives the unreferenced dcp and display-subsystem nodes none); before 0004 the
kernel refused (`firmware-compat 27.3.0 has no 27.x method table`).
**Not yet good:** the same loader and DTB booted on bare metal hung with no
network or USB (cause not yet read); the HV guest logs `format XR24 ... not
supported`; no HV session has stayed up past about a minute after login.
Keep `t6050-display=0` for daily boots.

Still open: `ufw` fails (IPv6 netfilter missing from the config); the USB EEM
gadget link drops after boot; Arch's `kernel-modules-hook` deletes this
kernel's modules whenever another kernel boots (package them, or make this
the default). Found with `tools/m5-remote` (m1n1 hypervisor + MMIO tracing).

**Result 2026-11-09 (betizzel's unit, this repo's loader): the merged tree runs
the N1.** Flavor `aurora-gpu-n1-simpledrm` (this unit's GPU bins) with
`make m1n1-gpu-n1`: this repo's GPU loader with a DT-only port of the
kernel-train hand-off, so its watchdog, GPU and DCP handling stay as verified.
Linux trained the link, loaded the firmware and brought up `wlan0` and `hci0`;
WPA3 association, DHCP, DNS and HTTPS passed. The runbook and results are in
[`bringup.md`](bringup.md#n1-wi-fi-and-bluetooth-isolated-j714s).

The merge needed five more patches (`patches/linux-aurora-n1/0002`–`0006`) and
one config change before that. All of them are pieces the installer tree has
in its own layout and the merge onto this layout lost:

- `CONFIG_PINCTRL_APPLE_GPIO=y`, with `gpio-reserved-ranges` on the AP bank:
  PERST# (pin 80) needs the bank's driver, and pin 112 must stay unread.
- The T6050 MSI window check accepted only the four-cell AIC specifier of the
  `die0` layout; this layout's AIC has three cells.
- The **GP power closure**: `apple,always-on` on `apcie_gp`, `apcie_sys_gp`,
  `apcie_phy_sw`, `aphy_gp_aus5_a` and `aphy_gp_aus5`, with `apple,no-auto-pm`
  on the three that iBoot leaves auto-gated. Without it the kernel train stops
  at `shared PHY: … waiting for 0x4/0x4`. It lives in
  `t6050-j714s-n1-host.dtsi`, which both units' N1 trees include.
- `apple,manual-availability` on `dart_apcie0` (as found above).
- The FT21 SMC write gate and the installer's NVMe/cpufreq compatibles had
  become the default. On this tree that removes battery, lid and RTC and puts
  NVMe and cpufreq on bindings this unit never ran, so 0003 makes the gate
  opt-in (`macsmc.m5_smc_gate=1`) and restores the verified compatibles.

The `-tripleu` trees carry the same fixes and were **not** booted here; with
`m5_smc_gate` now opt-in, a boot of that unit that relied on the gate has to
ask for it. The `CONNECT = -95` passphrase rejection did not occur with
NetworkManager 1.58.1 and wpa_supplicant 2.12: SAE was offloaded at the first
attempt.

## Credits

| Who | Work this flavor builds on |
| --- | --- |
| [rolotrealanis98](https://github.com/rolotrealanis98) | T6050 kernel base `34f2f5bb`, J716s DT layout, Centauri N1 kernel train and m1n1 patch0028, G17S M5 initdata |
| [edimoldovan](https://github.com/edimoldovan) | J714c T6050 CPU bring-up, cpufreq and AFE/PCIe work the T6050 pieces were matched against |
| [betizzel](https://github.com/betizzel) | this repo: J714s 15-core SMP, DVFS, WFI idle, s2idle, DCP, battery, GPU/Zink |
| [TripleU613](https://github.com/TripleU613) | J714s DT for this layout, N1 host profile and Wi-Fi bring-up, GPU voltage profile/fuse guard, installer image |
| omacom / aurora-silicon | m1n1 and Aurora kernel upstreams |

Patches keep their upstream licenses (kernel GPL-2.0, m1n1 MIT); new files
carry their own SPDX headers.

Full source inventory:
[installer SOURCES.md](https://github.com/TripleU613/omarchy-mac-installer/blob/main/SOURCES.md).
