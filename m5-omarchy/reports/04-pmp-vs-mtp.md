# 04 — PMP vs MTP static diff (J714s)

Source: `reports/04-j714s-full.txt` (our scrubbed dump, macOS 26.6.2, mBoot-18000.161.10). **No m1n1 code or m1n1-derived code was used** (PM decision, CLAUDE.md rule 7). Questions that need m1n1 are listed for the owner at the end. Physical addresses come from macOS's own `IODeviceMemory` property, so no address-translation code was involved. **[guess]** marks inference.

## 1. `pmp0` vs `mtp`

| | `pmp0@84E00000` | `mtp@94600000` |
|---|---|---|
| compatible / role / device_type | `iop,ascwrap-v6` / `PMP0` / `pmp` | `iop,ascwrap-v6` / `MTP` / `mtp` |
| reg[0] (wrapper) | **0x2_84E0_0000**, 0x88000 | **0x2_9460_0000**, 0x88000 |
| reg[1] | 0x2_8485_0000, 0x4000 | 0x2_9405_0000, 0x4000 |
| reg[2] | 0x2_8450_0000, 1 MiB (firmware region; nub `region-base` = 0x2_8450_0000) | — |
| reg[3] | 0x2_8425_0000, 0x4000 (`ptd-update-reg-index` = 3) | — |
| **clock-gates / power-gates** | **`<0x1b 0x1c>` / `<0x1b 0x1c>`** | **empty / empty** |
| sram-index | 1 | — |
| segment-names | `__TEXT;__DATA` | `__TEXT;__DATA;__OS_LOG` |
| IRQs | 0x18c–0x18f (4) | 0x2a4–0x2a7 (4) |
| nub `pre-loaded` | 1 | 1 |
| nub extras | `firmware-name` = `t6050pmp`, **`no-shutdown` = 1**, `ptd-range`, `pm-ptd-ranges`, `soc-device`, `soc-device-ps-group`, plus many `*-bw-*`/`*-lat-*` QoS tables and DVFS/thermal tables | `watchdog-enable`, `coredump-enable`, `cold-boot-after-hibernate`, `no-firmware-service` |
| DART | `dart-pmp0@841A0000`: regs 0x2_841A_0000 (0xc000), 0x2_841B_0000, 0x2_803F_8000. 16 SIDs, many `bypass-N`, two `l2-tt-*`, `dapf-instance-0`, `vm-base` 0x1_0000_0000. Mappers `mapper-pmp0` and `mapper-pmp0-ptd-fwd` | `dart-mtp@94800000`: regs 0x2_9480_0000, 0x2_9481_0000, 0x2_890F_C000. 1 SID, `dapf-instance-0`, `vm-base` 0x1_0000_4000. One mapper |

**Where `ASC_CPU_CONTROL` lives.** Aurora's own wrapper-v6 driver code (`drivers/soc/apple/mailbox.c` on `edimoldovan/linux-aurora:t6050-j714c`) defines `CPU_CONTROL` at wrapper + `0x44` and the mailbox at wrapper + `0x8000`. On ascwrap-v6 the wrapper is reg[0]. *Caveat: that code's ancestry is Asahi's Linux driver, not m1n1.*
- PMP: **0x2_84E0_0044**
- MTP: **0x2_9460_0044**, the register the kernel successfully writes to start MTP on T6050

**Verdict: the `+0x44` fault does not look like a wrong-address problem.** Both blocks have the same compatible, the same reg[0] size and the same reg[0]/reg[1] pattern, and the same offset works on MTP. The one structural difference is that **PMP is behind PMGR clock/power gates 0x1b and 0x1c, and MTP has none.** [guess] One of those gates is off (or held by firmware) when a raw loader runs, so the wrapper faults on access. That would fit edimoldovan's report that `ps_pmp` reads "on" while `+0x44` still faults: `ps_pmp` may be only one of the two gates. The other leading explanation is an access lock that iBoot sets for raw boot objects (the per-core `cpu-impl-reg` window also faults).

## 2. `pmgr`
- `pmgr@80600000` has only one `function-*` property: **`function-toggle_vdd_cio`**. There is **no `function-pmp_control`**, which confirms edimoldovan's T6050 vs T8142 observation on our machine. (I didn't verify T8142's side myself.)
- The macOS driver is `AppleT6050PMGR` (`com.apple.driver.AppleT6050PMGR`, matched on `pmgr1,t6050`). Its children are `soc-tuner` (`AppleT6050SOCTuner`), `clpc` (`AppleCLPC`, bundle `AppleT6050CLPC`), `ppm` (`ApplePassthroughPPM`) and `pmgrtools`.
- **The list of `notify_pmp` domains is not produced.** The flag lives inside the binary `devices` table. The only decoder we know of is m1n1's (and copies of it), so this is an open question (Q1).

## 3. IOService: macOS drivers (names only)
- **PMP:** `pmp0` → `AppleASCWrapV6` (`com.apple.driver.AppleA7IOP-ASCWrap-v6`) → `iop-pmp0-nub` → `RTBuddy(PMP0)` (`com.apple.driver.RTBuddy`) → `RTBuddyService` → **`ApplePMPFirmware`** (`com.apple.driver.ApplePMPFirmware`). Also under the RTBuddy: `RTBuddyIOReportingEndpoint`, `RTBuddyCoreAnalyticsEndpoint`, and **`PMP0Endpoint1`** → **`ApplePMPv2`** (`com.apple.driver.ApplePMP`, matched on `PMP0Endpoint1`).
- **MTP:** `mtp@94600000` → the same `AppleASCWrapV6` → `RTBuddy(MTP)`, with `RTBuddyIOReportingEndpoint`, `RTBuddyTraceKitEndpoint` and `RTBuddyService`. HID goes over `dockchannel-mtp` (`AppleDockChannelDevice`, `AppleHIDTransportInterface`).
- **GPU:** `sgx@0` → **`AGXAcceleratorG17X`** (`com.apple.AGXG17X`, matched on `gpu,t6050`). `gfx-asc` and `gfx1-asc` each carry `RTBuddy(GFX)`/`RTBuddy(GFX1)` → `AGXFirmwareKextG17RTBuddy`, with endpoints `GFXEndpoint1/2` and `GFX1Endpoint1/2`.
- **CPUs:** `cpu*` (`IOPlatformDevice`) → `AppleARMCPU` ×15. There is also `cpu-debug-interface` and `dbgCPU@88B00000`.
- **Takeaway:** macOS drives PMP through the *same* generic wrapper and RTKit stack as MTP, plus a PMP firmware loader (`ApplePMPFirmware`) and a protocol driver (`ApplePMPv2`) on endpoint service 1. [guess] So macOS starts the PMP through the same wrapper path, and the fault reflects platform state (clocks, gates or locks), not a different register interface.

## 4. Ladder step 2 probes
**These probes run through the m1n1 proxy, so under rule 7 the owner writes and runs them by hand. I only supply addresses.** Each one is a single 32-bit read. No bulk reads (a 16 KiB PTD read crashed the proxy on J714c) and no writes. Power-cycle between groups if anything faults.

| # | Address | Why | Expected / meaning |
|---|---|---|---|
| 1 | `0x2_9460_0044` (MTP CPU_CONTROL) | Control: same register on a known-good block | Reads fine → the access method is OK |
| 2 | `0x2_84E0_0044` (PMP CPU_CONTROL) | Reproduce edimoldovan's fault on J714s | Fault = same wall; a value = J714s differs from J714c |
| 3 | `0x2_84E0_0000` (PMP wrapper +0) | Whole wrapper or one register? | Fault → the whole block is gated/locked |
| 4 | `0x2_84E0_8110` (PMP mailbox A2I control, wrapper+0x8000+0x110) | Is the mailbox reachable while CPU_CONTROL isn't? | A value with 2/3 faulting → a selective lock; all fault → gate/clock |
| 5 | `0x2_8485_0000` vs `0x2_9405_0000` (reg[1] +0) | The second wrapper region on both | Same pattern as 1/2 |
| 6 | `0x2_841A_0000` vs `0x2_9480_0000` (DART +0) | Is PMP's DART reachable? | DART reachable but wrapper not → gating specific to the ASC |
| 7 | `0x2_8450_0000` (PMP firmware region +0) | The firmware is present (J714c saw it loaded) | Non-zero → iBoot pre-loaded it, matching `pre-loaded`=1 |
| 8 | PMGR power-state registers for devices **0x1b** and **0x1c** | Test the gate hypothesis | Addresses unknown to us: needs Q1 |
| 9 | `0x2_8424_0010` (PMP-STATUS, per edimoldovan's J714c table; PTD base = reg[3] − 0x10000 = 0x2_8424_0000) | Is PMP running? | 0 = not running. Owner should confirm the offset (Q2) |

**Decision rule:** if 1 works, 2–4 fault and 6 works, run the gate test next. The owner turns on PMGR devices 0x1b/0x1c and then re-reads 2. That step is a **write**, so it needs PM approval as its own step.

## Open questions for the owner (need m1n1 or m1n1-derived tools)
1. **Q1:** decode `/arm-io/pmgr` `devices`. Find the names and PS-register addresses of devices **0x1b** and **0x1c** (PMP's gates), and list every device with `notify_pmp`. Is `ps_pmp` one of 0x1b/0x1c?
2. **Q2:** decode `iop-pmp0-nub` `ptd-range` / `pm-ptd-ranges` / `soc-device` for J714s, and check it against edimoldovan's J714c table (PMP-STATUS at PTD+0x10).
3. **Q3:** run probes 1–9 above via the proxy and record the raw results by hand.
4. **Q4:** does T8142 (base M5) PMP have clock/power gates, and does it have `function-pmp_control`? Someone with a T8142 ADT can compare.

## Provenance notes
- Aurora's `mailbox.c`/`rtkit-helper.c` descend from Asahi's Linux drivers, not m1n1. The probe offsets (+0x44, +0x8000) come from there.
- The PTD layout in #293 was produced with Aura's `pmp_assist.py`, which is m1n1-derived. I've only cited edimoldovan's published *result* (PMP-STATUS at +0x10) and flagged it for the owner to confirm. I didn't use the tool or its decoding logic.
