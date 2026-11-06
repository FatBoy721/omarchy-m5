# Omarchy-M5-Pro

> *"It boots."* — us, 47 times, about 11 of which were true.

Native Linux, then [Omarchy](https://omarchy.org), on a **14-inch MacBook Pro with M5 Pro** (board **J714s**, Mac17,9, SoC **T6050**), bare-metal next to macOS. No VM, no emulator, no "works on my M2". This repo is the whole messy journey: every build, every native result, every failure, and every claim we had to walk back with our tail between our legs. It is not a product. It is a lab notebook with a commit history.

## TL;DR (2026-11-05, FT13 update)
**The built-in keyboard types in native Omarchy. The owner has tested it.** It is still very slow: this test kernel enables one CPU, and the framebuffer desktop saturates it. USB-C root SSH works on the same build. The trackpad enumerates but does not work; Wi-Fi still has no PCIe link.

The keyboard breakthrough was getting the MTP firmware past two blocked accesses, enabling the missing Apple HID driver, and setting one GPIO data bit **before** the keyboard processor starts. [Native findings, build hashes, and corrections](keyboard/STATUS-2026-11-05.md). This is an experimental bring-up, not a finished daily-driver install.

## Status
Labels: **NATIVE** = seen with our own eyes on the J714s · **VM** = QEMU · **REPORTED** = someone else said so · **HYPOTHESIS** = vibes, clearly labelled.

| What | State | Label |
|---|---|---|
| Our own boot object (m5boot) runs from iBoot | first green screen at beacon3, console at gz3 | NATIVE |
| Linux 7.2 boots | yes (gz5+) | NATIVE |
| The mystery ~45 s reset | a second watchdog hiding at 0x2_8833_0008. Cleared in gz10. Rest in peace. | NATIVE |
| **Omarchy desktop** (SDDM → Hyprland) | boots through FT13; one CPU and framebuffer rendering, severe lag | NATIVE |
| Hands-free test loop (macOS → Omarchy → back, no humans) | gz16 + guard/watchdog; the "3-minute auto return" now verified for real (h4) | NATIVE |
| **Root shell over USB serial** | 13:01: u10s (gser gadget + `agetty`) — `uid=0(root)`, `PRETTY_NAME="Omarchy"` | NATIVE |
| **SSH over USB-C** | verified through FT13: gser + CDC-EEM; root commands and a file read checked before cancelling the return timer | NATIVE |
| **Internal keyboard** | **FT9: owner-confirmed typing**, very slow. Correct controller ID `05ac:0359` discovered at boot | NATIVE |
| Internal trackpad | FT13 integrates host AFE reset; both SMC writes acknowledged, startup still times out. Real MMIO mapping test is being reviewed | NATIVE (failing) |
| Wi-Fi (N1) | prior runs: chip powered, port READY, root port answers `106b:100c`, link state machine stays at `0x00`; still unresolved | NATIVE (failing) |
| USB host (phone tethering) | port controller woken, roles set to SOURCE+DFP, phone charges for 5 glorious seconds, xHCI sees nothing | NATIVE (failing) |
| SMP / accelerated GPU | current build uses one CPU and simpledrm; no accelerated GPU demonstrated | NATIVE (limited) |
| CPU clock control | FT13 bounded states 5/6/7 trial changes instruction throughput as expected; restored boot state 6, write gate closed. No desktop-speed improvement yet verified | NATIVE |
| Persistent unattended access, battery, Touch ID, camera, speakers… | not verified complete | — |

**Correction:** the old claim that iBoot leaves MTP's DART locked with live translation tables was wrong. FT1 read SID0 with no valid table, streams disabled, and no SID0 lock. The later tables we had inspected were Linux's own. See the [correction and native evidence](keyboard/STATUS-2026-11-05.md#correction-to-the-earlier-dart-theory).

## Greatest hits from the logbook
- **"Our code runs!"** — it was a black screen. The build hadn't even been installed. (Retracted, see JOURNEY.md.)
- **A watcher that waited forever for "DONE 49"** while the worker had politely printed "DONE 50". One hour, gone.
- **A wait loop that matched its own command line** and reported "still running" about itself. Twice. Different days, same `pgrep`.
- **The firewall listener jammed** by a mystery local process knocking every 10 seconds, so the Mac's first dial-in call went to voicemail.
- **USB SSH "didn't work" for an hour** because the PC's serial driver also grabbed the network interface, then NetworkManager ate the IP address. The Mac was fine the whole time.
- **The breakthrough idea** (put a shell on the USB serial port that had *already worked*) came from a human-forwarded review, not from us. Credit where due.

## How it boots
1. **Stub macOS** (a small APFS volume group next to macOS) created with **betizzel's MIT stub scripts** (`prep-stub.sh` / `finish-install.sh`, github.com/betizzel/omarchy-m5). In the stub's paired 1TR: `bputil -nc` (Permissive on the stub only) and `kmutil configure-boot --raw --entry-point 2048 --lowest-virtual-address 0`. macOS itself stays at Full Security.
2. **m5boot** (`m5boot/`, initially written without reading m1n1): a raw ARM64 image with a branch at offset 0, padded to 16 KiB (the stock-image iBoot panic on 26.6.x is avoided by this header, NATIVE). It reads iBoot's boot_args/ADT, disables the watchdogs, builds a FDT, inflates an embedded `Image.gz` and jumps to Linux.
3. **Linux**: Asahi's `asahi-wip-7.2` + betizzel's T6050 patches + ours (`m5-omarchy/tools/kernel/patches`: framebuffer earlycon, PMGR write logging / read-only / allow-list). DT overrides in `m5-omarchy/tools/kernel/dts`. The installed gzft1 loader blacklists its input-related probes so the instrumented test kernel gets the first MTP start. One ESP `m5next/` set is consumed for that kernel switch.
4. **Initramfs** (busybox): logs to disk, then `m5.root=s5` finds the 120 GB Linux partition (label `omarchy`) and `switch_root`s into it.
5. **Omarchy rootfs** built from signed packages (ALARM + Omarchy's channel), with an overlay for autologin, software rendering and logging to the ESP.

## How we work
- **Owner** (the human): owns the Mac, makes every destructive or physical decision, holds the power button far more often than promised, and keeps everyone honest.
- **Current operator**: Codex, following the Claude handoff; one native operator at a time.
- **Engineering workers**: Claude sessions on the build host, doing source analysis and isolated builds. They do not independently touch the Mac. Antigravity is a separate research-only scout, writing findings incrementally.
- `m5-omarchy/` and `m5boot/` below are the published earlier snapshot. The new [status report](keyboard/STATUS-2026-11-05.md) records the later FT-series results; the source snapshot is not yet a complete reproduction of FT9.
- Rules: label every result, never claim an install that wasn't verified, keep provenance, no secrets. When a result turned out wrong it was **retracted in place**, never deleted (see JOURNEY.md).

## AI and m1n1
- **The initial m5boot and the FT9 result predate our m1n1 source audit.** That phase used public documentation (Asahi docs, XNU headers, Linux sources), without reading m1n1 or its forks.
- **On November 5, the owner opened source reuse for the next phase.** We now read upstream m1n1, aura and community forks to investigate secondary CPU startup, clocking and PCIe PHY initialization. Future changes derived from those implementations must identify their source and preserve the applicable per-file licenses; they cannot be described as clean-room work.
- Source audit references: [AsahiLinux/m1n1 `70757dc`](https://github.com/AsahiLinux/m1n1/tree/70757dc74c2dac485188acaa2fa7e73be5b108ee), [aurora-silicon/aura `077aabe`](https://github.com/aurora-silicon/aura/tree/077aabecd595fab9ebe34d3f3a28f10a82865d17), and [aurora-silicon/m1n1 `cf57aeb`](https://github.com/aurora-silicon/m1n1/tree/cf57aebc36b2c51c546d97f09e9bf390ff3f7be7). Source findings are not native test results.
- **Asahi Linux's policy forbids LLM-assisted contributions to Asahi.** Nothing in this repo is submitted to Asahi, and it should not be.

## Credits
- **betizzel** ([betizzel/omarchy-m5](https://github.com/betizzel/omarchy-m5)): the J714s bring-up we built on, the MIT stub scripts, the T6050 kernel patches and DT. Their agent also shared, in a private message (summarized here, not published), observations from their boots: that the idle reset matched a second watchdog word their loader clears, and that ATC0 USB needs no PMP but a longer power-up poll plus PHY bring-up.
- **Asahi Linux**: the kernel (`AsahiLinux/linux`), the docs, and asahi-installer (MIT).
- **Omarchy / omacom** and the community threads, by link: [omacom/linux-aurora#293](https://github.com/omacom/linux-aurora/issues/293), [omacom/omarchy-mac-installer#149](https://github.com/omacom/omarchy-mac-installer/issues/149). Public findings by edimoldovan, rolotrealanis98, birkskyum and scottjones are cited in the reports.
- Alpine Linux, Arch Linux ARM, and everyone publishing their M5 findings.

## Layout
- `JOURNEY.md`: every build and its native outcome.
- `m5boot/`: the boot object (source, tests, spec, NOTES, tasks), GPL-2.0.
- `m5-omarchy/`: research reports, kernel patches/DT overrides, build scripts, initramfs, rootfs overlay, tasks. No license file yet: all rights reserved by the owner until one is chosen, except files carrying their own SPDX header (e.g. `tools/step2-fast.sh` MIT, kernel patches GPL-2.0).
- `logs/`: native boot logs (scrubbed).
- `SCAN.md`: what was excluded or scrubbed for publication.

No binaries are included: no boot objects, kernels, DTBs, initramfs, rootfs images or Apple firmware. Hashes are listed so results can be matched to builds.
