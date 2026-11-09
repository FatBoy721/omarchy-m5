# 47: u3 NATIVE analysis: power works; the PHY was left in ISOLATION; u4

## u3 (NATIVE, `reports/native-u3.txt`, 07:30)
- **Power.** One domain at a time, with no hang:

  | Domain | Before | Writes | Result |
  |---|---|---|---|
  | atc0_common | 0x300 | → 0x0 → 0xf | 0x3ff |
  | atc0_usb | 0x244 | → 0x44 → 0x4f | 0x2ff |
  | atc0_phymxwrap | 0x300 | → 0x0 → 0xf | 0x3ff |

  Each reached actual f on the first sample.
  - So the u2c hang came from the kernel-driver/genpd path, not from a write to these four words. Clearing AUTO first and taking parents first is enough. PMP notification wasn't needed (betizzel REPORTED, now NATIVE).
- **PHY writes, all logged:**
  - DFLT and DEV tunables (+0x8 → 0x01c00007, +0x18 → 0x00230113).
  - CTL 0xb → 0x3 → 0x2 → 0x0 → 0x4. That is SIDDQ off, RESET off, PORT_RESET off, then APB_RESET_N on.
  - usb2-digital → 0x9.
  - MISCTUNE gates off (0x608c0813 → 0x008c0813).
  - SIG → 0x01c1000f, which reads back **0x01c0000f** (bit 16 doesn't stick).
  - PIPE mux already 0x42 (dummy).
  - PIPE tunable +0x44 0x30 → 0x34.
  - AON_GEN DWC3_RESET_N → 1.
- **Controller and gadget:** apple-dart bound both DARTs, dwc3 bound, UDC `2a2280000.usb` appeared, and the gadget was bound (rc 0). But the UDC state stayed `not attached` for 4 minutes and usb0 stayed down.

## Root cause candidate #1: USBCTL was never set to RUN
- **`usb2phy+0x00` (USBCTL) = 0x00000004 before and after op=dev.** m5_usb's `usbctl=` defaulted to −1, meaning "leave it alone".
- **Asahi's in-tree `drivers/phy/apple/atc.c` (our src/linux-asahi-wip72, GPL) defines `USB2PHY_USBCTL_RUN 2` and `USB2PHY_USBCTL_ISOLATION 4`.**
  - Its power-down writes ISOLATION ("this clears USB2PHY_USBCTL_RUN").
  - Its power-on ends with `writel(USB2PHY_USBCTL_RUN, …USBCTL)`. It does that for both roles; host vs device is chosen by `USB2PHY_SIG_HOST` (bits 14:12).
- **aurora agrees.** The T6050 `apple_t6050_usb2_stop` sets mode 4, and the T6050 host sequence ends with mode 2.
- **So the eUSB2 PHY stayed isolated, and no D+ pull-up could reach the line.** That fits `not attached` exactly.
- **Fix:** op=dev now writes USBCTL = 2 by default (`usbctl=` still overrides). The SIG host bits stay 0, which is device mode.

## The four PM questions
1. **Which physical port.** The ADT gives `usb-drd0` → `usb-drd0-port-hs` UsbIOPort … `nub-spmi-a0/hpm0@C/…/Port-USB-C@1`, and hpm0's `port-location` = **"left-back"**.
   - The other ports: hpm1 `Port-USB-C@2` = "left-front" (usb-drd1), and hpm2 `Port-USB-C@3` = "right" (usb-drd2).
   - **So ATC0/usb-drd0 is the left-rear port, the one next to MagSafe.**
   - Apple's DFU instructions name the left port nearest MagSafe as the DFU port on 14-inch MacBook Pros (REPORTED, from memory of Apple's support doc; not checked here). That would make the cable already in the right port. The `05ac:f014` seen under macOS fits this.
2. **The eUSB2 repeater.**
   - `usb-drd0` has `usb-repeater` = bytes "wacm",3 (an opaque reference, not decoded) and `Usb2Repeater = Yes`.
   - aurora notes that on T6040 the PD controller resets the repeater on each connect. I found no repeater register map in aurora's public T6050 code.
   - betizzel's m1n1 gadget worked without touching the repeater (REPORTED).
   - **Not pursued until USBCTL = RUN has been tested.**
3. **Soft-connect.** u4 dumps DCTL (RUN_STOP), DSTS (link state, speed), DCFG, DEVTEN, GCTL, GSTS, GUSB2PHYCFG and GUSB3PIPECTL, plus the PHY and PIPE registers:
   - after the gadget bind;
   - at +1 min and +2 min;
   - at +2 min it also toggles `/sys/class/udc/2a2280000.usb/soft_connect` (disconnect, then connect).
4. **Type-C role.**
   - With no PD driver, hpm0's sn201202x keeps its autonomous firmware policy. VBUS from the work host still reaches the Mac (it charges under macOS) and the CC lines are the controller's.
   - We force VBUS-valid in the PHY (SIG bits 3:0 = 0xf), so the PHY doesn't depend on VBUS detection.
   - betizzel: their gadget worked with the PD controllers skipped (REPORTED).
   - aurora's T6050 tipd SPMI work (branch `t6050/typec-events`, 542659c0e5) is the reference if role switching turns out to matter.

## u4 (built)
- **m5next/** = `build/usb-v1/m5next-u4/`: Image `6ca13193…`, initrd `1a459b5b…`, cmdline `bbaa7011…` (marker `USB-U4`, `m5_pmgr_allow=ans`).
- **m5drop/** = `loop/u4/m5drop/`: the u3 flow, with op=dev writing USBCTL = RUN, plus the dumps and soft_connect toggle above. m5_usb.ko `7251980994b29dd1…`.
- **Host check:** `lsusb` shows a new `1d6b:0104` "m5-omarchy" device. Then give the NCM interface 10.55.0.2/24 and run `ssh alarm@10.55.0.1`.
