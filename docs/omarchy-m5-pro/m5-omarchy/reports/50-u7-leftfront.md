# 50: u6 NATIVE (left-back = DFU port), port map, u7 on the LEFT-FRONT port

## u6 (NATIVE, `reports/native-u6.txt`)
- **What hpm0 reported:**

  | Register | Value | Meaning |
  |---|---|---|
  | MODE (0x03) | `41 44 46 55` = **"ADFU"** | not "APP " |
  | STATUS | `1d 68 0c 20` | |
  | SYSTEM_POWER_STATE | 00 | |
  | POWER_STATUS | `83 0f` | |
  | BOOT_STATUS | `0a 10 13 20` | |

- **Conclusion:** the left-back port's controller is running its **DFU firmware**, with a host attached on Apple's DFU port, and it owns the USB2 pair. `SSPS` can't help there.
- **Fix:** use a port whose controller runs its application firmware.

## Port map (NATIVE ADT)
| Physical port (ADT `port-location`) | Port | USB-C controller | Controller | ATC / PMGR |
|---|---|---|---|---|
| **left-back** (by MagSafe), the DFU port | Port-USB-C@1 | hpm0, nub-spmi-a0, USID 0xC | usb-drd0 0x2a2280000 | ATC0 (0x280600208, 0x2883001{48,50,58}) |
| **left-front** | **Port-USB-C@2** | **hpm1, nub-spmi-a0, USID 0xA** | **usb-drd1 0x2aa280000** (IRQ 1451) | **ATC1**: common 0x280600210, usb_aon 0x288300160, usb 0x288300168, phymxwrap 0x288300170 |
| right | Port-USB-C@3 | hpm2, nub-spmi-a1 (0x28a1a8000), USID 0xC | usb-drd2 0x382280000 (die 1) | ATC2 (pmgr4/5 die-1 blocks) |

- **Left-front is the cheapest move.** It's on the same SPMI bus as hpm0, and DT nodes already exist for `dwc3_1` and its DARTs.
- **ATC1 addresses:**
  - atc-phy1: usb2phy 0x2aaa90000, usb2-digital 0x2aa800000
  - usb-drd1 pipehandler 0x2aaa84000
  - DARTs 0x2aaf00000 and 0x2aaf80000
  - Tunables identical to ATC0: USB2PHY_DFLT/DEV/HOST, PIPE_HANDLER_DEFAULT
  - ATC1_USB parents COMMON + USB_AON (t6050-pmgr.dtsi)

## u7 (built): ask the owner to move the cable to the LEFT-FRONT USB-C port
- **Modules:**
  - `m5_usb` gained `port=0|1` (sha256 `33c3f30a3b7dc831…`).
  - `m5_hpm` gained `usid=` and `op=auto` (sha256 `c5812264f2877302…`). op=auto reads the controller, then sends `SSPS` S0 **only if MODE == "APP " and SYSTEM_POWER_STATE != 0**, as PM pre-approved. Otherwise it logs and does nothing.
- **Flow:**
  1. Guard (marker `USB-U7`).
  2. `m5_hpm op=auto usid=0xa`: the hpm1 read-only dump, then the conditional SSPS.
  3. `m5_usb port=1`: state, then pon atc1_common/usb/phymxwrap (auto, then target, stopping if one doesn't reach f), then state, then dev (USBCTL = RUN), then dt_nopd (dwc3_1 and its DARTs).
  4. Bind dwc3 2aa280000.usb, then the NCM + ECM gadget, 10.55.0.1/10.55.1.1, sshd.
  5. dwc3 and PHY dumps, a soft_connect toggle at +2 min, and 10 minutes of state logging.
- **Push:** m5next/ = `build/usb-v1/m5next-u7/` (Image `6ca13193…`, initrd `1a459b5b…`, cmdline `e450bd5f…`). m5drop/ = `loop/u7/m5drop/`.
- **Host:** same as report 49 (10.55.0.2/24 on the NCM interface, `ssh alarm@10.55.0.1` with the work key). Expect `1d6b:0104 m5-omarchy`.
- **For the persistent drop-in (report 49):** switch it to `port=1`, `usid=0xa`, the atc1 domains and 2aa280000 once u7 works.
