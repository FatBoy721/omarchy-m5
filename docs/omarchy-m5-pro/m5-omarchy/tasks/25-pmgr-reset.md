# Task 25 (URGENT): gz6 native = HARD RESET during the PMGR power-domain probes (no panic printed)

**NATIVE (owner, gz6 21d62e37, DTB ce5bd290):** the earlycon log scrolled through the PMGR power-controller probe lines, then the **Mac rebooted** with no panic/oops on screen (panic=0, apple_wdt off). gz5 (old DTB) got past the PMGR probes into apple_dart and stopped with an SError panic that stayed on screen. So the new DT change is the prime suspect: `power-domains = <&ps_atc0_usb>` on dwc3_0 + its 2 DARTs. Possible mechanism (HYPOTHESIS): powering ATC0 USB (or a parent/notify_pmp domain) resets the SoC. Alternatively, a domain was switched OFF.

The owner is extracting the last video frame; meanwhile prepare **two** DTB variants plus kernel logging:
1. **DTB-A (most conservative):** the gz6 DT but WITHOUT the new power-domains on dwc3_0/DARTs, AND dwc3_0 + its DARTs **disabled too**. That gives no USB, so a clean test of whether the kernel then reaches the initramfs with only earlycon/NVMe/simpledrm. Expected: boots to the initramfs shell on screen.
2. **DTB-B:** the gz6 DT without the new power-domains (back to how gz5 had dwc3), but with the USB0 DART (0x2a2f00000) disabled and dwc3_0 using bypass (no iommus), to test the earlier SError hypothesis (an unpowered DART read).
3. Kernel: make the Apple pmgr power-domain driver log every power_on/power_off (domain name + register) at KERN_EMERG **before** the write, so the last line on screen names the domain that resets the chip. A small patch, keep it in tools/kernel/patches.
Build both DTBs + the logging kernel, record them in inputs.md (slim v3), and tell the implementer which one to build first (my recommendation: **DTB-A first**, to get the first stable shell on screen).
End with `DONE 25`.

## Addendum (PM, after the native gz6 video): the premise changed
The gz6 video shows Linux ran ~45 s, **past** the PMGR probes: deferred probe timeouts, `sync_state() pending` lines, then a cursor, **stable**. The reset came later while idle, so it's likely a second watchdog (the implementer handles that in gz7). The PMGR reset hypothesis is weakened. Revised priorities for task 25:
1. **Keep the gz6 DT** as the base (it gets furthest). DTB-A/B are optional.
2. **Visibility after the initcalls:** make `console=tty0` actually show on screen. Built-in simpledrm (or simplefb) + `FRAMEBUFFER_CONSOLE`, so /init and userspace output appear. Also make the initramfs `/init` mirror every message to `/dev/kmsg` (so it shows via the earlycon even without fbcon) and print `=== m5 initramfs ===` there.
3. **Why the USB path fails:** `PS b2bd_afc_0/1, b2bd_afr_0/3: Failed to reach power state 0xf (now 0xf0000ff / 0xd0f)`; USB0 DART `2a2f00000` probe -110. Are these the ATC/USB domains? Are they notify_pmp (the PMP-gated list from report 05)? If USB needs PMP, the gadget/SSH path is blocked; then propose the best alternative foothold (e.g. NVMe-based logging: write the dmesg to the 120 GB partition from the initramfs, then read it from macOS? macOS can't read ext4. A FAT32 log file on the EFI partition (disk0s4, FAT32) is readable from macOS!).
4. Rebuild the kernel/initramfs as needed and update inputs.md (slim v3).
