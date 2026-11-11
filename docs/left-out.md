# Left out on purpose

Everything we know of that someone has working on an M5 Mac but that is **not** in our image,
with the reason and what would bring it back. The 30-minute watch
([`tools/watch/watch.sh`](../tools/watch/watch.sh)) checks the "recheck when" column.

| What | Whose | Why it's not in | Recheck when |
| --- | --- | --- | --- |
| Switching the kernel to aurora-silicon's `integration/aurora` + the Aura bootloader (USB4, external displays, SD reader, PMP, SEP, memory-speed fix) | DjDeveloperr, erikwb, aurora-silicon | Aura hands over the GPU and display only on the macOS 27.0 firmware; every J714s we know runs 27.3 beta 1 (needed for all cores). On 27.3 we'd lose the GPU and the full display. Tested on TripleU613's J714s 2026-11-11: boots, Wi-Fi ok, no GPU/DCP/SEP. | aurora-silicon/linux #1173 (GPU on 27.2/27.3) and #1174 (DCP on 27.3) merge, or Aura gains a 27.3 handoff |
| USB4 / Thunderbolt and external displays | DjDeveloperr (#1515), erikwb | Needs the aurora-silicon base above | With the base switch |
| SD card reader | DjDeveloperr (#1570) | Needs upstream's kernel-trained PCIe port 1 (#1182); open PR, no card read yet | #1570 merges and the base switch |
| CLPC DRAM floor after idle (memory latency 300 → 110 ns) | DjDeveloperr (#1555, #1556) | Needs upstream's T6050 CLPC driver (#1324); ours has none | With the base switch |
| Speakers through the AOP (upstream's own audio stack) | DjDeveloperr (#1521, #1554), mic #1557 | Not audible yet by the author's own report; our gathered J716s-style audio already plays | #1554 reports audible playback |
| Keyboard backlight off when idle | danielfernau (omacom/omarchy #12558), IronsideXXVI (#18177) | Patches the Omarchy package itself; the image ships stock Omarchy | Either PR merges into omacom/omarchy |
| Deep sleep (suspend-to-RAM) | IronsideXXVI (J604, M4) | Not working on his own Mac yet; lid sleep (s2idle) already works here | He reports a completed s2r cycle |
| P-cluster drop to the slowest state when all cores idle | IronsideXXVI (J604 0223/0224/0228) | On the J714s's default schedutil governor idle clusters already sit at their minimum (measured 1.3 GHz); only matters under the performance governor | If we make "performance" a default |
| N1 shutdown park (no ASPM, hold the port on restart) | edimoldovan (linux-aurora ab24d156868e) | Fixes aurora's adopt path; our kernel trains the N1 differently and has rebooted cleanly all day | Restart hangs show up here |
| Per-unit GPU bins (FatBoy721's unit) | FatBoy721 (PR #5 0014) | The image reads every unit's bins from its own ADT now | Never (superseded) |
| Light sensor calibration in the image | aurora-silicon installer | Per machine and only in macOS; [`tools/als-calibration/save-als-cal.py`](../tools/als-calibration/save-als-cal.py) saves it | An installer path that runs on macOS for the J714s |
| A USB 3 device on port 1 | edimoldovan (in the image) | Port 1's SuperSpeed host comes up on TripleU613's J714s (its PHY firmware boots, SuperSpeed root hub registers), but the PC recovery cable lives on that port, so no USB 3 device has been tried | Someone plugs a USB 3 device into the left-front port |
| USB-C network gadget on port 1 | this repo | Port 1 is a USB host now (all three ports host); the image doesn't need the gadget, the dev Linux keeps it | If someone needs the cable network back |
| SMC key inventory (debug) | satchlj (t6050-smc-key-inventory) | A debugging aid, no user feature | — |
| Haptic actuator without hidraw | DjDeveloperr (#1576) | Our kernel has `CONFIG_HIDRAW=y`; the actuator binds | — |
