# Platform port: SMC, battery, sensors, lid and power button, RTC (2026-11-06)

The new priority is a usable laptop. We reuse the J714c platform work posted in [omacom/linux-aurora#293](https://github.com/omacom/linux-aurora/issues/293) and check every value against our own J714s ADT. Nothing on this page has been tested natively yet unless it is labelled NATIVE.

## Upstream commits (edimoldovan/linux-aurora)

| commit | what | here |
|---|---|---|
| `4602eba4b9d2` | T6050 SMC + nub-spmi0 / PMIC NVMEM DT (from betizzel/omarchy-m5, with the rolotrealanis98 m5pro-linux window fix) | ported into a built-in DT overlay; values match our ADT (nub-spmi0 `0x28a014000`, gen 4; PMIC USID 0xe; clock offset `0x2100`/6; SMC SRAM `0x28de00000`/`0x140000`) |
| `68d2fe0a8e7f` | macsmc-power: initialise work items before the notifier | applied |
| `0bc84cc4a6b2` | battery and charger config | applied |
| `c5b0600d19a4` | SMC sensors (hwmon), F0md/F1md fan-mode keys | ported into the overlay |
| `0fbd859e287d` | RTKit T6050 AP power ACK wait | not needed: our RTKit already waits for the ACK |

## How it reaches the running system
Our boot object builds the live device tree, so editing a board `.dts` would change nothing. The existing built-in SMC node creator gets a new mode, `m5_smc=2`, which applies a built-in overlay: the SMC with sensor and RTC children, the SPMI controller and the PMIC NVMEM. `m5_smc=1` keeps the current behaviour, so rollback is a cmdline change.

## Safety rules kept
- SMC key writes stay denied, apart from the two existing trackpad-reset payloads within their per-boot budget. Battery charge-control writes are refused.
- The PMIC NVMEM is read-only, so the RTC cannot write the PMIC.
- No SMC reboot child. No SMC GPIO child (it has no user, and its read path would need SMC writes).
- Lid and power-button events need one SMC notification-enable write. That write is off by default and awaits the owner's decision.
- The first platform boot ignores lid, power-key and idle actions and refuses all system sleep. That stays until our USB-gadget access is shown to survive resume.

## First practical step: battery readout (NATIVE, negative)
On the FT19 kernel, with no new kernel, after an independent review: the unmodified upstream `macsmc-power` battery/AC driver was loaded as a module, together with a small module registering its standard child device under the existing SMC. Its charge-control writes are refused by our SMC write gate.

**Result: Linux hard-hung, and the SoC watchdog reset the Mac back into macOS.** No SMC write could reach the SMC. Which step stalled is unproven; this matches the third-party J716s report of a probe hang.

Next: a per-key diagnostic that logs each key's metadata before querying it, so a stall names its key. The combined SMC + display build is ready but held: it contains the same driver, and its other children use the same SMC calls.

## Source published (2026-11-06; built and reviewed, not yet tested natively)
- [`patches/2026-11-06/platform-r2/`](patches/2026-11-06/platform-r2/): the combined platform build. Display (eDP connector) and firewall kernel support are included. The SMC children are compiled in but **all off**, and the battery driver is **removed**.
- [`patches/2026-11-06/ft21-reset-fresh/`](patches/2026-11-06/ft21-reset-fresh/): a separate trackpad-only experiment (host AFE reset after the firmware's own reset request, then a fresh image and power-ON).

Both are queued with the operator: platform first, then the trackpad experiment. Results will be added here only from native runs.
