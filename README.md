# Omarchy-M5-Pro

Native Linux, then [Omarchy](https://omarchy.org), on a **14-inch MacBook Pro with M5 Pro** (board **J714s**, Mac17,9, SoC **T6050**), booted bare-metal next to macOS. This is the working journey: every build, every native result (including the failures and the claims we had to retract), the source and how we work. Nothing here is a finished product.

## Status (2026-11-05)
Labels: **NATIVE** = seen on our J714s · **VM** = QEMU · **REPORTED** = someone else's claim, not reproduced · **HYPOTHESIS** = our guess.

| What | State | Label |
|---|---|---|
| Our own boot object (m5boot) runs from iBoot as a raw fuOS image | works since beacon3 (green paint), gz3 (console) | NATIVE |
| Linux 7.2 (slim, single core) boots to the initramfs shell, earlycon on the framebuffer | works (gz5+) | NATIVE |
| The ~45 s idle reset | fixed in gz10: a secondary watchdog word (0x2_8833_0008, read 0x7c = armed) is now cleared; ran 264 s, no reset | NATIVE |
| Logs without a camera (raw on disk0s5 + FAT32 on the ESP, readable from macOS) | works (gz9+), see `logs/` | NATIVE |
| Initramfs → `switch_root` into the Omarchy ext4 rootfs → SDDM autologin → Hyprland (simpledrm + llvmpipe) | **Omarchy booted natively on gz12 (2026-11-05 00:03)**: owner saw the desktop come up; log confirmation from the ESP pending | NATIVE (owner-observed) |
| Internal keyboard/trackpad (MTP/DockChannel) | DTB I1 built (gz12), untested | HYPOTHESIS |
| USB gadget / SSH | blocked: ATC0 USB power chain + eUSB2 PHY bring-up; power half in gz13, untested | HYPOTHESIS |
| SMP (more than one core), GPU | not started; SMP is reported to need a newer stub firmware (macOS 27.3b1+) | REPORTED |

## How it boots
1. **Stub macOS** (a small APFS volume group next to macOS) created with **betizzel's MIT stub scripts** (`prep-stub.sh` / `finish-install.sh`, github.com/betizzel/omarchy-m5). In the stub's paired 1TR: `bputil -nc` (Permissive on the stub only) and `kmutil configure-boot --raw --entry-point 2048 --lowest-virtual-address 0`. macOS itself stays at Full Security.
2. **m5boot** (`m5boot/`, ours, clean-room): a raw ARM64 image with a branch at offset 0, padded to 16 KiB (the stock-image iBoot panic on 26.6.x is avoided by this header, NATIVE). It reads iBoot's boot_args/ADT, disables the watchdogs, builds a FDT, inflates an embedded `Image.gz` and jumps to Linux.
3. **Linux**: Asahi's `asahi-wip-7.2` + betizzel's T6050 patches + ours (`m5-omarchy/tools/kernel/patches`: framebuffer earlycon, PMGR write logging / read-only / allow-list). DT overrides in `m5-omarchy/tools/kernel/dts`.
4. **Initramfs** (busybox): logs to disk, then `m5.root=s5` finds the 120 GB Linux partition (label `omarchy`) and `switch_root`s into it.
5. **Omarchy rootfs** built from signed packages (ALARM + Omarchy's channel), with an overlay for autologin, software rendering and logging to the ESP.

## How we work
- **Owner** (the human): owns the Mac, makes every destructive or physical decision, does the physical steps (power-holds, typing credentials in 1TR, photos early on).
- **PM**: a Claude session that writes tasks (`*/tasks/`), reviews results, runs read-only and approved commands on the Mac.
- **Workers**: Claude sessions doing one task at a time. `m5-omarchy/` is the research/kernel/rootfs worker (`reports/` are its write-ups). `m5boot/` is a separate clean-room implementer that sees only a cited spec (`m5boot/spec`).
- Rules: label every result, never claim an install that wasn't verified, keep provenance, no secrets. When a result turned out wrong it was **retracted in place**, never deleted (see JOURNEY.md).

## AI and m1n1
- **We did not use, read, clone, build or run m1n1 or any of its forks** (AsahiLinux/m1n1, aurora-silicon aura/m1n1, others). Upstream m1n1 asks AI tools not to use it; we treated its forks the same way. m5boot was written from public documentation (Asahi docs, XNU headers, Linux sources) only; m1n1 behaviour described by third parties is marked as such.
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
