# 48: USB2 routing through the left-back port's controller (hpm0): research, read-only u5, proposed SSPS (u6)

## The observation
- **What the work host saw:** under u4, the SoC side was right. dwc3 RUN was set (DCTL 0x80f00000), DSTS 0x008e0001, and USBCTL = RUN. Yet the host kept `05ac:f014 Apple Device (Port DFU Mode)` enumerated as the **same device** (bus 003, dev 007) for hours, across every Linux boot.
- **What that means:** the port's USB2 pair is connected to the USB-C port controller's own DFU device, not to dwc3.

## Facts (NATIVE ADT; REPORTED where marked)
- **The controller.** usb-drd0's port is `nub-spmi-a0@8A188000/…/hpm0@C/…/Port-USB-C@1`, `port-location` "left-back". hpm0 properties:
  - `compatible "usbc,sn201202x,spmi"`, `reg[0] = 0xc` (SPMI USID 12), `port-number 1`
  - `interrupts <0x0b 0x11 0x13>` on the nub-spmi-a0 interrupt controller
  - `hpm-class-type 10`, `transports-supported 1..5`
- **The bus.** `nub-spmi-a0`: `compatible "aapl,spmi"`, gen 4, reg[0] 0x28a188000 (+0x4000). It is also an interrupt controller.
- **No DT node.** None of our T6050 DTs has a node for this bus or for any HPM, so Linux never talks to hpm0.
- **aurora (REPORTED; GPL source read):**
  - `j716c/t6050-dt t6050-die0.dtsi`: `nub_spmi_a0: spmi@28a188000 { compatible = "apple,t6050-spmi", "apple,t8142-spmi"; reg = <0x2 0x8a188000 0x0 0x4000>; }`. Its comment: the HPMs "are polled (no interrupts)".
  - `t6050-j775d.dts`: `hpm0: usb-pd@c { compatible = "apple,sn201202x"; reg = <0xc SPMI_USID>; }`. On that Mac Studio, hpm0 is left **disabled** because "rear port 1 carries the DFU cable … a probe wakes the controller and sets its power state even when polled".
  - Integration `drivers/usb/typec/tipd/spmi.c` adds polled select and a WAKEUP poll (`sn201202x_wake_poll`).
- **Our tree** (`src/linux-asahi-wip72`):
  - `drivers/usb/typec/tipd/spmi.c` has sn201202x, but only with interrupts.
  - `core.c` probe calls `cd321x_switch_power_state(tps, TPS_SYSTEM_POWER_STATE_S0)`. That is the `SSPS` command (DATA1 0x09 := 0x00, CMD1 0x08 := "SSPS") if SYSTEM_POWER_STATE (0x20) isn't already S0.
  - `CONFIG_TYPEC` is off in usb-v1.
  - `drivers/spmi/spmi-apple-controller.c` (`apple,t6050-spmi` = gen 4) writes nothing at probe when no IRQ is given.
- **HYPOTHESIS, the key one:**
  - The ACE3 runs its own DFU personality on the port's USB2 pair while the system power state it was told is not S0.
  - macOS and m1n1 move it to S0 (`SSPS`), and that switches the pair to the SoC. That would explain why betizzel's gadget worked after m1n1: m1n1 talks to the HPMs, even though their note says it "skips the PD controllers"; I can't tell what m1n1 does, and I don't read m1n1.
  - Aurora's "a probe … sets its power state" fits this.
- **Not the cause:** the eUSB2 repeater and CC role. The pair never reaches the SoC in the first place.

## u5 (read-only, built)
- **Module `tools/loop/hpm-mod/m5_hpm.c`** (GPL; sha256 `6e0c855e166990db…`, vermagic 7.2.2-m5slim+). It runs in two parts.
- **Live-DT part:** creates `/soc/spmi@28a188000` (`apple,t6050-spmi`, reg as aurora's, no IRQ) with child `usb-pd@c` (`m5,hpm-ro`, USID 0xc), then creates the controller device.
- **Its own spmi driver** reads VID, MODE (expect "APP "), CMD1, STATUS, SYSTEM_POWER_STATE, BOOT_STATUS, POWER_STATUS and DATA_STATUS. It uses the tipd SPMI read protocol:
  - select = SPMI register-zero write of the register number;
  - poll reg 0 until it echoes the number;
  - size at 0x1f, data at extended 0x20.
- **Writes:** the selects only. **No WAKEUP and no command.** If the ACE3 is asleep, aurora says it returns zeros. That gets logged; it is not woken.
- **The decisive value:** SYSTEM_POWER_STATE. 0x00 = S0, 0x03/0x04/0x05 = S3/S4/S5. DATA_STATUS tells whether a data connection is reported.
- **Push:** m5next/ = `build/usb-v1/m5next-u5/` (usb-v1 Image `6ca13193…`, initrd `1a459b5b…`, cmdline `5a39a012…` marker USB-U5). m5drop/ = `loop/u5/m5drop/`.

## Proposed write, for PM approval (u6, built but NOT to be pushed until approved)
- **The `SSPS` S0 command to hpm0,** exactly the in-tree tipd probe's `cd321x_switch_power_state`:
  1. If CMD1 isn't idle, stop.
  2. DATA1 (0x09) := `00`.
  3. CMD1 (0x08) := `"SSPS"`.
  4. Poll CMD1 until 0 (at most 1 s).
  5. Read DATA1 (the result), SYSTEM_POWER_STATE and DATA_STATUS.
- **Two bus writes,** both to the USB-C port controller over SPMI. That is not PMGR, SMC or audio, but it is a new device class: a Type-C/PD controller with charging authority. Hence the approval.
- **Optional `wake=1`** (an SPMI WAKEUP first) only if u5 shows zeros because the controller is asleep.
- **Then u6 continues with the u4 flow:** ATC0 pon, PHY with USBCTL = RUN, dwc3, gadget and sshd.
- **Expected on the host:** `05ac:f014` disconnects, then `1d6b:0104 m5-omarchy` appears.
- **Risk:** the controller also manages charging and the DFU and debug paths. Changing its power state could change what it negotiates on that port. Under macOS it is in S0 all the time, so S0 is its normal running state.
- **Push (after approval):** m5next/ = `build/usb-v1/m5next-u6/` (cmdline `0be3b130…`, marker USB-U6). m5drop/ = `loop/u6/m5drop/`.
