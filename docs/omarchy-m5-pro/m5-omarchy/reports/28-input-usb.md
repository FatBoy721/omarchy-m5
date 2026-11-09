# 28 — Input (MTP keyboard/trackpad) and the USB power path (VM: boots; NATIVE pending)

Artifacts and hashes: `~/m5boot/spec/inputs.md` § Input v1. Kernel = desktop config + patch 0002 (allow-list, 10 ms poll). DTBs I1/U1. Initramfs and rootfs now include the trackpad firmware.

## Priority 1: keyboard/trackpad (DTB I1)
- **Why MTP may simply work now:**
  - gz5's SError came with **both** the MTP DART and the USB0 DART enabled, and USB0's DART was the next to probe (report 24).
  - betizzel (REPORTED, private message, summarized) expects ATC0 USB to be **off at iBoot hand-off**, which would explain the SError without a power domain. Their MTP keyboard worked natively under Linux with the **same DT** (MTP + DART enabled, ATC domains untouched).
  - So **I1 = DTB C (USB DARTs off) + MTP, mtp_mbox, mtp_dart, mtp_dockchannel, mtp_hid re-enabled.** That isolates MTP.
- **PMGR:** none. The ADT has no MTP pmgr device, so with `m5_pmgr_ro` I1 adds no PMGR writes.
- **DAPF:**
  - The ADT dart-mtp has three windows (`instance` tags `DART`/`DAPF`/`PS_PROT`): DART 0x294800000 (0xc000), **DAPF 0x294810000 (0x4000)**, PS_PROT 0x2890fc000 (0x4000). It also has `dapf-instance-0` (5 windows) and `dart-tunables-instance-0`.
  - **No allowed source gives the DAPF register layout**: the Linux apple-dart driver has only the BYPASS_DAPF TCR bit (report 24). So Linux does **not** program DAPF. [HYPOTHESIS] iBoot leaves DAPF configured, since it preloads and starts MTP (`pre-loaded = 1`); betizzel's working boot doesn't separate "m1n1 did it" from "iBoot did it".
  - If I1 shows the MTP RTKit up but no keyboard events (or MTP crash reports), DAPF is the next suspect. A read-only dump of 0x294810000 would need a `devmem` tool (busybox here has none); that's the next step.
- **Trackpad firmware:**
  - Extracted **on ush, without touching the Mac**: betizzel's `scripts/extract-tpmtfw.py` (no license header, so local use only, report 06) with asahi-installer's MIT `asahi_firmware/multitouch.py`, against Apple's **26.6.2 IPSW** via HTTP ranges. That's the same build as our stub (cloned from 26.6.2, report 08), so it matches the MTP image iBoot preloads.
  - Result `build/firmware/apple/tpmtfw-j714s.bin`, 79,956 B, header `HIDF` v1 (what `dchid_get_firmware()` checks). It's in the initramfs `/lib/firmware/apple/` (the built-in driver probes there) and the rootfs `/usr/lib/firmware/apple/`.
  - Apple firmware: keep it local, never publish.
  - Optional macOS cross-check (read-only): `sudo find /System/Volumes/Preboot -path '*restore*' -iname 'Multitouch*.im4p' -exec shasum -a 256 {} \;`, compared with the same file pulled from the IPSW.

## Priority 2: USB gadget (DTB U1, experimental)
- **Power** (REPORTED: ATC0 needs no PMP; m1n1 powers COMMON + USB_AON + USB + PHY wrapper with ~10 ms polling):
  - **Allow-list:** `m5_pmgr_allow=<labels>` under `m5_pmgr_ro`. Only the named domains may be written; everything else stays read-only. The matching logic is checked by `tools/kernel/tests/m5-pmgr-allow-test.c` (prefixes like `atc0_us` are rejected).
  - **Poll timeout** 100 µs → **10 ms** (global; it only lengthens the wait on a slow domain).
  - The "Failed to reach power state … (now: …)" message now prints the polled register, not the pre-write one.
  - **U1 DT:** dwc3_0 + dart_0 on `ps_atc0_usb` (genpd powers its parents `atc0_common`, `atc0_usb_aon` first), dart_1 on `ps_atc0_phymxwrap` (ponytail: a single-domain workaround to get the PIPE-mux wrapper powered).
- **New PMGR writes (U1 + allow cmdline only), all logged `m5 pmgr:` before they happen:**
  - power-on (target 0xf) of atc0_common (0x280600208), atc0_usb_aon (0x288300148), atc0_usb (0x288300150), atc0_phymxwrap (0x288300158);
  - the driver's AUTO_ENABLE writes on those same four.
  - Caution (REPORTED): their only ATC -110 appeared when AUTO_ENABLE was set on already-on domains. Patch 0003 (betizzel) skips that write when the bit is already set.
- **Not done: eUSB2 PHY reset/run, forced VBUS-valid, PIPE-mux to a dummy PHY.** The third-party note describes m1n1's behaviour, but no allowed source gives register addresses/offsets, and writing guessed MMIO is outside the safety rules.
  - **Expected U1 result:** the domains power on (logged); DWC3 core soft reset **times out (-110)** without PHY bring-up. That validates the power half on hardware.
  - Next step: the PHY register map, from the ADT `atc-phy0` node's tunables/regs or a PHY description from betizzel (behaviour-level), then a small Linux PHY driver.
- **Safety:** no SMC, no audio, no new writes outside the four listed domains.

## Recommendation
Boot **I1 first** (`m5_pmgr_ro`, `m5.root=s5`): keyboard/trackpad on the desktop is the goal, and I1 adds no PMGR writes. If the ESP log shows a SError at MTP, revert to DTB C and take the DAPF route. U1 is a separate, later boot.

## VM
The input-v1 kernel + new initramfs boot QEMU virt to the initramfs shell with `m5_pmgr_ro m5_pmgr_allow=…` parsed. MTP and PMGR can't be exercised in a VM.
