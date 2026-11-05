# Task 24 (URGENT): get past the native SError, a DT-only change

**NATIVE (owner photo `reports/native-gz5-linux-serror.jpg`, gz5 3bceded2):** **Linux 7.2.2-m5slim+ #5 booted natively** on "Apple MacBook Pro (14-inch, M5 Pro, 2026) (DT)", with the earlycon on the FB, initcall_debug, single core. It ran through the PMGR power-domain probes (apple_pmgr_ps_driver_init OK), then apple_dart_driver_init:
- `apple-dart 294800000.iommu: Limiting DMA range to 0x0000010000004000..0x00000100ffff3fff`
- `platform 294600000.mtp: Adding to iommu group 0`, `platform 294b20000.input: Adding to iommu group 0`
- `apple-dart 294800000.iommu: DART [pagesize 4000, 16 streams, bypass support: 1, bypass forced: 0, locked: 0, AS 42 -> 42] initialized`
- `probe of 294800000.iommu returned 0 after 540 usecs`
- then **`SError Interrupt on CPU0, code 0x00000000be000000 -- SError`**, Comm swapper/0, Tainted M (MACHINE_CHECK), pc el1_abort+0x3c, lr el1_abort+0x20. Regs: x0 = x21 = 0x2a2f0000, x1 = x19 = 0x96000410, x23 = 0x23400009, x9 = 0x100000000.
- `Kernel panic - not syncing: Asynchronous SError Interrupt`. It stays on screen (panic=0 works).

**Do (fast, DT only, no kernel rebuild unless needed):**
1. Disable the MTP (keyboard/trackpad DockChannel) and its DART for now: set `status = "disabled"` on the mtp node (294600000), its iommu dart (294800000), the input node (294b20000) and anything referencing that DART. That's the known MTP DART/DAPF issue (third-party: the MTP DART needs DAPF setup that m1n1's kboot does on T6050). Keep USB/DWC3 gadget, NVMe, simpledrm/earlycon.
2. Check whether any OTHER dart nodes or devices could hit the same problem (DARTs for USB/dwc3, ANS/NVMe, display). For anything not needed for the first SSH foothold (USB gadget + initramfs), disable it too. For DWC3 + its DART, keep them, but tell me whether the same DAPF issue could hit them.
3. Rebuild the DTB, record its hash in inputs.md (slim v2 section, DTB updated), and give a one-line summary of what you disabled.
4. Then (non-urgent, separate) start a short research note: what DAPF is, how it's configured from the ADT (properties on the dart node), and whether the Asahi/Aurora Linux apple-dart driver can program it (GPL kernel, AI-allowed), so the keyboard can come back without a bootloader change.

End with `DONE 24`.
