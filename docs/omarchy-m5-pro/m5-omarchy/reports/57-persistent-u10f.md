# 57 — Persistent SSH-over-USB set; u10f (dwc3-level fix)

**u10d (NATIVE, reported by the PM):** the gser gadget **configured**. The host saw no -110, `bConfigurationValue=1` and interface 3-3.2:1.0 at 10:37:47. That confirms report 55: when IN data is pending on another endpoint, the Apple dwc3 never completes the ep0 status ZLP.

## The dwc3-level fix (`tools/kernel/patches/m5-dwc3-debug-knobs.patch`, now three knobs)
- **New knob `dwc3.m5_hold_in`** (0644, default 0). When it is 1, a request queued on a non-ep0 IN endpoint while a control transfer is in progress is held. The hardware gets no TRB and no Update Transfer for it.
  - "In progress" means anything except `ep0state == SETUP_PHASE && ep0_next_event == COMPLETE`.
  - The endpoint gets the flag `DWC3_EP_M5_HELD`, and later requests on it queue behind the held one.
- **Release:** `dwc3_m5_release_held()` runs at the end of `dwc3_ep0_complete_status()`, after the next SETUP has been armed. It kicks each held endpoint that is still enabled.
- **Limit (HYPOTHESIS):** a TRB that is already in hardware when the next control transfer starts is not recalled. For ECM, the f_ecm delay covers that case, so the persistent set uses both fixes.
- **Kernel "usbdbg5":** usbdbg4 (with the f_ecm defer) plus this patch. Image `5b9108c2…`. The config is unchanged, so the usbdbg modules load.

## u10f: the dwc3 fix on its own
- **What it tests:** the u10e flow (ECM-only, sshd, trace) with `dwc3.m5_hold_in=1` and **`usb_f_ecm.m5_notify_delay_ms=0`** (stock ECM). This isolates the dwc3 fix.
- **Push:**
  - m5next/ = `build/usb-v1/m5next-u10f/`: Image `5b9108c2…`, initrd `6fe015a9…`, cmdline `5b2e824e…` with marker `USB-U10F`.
  - m5drop/ = `loop/u10f/m5drop/`.

## Persistent set for the normal Omarchy boot
- **m5next/ = `build/usb-v1/m5next-usbnet/`:** Image `5b9108c2…` (usbdbg5), initrd `6fe015a9…`, cmdline `8fb42f46…`.
  - The cmdline is the test cmdline **without `m5.autoreboot`, `m5.testmarker` and `initcall_debug`**, so there is no auto-reboot guard and no experiment runner.
  - `maxcpus=1`, `m5_pmgr_ro`, `m5_pmgr_allow=ans` and the nvme options stay as they were in every USB test.
- **m5drop/ = `tools/rootfs/m5drop-usbnet/`**, rewritten for the left-front port:
  - **Service:** `m5-usbnet.service`, a oneshot pulled in by sddm.
  - **Kernel check:** it runs only on the usbdbg5 kernel, which it recognises by both knobs being present.
  - **Sequence:**
    1. Set `m5_hold_in=1` and the ECM delay to 2000 ms.
    2. Power ATC1 (common, usb, phymxwrap) one domain at a time with `m5_usb port=1`, stopping if a domain doesn't reach actual f.
    3. Bring up the device PHY, then run `dt_nopd` and bind `2aa280000.usb`.
    4. Create the ECM gadget, assign `usb0` 10.55.0.1/24, start sshd.
  - **sshd:** key-only (`sshd_config.d/m5.conf`, work key in `m5_authorized_keys`, git-ignored). NetworkManager leaves `usb0` unmanaged.
  - **No more hpm step:** hpm1 reads time out, and u10d configured without them.
  - **Modules:** `m5_usb.ko` `c040c621…` (usbdbg build).
- **Host side (report 49):** use the left-front port, `ip addr add 10.55.0.2/24 dev <ecm-if>`, then `ssh alarm@10.55.0.1`.
- **Order:** promote this set only after u10e (or u10f) shows SSH working. If u10f works on its own, the f_ecm delay can be dropped later.

Labels: u10d REPORTED (NATIVE, by the PM); u10f and the persistent set are built, not run.
