# 24 — Past the native SError: DT-only changes (VM build only; NATIVE pending)

**One-line summary:** disabled MTP, mtp_mbox, mtp_dart, mtp_dockchannel and mtp_hid, plus dwc3_1/dwc3_2 and their four DARTs. Kept dwc3_0 (the Port-USB-C@1 gadget) and **bound dwc3_0 and both of its DARTs to `ps_atc0_usb`**. They had no power-domains. NVMe/ANS, simpledrm and the earlycon are unchanged.

DTB: `build/linux-slim/arch/arm64/boot/dts/apple/t6050-j714s.dtb`, 66098 B, sha256 `ce5bd2907cdd700791949cb99f8e40bb3d583079d7cdd27037254d696b0bf1c6` (also in `~/m5boot/spec/inputs.md`). Kernel Image/Image.gz unchanged. Source: `tools/kernel/dts/t6050-j714s-m5.dtsi`, included last by t6050-j714s.dts via `tools/build-slim.sh`.

## Why the USB DART change too [HYPOTHESIS, evidence-based]
- The SError is **asynchronous**, so the PC (el1_abort) doesn't point at the culprit. The last completed probe was the MTP DART. With initcall_debug, "probe of X returned" prints only after a probe finishes, so **the next DART probing** when the SError arrived was most likely `dwc3_0_dart_0` @ **0x2a2f00000**.
- The panic registers hold **x0 = x21 = 0x2a2f0000**. That's exactly 0x2a2f00000 >> 4, possibly a shifted register/page value. Suggestive, not proof.
- ADT (`reports/04-j714s-full.txt`):
  - `dart-usb0` has `"clock-gates" = <0x245, 0x245>` (usb1: 0x248, usb2: 0x24b), so it sits behind a PMGR gate. Touching a gated-off block's registers gives an SError.
  - Our DT had **no `power-domains` on dwc3_0 or its DARTs**, so Linux never powered them, and `pd_ignore_unused` only stops domains from being turned *off*.
  - Asahi's t600x DTs bind the same nodes to `ps_atc0_usb`; I verified the label in the built DTB.
  - [Not verified] that PMGR id 0x245 is exactly ps_atc0_usb (reg 0x150). The mapping table isn't decoded here.
- So the MTP change alone might not get past the SError; the USB power-domain change targets the other candidate. If it **still** SErrors at the same place, the next step is to disable dwc3_0 + its DARTs too. That costs the gadget, but it tells the two apart in one boot.

## (2) Other DARTs and DAPF
| DART (ADT) | DT node | DAPF in ADT | clock-gates | Now |
|---|---|---|---|---|
| dart-mtp | mtp_dart | **yes** (`dapf-instance-0`, 5 entries) | none | disabled |
| dart-usb0 | dwc3_0_dart_0/1 | **no** | 0x245 | kept, + ps_atc0_usb |
| dart-usb1 / usb2 | dwc3_1/2 darts | no | 0x248 / 0x24b | disabled (not needed) |

- NVMe uses SART (not a DART) and already has `power-domains = <&ps_ans>`.
- The DT has no display/DCP/GPU/ISP DARTs.
- **The DAPF issue can't hit dwc3_0**: its ADT DART has no DAPF instance.

## (4) DAPF research note (start)
- **What:** DAPF ("DART address-port filter", the name used in Asahi's ADT property naming) is a per-DART table of physical address windows that the device behind the DART may access. The ADT carries it as `dapf-instance-0`. On dart-mtp it has 5 entries of 48 bytes each: `{u64 start, u64 end, 32 B flags/attrs}`. The first is 0x28830c000–0x28830c07f (MMIO windows near DockChannel/AOP), the next 0x288320900-ish… (decoded from the raw bytes, layout [HYPOTHESIS]).
- **Who programs it:** m1n1's kboot does, from the ADT, on chips that need it. That's REPORTED in the task brief; m1n1 code wasn't read (restricted).
- **Kernel (GPL, allowed):** `drivers/iommu/apple-dart.c` in our tree only knows the **`TCR_BYPASS_DAPF`** bits (`DART_T8020_TCR_BYPASS_DAPF` BIT(12), `DART_T8110_TCR_BYPASS_DAPF` BIT(2)). It has **no code to program DAPF windows** and no DT binding for them. Paths back to the keyboard without a bootloader change:
  - (a) set BYPASS_DAPF in the MTP DART's TCR for MTP streams [HYPOTHESIS: may be locked or ignored];
  - (b) a small kernel patch that reads a DT `apple,dapf` array (copied from the ADT `dapf-instance-0` by our DT generator) and writes it at probe. The register layout needed for (b) isn't in any allowed source I have; to be continued.
