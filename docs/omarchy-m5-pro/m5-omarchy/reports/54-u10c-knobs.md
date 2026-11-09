# 54 — u9 ACM also fails → u10c: dwc3 SET_CONFIGURATION knob matrix

**u9 (NATIVE, from the PM's host-side report):** the ACM-only gadget fails the same way (`can't set config #1, error -110`, no ttyACM). So data queued on the ECM notify endpoint isn't the cause. u9's device-side FIFO dump is still to come; u10a and u10b stay ready to run.

## What the PM asked me to rule in or out (from the u8 trace, NATIVE)
- **Delayed status: ruled out.** dwc3 does prepare and start the ep0in status2 TRB right after SET_CONFIGURATION (u8 trace line ~252). With `USB_GADGET_DELAYED_STATUS`, no such TRB would exist until the function queues it.
- **LPM/U1/U2: ruled out.**
  - The U1/U2 changes in `dwc3_ep0_set_config` are SuperSpeed-only, and this link runs at HS.
  - `DCFG.LPM_CAP` = 0 and `gadget-lpm-disable` is in the live DT.
  - DSTS shows the link state is ON, not L1.
- **What remains:** the hardware-side steps that SET_CONFIGURATION adds over SET_ADDRESS:
  - (a) `DEPSTARTCFG(XferRscIdx=2)` in `dwc3_ep0_set_config` (ep0.c);
  - (b) DEPCFG/XFERCFG for the new endpoint;
  - (c) the **no-op START_TRANSFER** that dwc3 issues on every bulk/int endpoint enable (gadget.c, "Issue StartTransfer here with no-op TRB"). ACM's notify endpoint gets it too, which matches u9 failing.

## u10c (built)
- **Kernel "usbdbg2":** usbdbg plus `tools/kernel/patches/m5-dwc3-debug-knobs.patch`, which adds two **runtime** knobs (0644):
  - `dwc3.m5_skip_startcfg` skips (a);
  - `dwc3.m5_no_noop_start` skips (c). The endpoint's first real request then uses START_TRANSFER, because the STARTED flag is never set.
  - Config is unchanged, so the usbdbg modules still load.
  - Image `fece13bd…`.
- **Push:**
  - m5next/ = `build/usb-v1/m5next-u10c/`: Image `fece13bd…`, initrd `6fe015a9…` (the same as u8), cmdline `3276db20…` with marker `USB-U10C`.
  - m5drop/ = `loop/u10c/m5drop/`.
  - Cable stays on the left-front port.
- **Flow:** the u8 flow with ECM only, starting with skip_startcfg=1 before the bind. That is attempt 1/0.
- **Matrix:** if attempt 1/0 fails, the runner soft-reconnects through 0/1 → 1/1 → 0/0 → 1/0.
  - Each attempt clears the trace, logs `TRY startcfg_skip=X noop_skip=Y connected HH:MM:SS` and waits 40 s.
  - It counts an attempt as successful when an `ep0in Transfer Complete [Status Phase]` follows `Set Configuration` in the trace, and stops at the first success.
  - Then it runs a dwc3dump and 6 minutes of state logs.
  - Each attempt's trace is saved through trsave (`trace-u10c-*`).
- **For the PM, host side:** note the time of each `can't set config` or success, so it can be matched to the TRY lines (≈41 s apart).

**What the matrix tells us (HYPOTHESIS):**
- **1/0 works:** DEPSTARTCFG(2) is the cause. The fix is a quirk that skips it on Apple dwc3, which is safe with few endpoints.
- **0/1 works:** the no-op START_TRANSFER on the new IN endpoint wedges the TX path. The fix is to skip it.
- **Only 1/1 works:** both matter.
- **None works:** the cause is DEPCFG itself, likely FIFO assignment. Run u10a/u10b and use the u9 FIFO dump.

Labels: u9 result REPORTED by the PM (NATIVE); analysis HYPOTHESIS; u10c built, not run.
