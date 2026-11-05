# 65 — h2 STATUS decode; h4 (wait for the Type-C partner, read-only config dump)

## h2 (NATIVE, `reports/native-h2.txt`)
- **The hpm1 bring-up worked:** wake_poll got an answer after 1 try, MODE `APP `, and `SSPS` S0 succeeded (SYSTEM_POWER_STATE 0x07 → 0x00 in 10 ms).
- **Partner side:** xHCI registered buses 1 and 2. The phone never appeared.
- **STATUS decode,** against aurora tipd `tps6598x.h` @1edf9d01:

| | raw (LE) | bit0 plug | CONN_STATE[3:1] | bit5 power role | bit6 data role | bit28 | VBUS[21:20] |
|---|---|---|---|---|---|---|---|
| before SSPS | `00 00 00 10` = 0x10000000 | 0 | 0 NO_CONN | sink | UFP | HIGH_VOLTAGE_WARNING | 0 (vSafe0V) |
| **after SSPS** | `09 00 00 10` = 0x10000009 | **1** | **4 = NO_CONN_R_A** | sink | UFP | 1 | 0 |

- **What this means (HYPOTHESIS):**
  - In S7 (the SoC "off") the port state machine was **disabled**: no plug was seen at all.
  - S0 **enabled** it, and it now sees a plug, but only **Ra**: a cable or VCONN pull-down, with no Rd/Rp resolved. So it is **not connected** in the Type-C sense. It has no role yet and does not source VBUS, so the phone sees nothing.
  - h2 read STATUS only about 10 ms after SSPS. Type-C attach takes about 100–200 ms (tCCDebounce), so the partner may simply not have been resolved yet.
  - The other possibility: two DRPs, both in Try.SNK (the phone toggling and the Mac's port configured sink-preferred), may never settle into the Mac as source.
- **POWER_STATUS 0 and DATA_STATUS 0:** no contract and no data connection, consistent with the above.
- **`dt create … -22` and the second probe:** `of_changeset_apply` already populated the spmi bus through `of_platform_notify`. Our explicit `of_platform_device_create` then made a duplicate (`spmi@28a188000#1`), and the spmi child probed a second time. That was harmless in h2, where the second pass saw S0 and did nothing. **It would send SWSr/SWDF twice in h3.** Fixed in h4: the module skips the create when the node is `OF_POPULATED`.
- **h3 (running):** it re-reads STATUS 200 ms after SSPS. If the partner is still Ra-only, SWSr/SWDF are PD role swaps that need a connection, and they will most likely fail with a non-zero DATA1 result.

## h4 (built): give the state machine time, and dump the port config read-only
- **`m5_hpm op=srcdfp`** (`f5f74119…`): wake, then SSPS S0 (as in h2), then:
  1. **Read-only dump** of INT_EVENT1 (0x14), GLOBAL_SYSTEM_CONFIG (0x27), PORT_CONFIG (0x28), PORT_CONTROL (0x29), and TX/RX source caps (0x30/0x32). PORT_CONFIG holds the Type-C state-machine setting (sink / source / DRP, Try.SRC/SNK), which tells us whether the Mac's firmware keeps this port sink-only in our state.
  2. **Poll STATUS every 100 ms for up to 4 s.** Every change is logged with conn_state and VBUS. It stops as soon as conn_state ≥ 6 (CONN_NO_R_A / CONN_WITH_R_A).
  3. **SWSr / SWDF only when connected** (as h3, pre-approved). Otherwise it logs `partner NOT resolved after 4 s: no role swap`.
- **The double-probe fix** (above).
- **Set:**
  - m5next/ = `build/usb-v1/m5next-h4/`: Image `ca23e30b…`, initrd `028ea256…`, cmdline `67eacd45…` with marker `USB-H4`, the 3-minute guard and the same disarm rule;
  - **no m5drop**.
- **For the owner:** if possible, run once with the phone's USB mode set to **"USB tethering" before plugging in**, and once after replugging. Some phones only present Rd (sink) when they are charging-only.

## Next, depending on h4's PORT_CONFIG and STATUS trace
- **PORT_CONFIG shows sink-only or Try.SNK:** write PORT_CONFIG to DRP/Try.SRC (a register write, so it needs approval), or use the 4CC `SRYR`/swap after attach.
- **conn_state reaches 6/7 but VBUS stays 0:** SWSr + `SRDY`-style source enable (needs approval).
- **conn_state stays 4:** the cable/phone end isn't presenting Rd. Try a different C-to-C cable, or a USB-A adapter with a standard Rd.

Labels: the decode is NATIVE data; the interpretation is HYPOTHESIS; h4 is built, not run.

## Addendum (task 66, PM 11:59): h4 rebuilt as an h3 loop
- **h3 (NATIVE, owner):** the phone briefly showed its USB options and tethering could be selected, then it dropped. After a replug there was nothing, because the role swap is volatile per attach. This is the first sign that SWSr/SWDF makes hpm1 source and host.
- **h4, as now built:**
  - `m5_hpm op=read wake=1 persist=1` (`857ee558…`): wake plus a read-only dump. The module **stays loaded**.
  - `/sys/module/m5_hpm/parameters/kick` runs one **pass**: wake if asleep → SSPS S0 if not S0 → SWSr if sink → SWDF if UFP → STATUS, logged as `m5hpm: pass done: sps … STATUS[0] … conn_state …`.
  - **The /init loop:** every 2 s, if **no device** exists under `/sys/bus/usb/devices/[0-9]-[1-9]*` (root hubs and their interfaces don't count), it kicks a pass and logs `hpm1 pass N: …`. Once a device enumerates, it logs the product name and **pauses**; it **resumes** if the device disappears.
  - The 4 s wait / swap-only-when-connected logic from the first h4 draft is no longer used (that is the `op=srcdfp` path, not called).
  - Fixed: the duplicate spmi probe.
  - The rest is unchanged: tethering drivers, DHCP with the 10.66.0.2 fallback, dial-out to 10.168.168.151:2222, the keyboard shell, the 3-minute guard (disarmed by a keyboard or a live SSH session), m5-kexec.
- **Set:** `build/usb-v1/m5next-h4/`: Image `ca23e30b…`, initrd `99d65a76…`, cmdline `67eacd45…` with marker `USB-H4`. No m5drop.
