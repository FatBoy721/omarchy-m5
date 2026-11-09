# 51 — u8: SET_CONFIGURATION -110 on left-front; ECM-only, dwc3 trace, DART check

**Bottom line:**
- **u7 (NATIVE, as reported by the PM 09:32):**
  - The host enumerated `1d6b:0104 m5-omarchy` and read the descriptors and strings, so EP0 works on ATC1 (left-front).
  - It then failed with `can't set config #1, error -110`, twice.
- **u8 and u8p are built.** Both run the u7 flow on the same port with three changes:
  - the gadget is ECM only (no NCM);
  - a new usbdbg kernel records dwc3 + gadget trace events and turns on dynamic debug;
  - the runner logs iommu group and DART fault state around SET_CONFIGURATION.
- **u8p** is u8 plus `iommu.passthrough=1`. It is a direct A/B test for question (c).

## Sets (push one: m5next/ + m5drop/)
| Set | m5next/ | m5drop/ | Difference |
|---|---|---|---|
| **u8** (push first) | `build/usb-v1/m5next-u8/`: Image `09ec53ef…`, initrd `6fe015a9…`, cmdline `12583d97…` | `loop/u8/m5drop/` | marker `USB-U8` |
| **u8p** | `build/usb-v1/m5next-u8p/`: same Image and initrd, cmdline `62e63af4…` | `loop/u8p/m5drop/` | marker `USB-U8P`, `iommu.passthrough=1` |

- **Kernel "usbdbg":** usb-v1's config plus `tools/kernel/m5-usbdbg.config` (DEBUG_FS, FTRACE + default tracers → EVENT_TRACING, DYNAMIC_DEBUG). Build tree: `build/linux-usbdbg`. `uname -r` is unchanged (`7.2.2-m5slim+`); the guards key on the marker.
- **Modules rebuilt against usbdbg**, because tracing changes `struct module`:
  - m5_usb `071e5532…`, m5_hpm `23a78c65…`, m5_mtp `6e8e01c1…`;
  - `t6050_probe.ko` is rebuilt too and appended to the u7 initrd as a second cpio member, so the later entry replaces it.
- **The ssh key** is copied from u7 and stays git-ignored.

## What u8 records
- **Trace:** tracefs with an 8 MiB buffer and every `dwc3` event except `dwc3_readl`/`dwc3_writel`. This covers ctrl_req, ep_queue, gadget_ep_cmd (DEPCFG/DEPXFERCFG/STARTTRANSFER and their status), ep0 completion and events. `gadget` events (usb_ep_enable, queue, giveback) are on too.
- **Where the trace goes:** the ESP file `m5log/trace-u8-<boot>.txt`, rewritten with the last 6 MB at these points:
  - after the gadget is configured;
  - 5 s after the UDC is bound;
  - every minute for 10 minutes.
- **Dynamic debug:** turned on for `drivers/usb/dwc3/*`, `drivers/usb/gadget/*` and `apple-dart.c`. That output goes to the existing `exp-u8-*.txt` dmesg.
- **dartinfo:** each iommu group's type and devices, plus the last 40 `dart|iommu|fault` lines of dmesg.
- **The u7 tail, unchanged:** the sshd start, the dwc3dump calls, the soft_connect toggle at t+2m and the 10 minutes of logging. The service timeout is raised from 300 s to 840 s so the 10-minute loop isn't killed. The rest of the flow is unchanged from u7: `m5_hpm op=auto usid=0xa`, then ATC1 pon, dev, dt_nopd and the dwc3 bind.

## (c) Does the USB DART matter for non-EP0 endpoints? HYPOTHESIS
- **EP0 already goes through the DART.** dwc3 fetches EP0 TRBs and setup/data buffers by DMA from `dma_alloc_coherent` memory mapped through dwc3_1's DARTs (`iommus = <&dwc3_1_dart_0 0>, <&dwc3_1_dart_1 1>`, t6050-storage-net.dtsi:97). Descriptors were transferred, so translation works for that device.
- **The ECM/NCM endpoints use the same device and the same iommu domain.** A DART that is "missing" only for bulk or interrupt endpoints is therefore unlikely.
- **What could still be DART-related:** the bulk or interrupt endpoints might use the second DART (sid 1) for their DMA reads, while EP0 used only dart_0. u8p (passthrough) and the fault lines in dartinfo settle this either way.
- **More likely causes, ranked (both HYPOTHESIS):**
  1. A DEPCFG or DEPSTARTCFG command hangs or fails for the new endpoints at SET_CONFIGURATION. The `dwc3_gadget_ep_cmd` status in the trace will show it.
  2. The status stage never completes: no XferNotReady(status) is acted on.
- **How to tell them apart in the trace:** look for `dwc3_gadget_ep_cmd ... status: Timed Out` or a non-zero status, and check whether the ep0 status `dwc3_prepare_trb` and `dwc3_complete_trb` lines appear after the `Set Configuration` ctrl_req.

Labels: u7 result is REPORTED (by the PM) from a NATIVE run; u8/u8p are built and not run yet; §(c) is HYPOTHESIS.

## Addendum 2026-11-05 (PM message 09:38, `reports/native-u7.txt`)
- **SET_CONFIGURATION reached the device (NATIVE).** The device reports `udc state configured` at 98 s, yet the host still got -110. When the host re-authorized at 159 s, dwc3 logged `wait for SETUP phase timed out` and `ep0 data phase end transfer failed: -110`.
- **So the failure is in the status stage of a control transfer with no data stage.** Transfers with an IN data stage (the descriptors) work.
- **Both dwc3_1 DARTs are in translated mode, not bypass (NATIVE).** Each reports `bypass support: 1, bypass forced: 0, locked: 0`, and the kernel default domain is "Translated". u8p (`iommu.passthrough=1`) should therefore put them into hardware bypass, which makes it a real test of the PM's event-buffer/DART question.
- **hpm1 reads time out (NATIVE).** Registers 0x03, 0x08, 0x20, 0x2d and 0x3f returned -110, so MODE was unread and op=auto sent no SSPS. EP0 still worked, so hpm1's state isn't blocking USB2. u8 keeps the same read-only behaviour.
- **u8 already covers the PM's request,** with no rebuild needed: the gadget is ECM only; all dwc3 events (ctrl_req, prepare/complete_trb, gadget_ep_cmd, event) and gadget events are written to the ESP as `trace-u8-*`; dyndbg is on for dwc3; the dartinfo checks are in the log.
- **Two ways to read the u8 trace (HYPOTHESIS):**
  - If an `ep0` XferNotReady(Status) event appears after the Set Configuration ctrl_req, but no status TRB completes, the problem is the status TRB's DMA or the DART.
  - If no XferNotReady(Status) event ever appears, the problem is event delivery (DEVTEN or the event buffer).

## Addendum 2 (2026-11-05 09:45): register decode from native-u7, and why there is no u9 yet
dwc3dump read at 38.6 s and again at 98.7 s (NATIVE; decoded against the dwc3 core.h field layout).
- **DCFG 0x00a00840:**
  - Speed is HS.
  - DEVADDR is 8: SET_ADDRESS worked, and that is also a status stage without a data stage.
  - LPM_CAP (bit 22) is 0.
- **GUSB2PHYCFG 0x00102400:** SUSPHY (bit 6) = 0, ENBLSLPM (bit 8) = 0, USBTRDTIM = 9. The live FDT for usb@2aa280000 carries `snps,usb2-gadget-lpm-disable`, `dis_u2_susphy`, `dis_u3_susphy` and `dis_enblslpm`, so the PHY suspend and LPM/L1 idea is already excluded.
- **DSTS 0x0003fe10 → 0x0000b790:** link state stays 0 (ON), at HS, and the frame number keeps moving. The link didn't drop after config, so a missing VBUS/session override is unlikely.
- **DALEPENA 0x223:** ep0 and ep1, plus physical eps 5 and 9 (the two interrupt-IN notify endpoints of NCM and ECM). So SET_CONFIGURATION ran on the device: DEPSTARTCFG(2), then the DEPCFG/XFERCFG commands, then DALEPENA.
- **What is left:** the only thing SET_CONFIGURATION adds over SET_ADDRESS is DEPSTARTCFG(XferRscIdx=2) followed by the new endpoints' DEPCFG/DEPXFERCFG (ep0.c:654, `dwc3_ep0_set_config`). After that, the ep1 status START_TRANSFER apparently never completes.
- **Why there is no u9 yet:** the u8 trace (`dwc3_gadget_ep_cmd` status, then XferNotReady(Status) and `prepare_trb` on ep1) decides between the candidates directly. Each candidate has its own small fix, so a u9 now would be a guess.

**u9, chosen from what the u8 trace shows (HYPOTHESIS):**
1. **No XferNotReady(Status) arrives after Set Configuration.** The new endpoint resources clobber event delivery. u9 = a module op that reads DEPCMD/GEVNTCOUNT after config and re-arms ep1.
2. **XferNotReady arrives, but START_TRANSFER on ep1 fails or times out.** u9 = a patched usbdbg kernel that skips DEPSTARTCFG(2) on SET_CONFIGURATION. That is safe when resources are allocated statically, as they are with 4 endpoints.
3. **The TRB starts but never completes.** That points to DMA: run u8p (DART bypass).
