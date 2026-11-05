# 55 — u9 FIFO/debug dump: the FIFOs are fine; ACM also queues a notify → u10d (gser)

## u9 dwc3dump (NATIVE, `reports/native-u9.txt`)
- **TxFIFOs are contiguous and don't overlap.** MDWIDTH is 128 bits (GHWPARAMS0[15:8] = 0x80).
  - TX0: start 0, depth 0x23 (560 B, enough for ep0's 512 B).
  - TX1–TX7: each 0xc7 deep, starting at 0x23, 0xea, 0x1b1, 0x278, 0x33f, 0x406 and 0x4cd.
  - The end, 0x594, is within RAM1 (GHWPARAMS7[15:0] = 0xe92).
- **RX FIFOs:** RX0 is at 0, depth 0x3e8.
- **The FIFO-size hypothesis (report 52 #1) is ruled out, so u10a and u10b aren't needed.**
- **TX2 changes after SET_CONFIGURATION:** it goes from 0x00ea00c7 to 0x00ea**8**0c7. Bit 15 is set by the hardware (Linux doesn't write the FIFO registers). TX2 is the FIFO of the notify endpoint ep2in. HYPOTHESIS: this flags "FIFO holds data", i.e. the queued notification.
- **DEPCMD_1 = 0x00010006** (ep0in START_TRANSFER, resource 1) and **DEPCMD_5 = 0x00020007** (ep2in UPDATE_TRANSFER). Neither command is active and both have status 0. GEVNTCOUNT0 = 0: no events are pending, so the controller never generated the status completion at all.

## u9 trace (NATIVE, `native-u9-trace.txt`)
**ACM also queues IN data at SET_CONFIGURATION.** The steps run in this order:
1. ep2in (int, FIFO 2), ep1in (bulk, FIFO 1) and ep1out are enabled, each with its no-op START_TRANSFER.
2. f_acm queues a **10-byte SERIAL_STATE notify** on ep2in, an HWO TRB followed by Update Transfer.
3. The ep0in status2 Start Transfer is Successful, but it **never completes**.

So u9 didn't remove the variable it was meant to remove; my report 52 premise ("ACM queues nothing") was wrong. ECM (u8) and ACM (u9) have the same pattern: **IN data is pending on ep2in/FIFO2 when the ep0in status ZLP is armed.**

## u10d (built): generic serial, so no IN is queued at SET_CONFIGURATION
- **f_serial (gser) has bulk IN and OUT only, with no notify endpoint.** It queues only OUT reads at set_alt. IN data is written only once a tty is opened, and the runner doesn't open one.
- **If u10d configures** (the host binds the `usb_serial_simple`/generic driver, or at least no -110), the pending-IN-on-another-FIFO theory holds. The next step is a real fix: delay notify endpoints until after the status stage (a small dwc3 or composite patch), and then ECM gets SSH.
- **If u10d fails too,** the cause is enabling the endpoints or their no-op STARTs, and **u10c's knob matrix** (already built) decides between them.
- **Kernel "usbdbg3":** usbdbg2 (with the dwc3 knobs, off by default) plus `CONFIG_USB_CONFIGFS_SERIAL`. Image `536a187f…`. The kernel config gains only a function driver, so the usbdbg modules still load.
- **Push:**
  - m5next/ = `build/usb-v1/m5next-u10d/`: Image `536a187f…`, initrd `6fe015a9…`, cmdline `1bc8864d…` with marker `USB-U10D`.
  - m5drop/ = `loop/u10d/m5drop/`.
  - Cable stays on the left-front port.
- **Order:** run **u10d, then u10c**. They're independent, and each takes about 10 minutes.

## u8p (NATIVE, `native-u8p.txt`, host side reported by the PM)
Same failure with `iommu.passthrough=1`: the DART is ruled out.

Labels: dumps and traces NATIVE; the meaning of bit 15 is HYPOTHESIS; u10d built, not run.
