# 44: u2 (NATIVE) analysis and the u2 rev 2 fix

**NATIVE u2** (`reports/native-u2.txt`, 06:43):
- **Power state at hand-off** (same as u0):

  | Domain | Reads | State |
  |---|---|---|
  | atc0_common | 0x300 | off |
  | atc0_usb_aon | 0x2ff | on |
  | atc0_usb | 0x244 | clock-gated (target and actual 4) |
  | atc0_phymxwrap | 0x300 | off |
  | atc0_common_dp_0..3 | 0x244 | clock-gated |

  This **confirms** betizzel's guess (REPORTED): ATC0 is not up at iBoot hand-off, which matches the column for ATC3, the port m1n1 leaves untouched.
- **`dt changeset (power) apply: -22` was a build failure, not an apply failure.**
  - The log shows four status lines and the dart_0 power-domains line, then nothing for dart_1.
  - So `set_pd(dart_1, atc0_phymxwrap)` returned -EINVAL and the changeset was never applied. No node was enabled and nothing was powered.
  - Cause (HYPOTHESIS, consistent with the code path): `ps_atc0_phymxwrap` has **no phandle** in the live FDT, because dtc drops phandles nothing references, and my `set_pd()` rejected a phandle of 0.
- **The dwc3 changeset applied (0), but dwc3's power domain never got a provider,** so it hit the deferred-probe timeout (-110).

## Fix (u2 rev 2; same m5next/ kexec set, new m5drop)
- **Phandle:** `set_pd()` gives a phandle-less domain node an in-memory phandle (largest existing + 1) before pointing power-domains at it.
- **Build vs apply:** a changeset build error is now logged separately from the apply result.
- **Device creation:** after a successful apply, for each of the four pwrstate nodes, both DARTs and dwc3, the module logs whether a platform device exists and which driver it has. If the OF reconfig notifier didn't create a device (parent not a populated bus), it calls `of_platform_device_create()`.
- **dwc3 rebind:** after `dt_dwc3`, the script logs the DART and dwc3 driver links. If dwc3 is unbound (a deferred-probe timeout leaves it unbound), it writes `2a2280000.usb` to `/sys/bus/platform/drivers/dwc3/bind`.
- **Unchanged:** the gadget, network and sshd steps.

**Why not the chain/dtb2 route:** it needs the merge tool and the chain layout from another project's tree (`~/m5-n1`, `~/m5-build`). The runtime fix is a module plus script change pushed through the same proven m5next/ set. If rev 2 still can't power the chain, the chain route is next. U2's delta is fully described in `tools/kernel/dts/t6050-j714s-m5-U2.dtsi`, and the merge would apply it to `m5log/live-fdt.dtb`.

## Push
- **m5next/:** `build/usb-v1/m5next-u2/`, unchanged. Image `6ca13193…`, cmdline `c1f8c4dd…` (allow-list ans + 4 × atc0).
- **m5drop/:** `loop/u2/m5drop/` (rev 2). m5_usb.ko sha256 `18a285adcd78708f…`.

**Watch for:**
- `had no phandle, assigned N`
- `dt changeset (power) apply: 0`
- `m5 pmgr:` power-on writes for exactly the four ATC0 domains
- a `ps` dump with all four main domains at actual f
- `op=dev` then running with its logged writes
- the dwc3 driver bound, `/sys/class/udc` listing `2a2280000.usb`, and the UDC `state`
