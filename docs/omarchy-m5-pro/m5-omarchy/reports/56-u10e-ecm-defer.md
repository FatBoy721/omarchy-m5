# 56 — u10e: ECM with deferred notifications + sshd (run if u10d configures)

## The fix (`tools/kernel/patches/m5-f_ecm-defer-notify.patch`, in the "usbdbg4" kernel)
- **What changes:** `ecm_notify()` no longer queues the CONNECT/SPEED_CHANGE notification inline from `set_alt`, `open` or `close`. It arms a `delayed_work` instead, and the work queues the notification later.
- **Why:** inline queueing happens inside SET_CONFIGURATION / SET_INTERFACE handling, so the notify TRB is pending on ep2in before the ep0 status ZLP is armed. That is the condition seen in u8 and u9.
- **The knob:** `usb_f_ecm.m5_notify_delay_ms`, writable at runtime (0644).
  - The kernel default is 50 ms; **the u10e runner sets 2000 ms**.
  - The longer delay covers the host's follow-up control transfers after SET_CONFIGURATION: SET_INTERFACE alt 1 when cdc_ether binds, plus the class filter requests.
  - 0 gives the stock behaviour.
- **Safety:**
  - The work checks that the notify endpoint is still enabled.
  - `ecm_disable` cancels it, and `ecm_unbind` cancels it synchronously.
  - The chained SPEED notification still comes from `ecm_notify_complete`, unchanged.
- **Kernel:** usbdbg3 (dwc3 knobs off, gser) + this patch. Image `bd7189a7…`. The config is unchanged, so the usbdbg modules load.

## u10e set
- **Push:**
  - m5next/ = `build/usb-v1/m5next-u10e/`: Image `bd7189a7…`, initrd `6fe015a9…`, cmdline `0bf7f455…` with marker `USB-U10E`.
  - m5drop/ = `loop/u10e/m5drop/`.
  - Cable on the left-front port (Port-USB-C@2).
- **Flow:** the u8 flow (hpm1 read, ATC1 power-on, dwc3 bind, ECM-only gadget, trace and dartinfo), with the 2000 ms delay set before the UDC bind. Then `usb0` gets 10.55.0.1/24 and **sshd** starts (key-only, `m5_authorized_keys`, git-ignored).
- **Host side, same as report 49:**
  1. Expect `cdc_ether`, with no -110.
  2. `ip addr add 10.55.0.2/24 dev <ecm-if>; ip link set <ecm-if> up`.
  3. `ssh alarm@10.55.0.1`.

## Caveat (HYPOTHESIS)
- **If the host never polls the notify endpoint before its next control transfer, a stall can still happen.** The delayed notification then sits on ep2in, and the next two-stage control transfer would stall the same way.
- **What it would look like:** -110 on a later request instead of on SET_CONFIGURATION.
- **The answer if so:** raise the delay further. It is a runtime knob, so this needs no rebuild. After that, the real fix is in dwc3 or the TX arbitration.

Labels: built, not run; this is only meaningful if u10d (gser) configures.
