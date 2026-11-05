# 53 — u10a / u10b: TxFIFO layout fixes for the SET_CONFIGURATION status stall

**Context (from the PM):**
- u8p failed the same way as u8 (NATIVE, iommu passthrough), so the DART is ruled out.
- u9 (ACM-only, with a FIFO dump) is still pending.
- dwc3 GTXFIFOSIZ/GRXFIFOSIZ writes from m5_usb are approved. They are volatile controller registers and reset on reboot.

Both sets use the u8 flow: left-front port (Port-USB-C@2), hpm1 read, ATC1 power-on, ECM-only gadget, usbdbg trace and dartinfo. Image and initrd are the same as u8 (`09ec53ef…` / `6fe015a9…`). m5_usb.ko sha `c040c621…`.

## Sets
| Set | m5next/ | m5drop/ | Change |
|---|---|---|---|
| **u10a** | `build/usb-v1/m5next-u10a/` (cmdline `53772bb0…`, marker `USB-U10A`) | `loop/u10a/m5drop/` | `dt_nopd fiforesize=1` adds `tx-fifo-resize` to usb@2aa280000 before the dwc3 bind |
| **u10b** | `build/usb-v1/m5next-u10b/` (cmdline `bd8c0bd3…`, marker `USB-U10B`) | `loop/u10b/m5drop/` | explicit layout from the new `m5_usb op=fifo` |

**u10a: dwc3 sizes the FIFOs itself.** The kernel driver then programs GTXFIFOSIZ on every SET_CONFIGURATION (`dwc3_gadget_clear_tx_fifos` and the resize at endpoint enable, gadget.c:753/816). Because this happens inside the SET_CONFIGURATION path, a core soft reset can't undo it.

**u10b: m5_usb writes the layout.** `op=fifo` (the approved writes) does this:
- Reads the IN-endpoint count from GHWPARAMS3[22:18] and the RAM1 depth from GHWPARAMS7[15:0].
- Logs every GTXFIFOSIZ value before and after.
- Leaves FIFO0 (ep0in) as it is.
- Gives FIFO1..n-1 contiguous, non-overlapping ranges: equal shares of the remaining RAM1, each capped at 0x400 words.
- Writes nothing if the share would be below 0x10 words or the count above 16.
- Skips any register that already holds the target value.

The runner sequence is:
1. UDC bind.
2. soft_connect disconnect, then dwc3dump.
3. `op=fifo`.
4. connect.
5. `op=fifo` again, then dwc3dump.

Step 5 is there because connect runs `dwc3_core_soft_reset` (gadget.c:2782). If the soft reset puts the FIFO registers back to their defaults, the second `op=fifo` rewrites them, and the log shows that it happened. The host re-enumerates on connect.
- **Known risk:** that second write races the host's enumeration (HYPOTHESIS, low impact). If it lands while ep0 is mid-transfer, that transfer can fail. The next re-authorize retries it.

## How to read the results
- **u10a or u10b gets past SET_CONFIGURATION:**
  - the host gets `cdc_ether`, then `ssh alarm@10.55.0.1` after the host-side IP setup in report 49;
  - the fix that worked goes into the persistent `m5drop-usbnet` (port=1, usid=0xa, atc1);
  - u10a's way (the DT property) is preferred.
- **Both fail, but u9 (ACM) passes:** the FIFO size isn't the cause; data already queued on the notify endpoint is. Next is the f_ecm deferred-notify patch (report 52).
- **All of u9, u10a and u10b fail:** compare u9's GDBGEPINFO and DEPCMD_1 with the trace.

Labels: built, not run; the mechanism is HYPOTHESIS.
