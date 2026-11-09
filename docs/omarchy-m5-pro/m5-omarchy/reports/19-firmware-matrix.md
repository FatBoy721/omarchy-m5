# 19 — T6050 (M5 Pro/Max) native custom-boot-object reports vs firmware

**Answer: no.** No public source reports a raw fuOS boot on **mBoot-18000.161.x (macOS 26.6.x)**. Every reported working T6050 raw boot uses stage-2 firmware **18000.120.36 (26.5)** or **20457.x (macOS 27.0 → 27.3 beta 1)**. Our J714s is the only known data point on 18000.161.10, and it panics in iBoot after the `fuos` load even with a 192 KB image (NATIVE, reports 15/16). All rows below are **REPORTED** unless marked otherwise.

Key fact (REPORTED, rolotrealanis98): the firmware that loads and starts the raw object is the **stub's own stage-2 mBoot** (`/chosen/firmware-version`), cloned from the host macOS when the stub is created. It is not the machine-wide LLB (`system-firmware-version`), and a later macOS update does not change it. Our stub was cloned from 26.6.2 (report 08), so its stage 2 is 18000.161.10.

## Matrix
| Who / machine | Host macOS + firmware | Stub (stage 2) | Boot object (size) | Stub created by | Result | Source |
|---|---|---|---|---|---|---|
| **Us**, J714s Mac17,9 M5 Pro | 26.6.2, mBoot-18000.161.10 | 26.6.2 clone (18000.161.10) | m5boot 49.0 MB; m5boot-gz 18.9 MB; probe 192 KB | betizzel `prep-stub.sh` + `finish-install.sh` @15cd70c1 | **iBoot panic after `fuos` load ×3; NATIVE**. probe2 is armed and pending | reports 11/15/16/18 |
| betizzel, J714s Mac17,9 M5 Pro | 26.5 (25F71) | "OS and system firmware both report **mBoot-18000.120.36**" | patched m1n1 stage 1 v1.6.1-28-g4184923f (size not stated) | own `prep-stub.sh` (clone of host install) + `finish-install.sh` | boots iBoot → m1n1 → fb console, USB proxy | [#293 c6624146044](https://github.com/omacom/linux-aurora/issues/293#issuecomment-6624146044); omarchy-m5 `docs/smp-t6050-findings.md:4`, `docs/bringup.md:155` @15cd70c1 |
| edimoldovan, J714c Mac17,7 M5 Max | 27.0 (iBoot-20457.1.29), then 27.2 beta (**mBoot-20457.41.3**) | not stated (assumed host clone) | upstream m1n1 `v2.0.0-53-g7cde7d1a` raw, `--entry-point 2048` (size not stated) | not stated | boots, EL2 proxy, Linux 1 core; same result on both firmwares | [#293 c6614448292](https://github.com/omacom/linux-aurora/issues/293#issuecomment-6614448292); [installer#149](https://github.com/omacom/omarchy-mac-installer/issues/149); edimoldovan/kernel `CPU-START.md` ("Firmware re-test on mBoot-20457.41.3") |
| rolotrealanis98, J716s Mac17,8 M5 Pro 16" | 27.2 (mBoot-20457.41.2) → 27.3 beta 1 (26C5035r; LLB mBoot-20457.60.65.0.1) | 27.2 clone (20457.41.2); **recreated** on 27.3b1 → `firmware-version` mBoot-20457.60.65.0.1 | plain m1n1 stage 1 **0x4D0000 (4.8 MiB)** boots; CHAINLOADING builds at 0x4E0000–0x4F0000 loop ("macOS needs to be reinstalled") | betizzel `prep-stub.sh` + `finish-install.sh` (+ its own `refresh-stub-firmware.sh recreate`) | boots on both; **18-core SMP only with the 27.3b1 stub** | [m5pro-linux](https://github.com/rolotrealanis98/m5pro-linux) @aa42195e `README.md`, `docs/boot-and-recovery.md`, `docs/smp-t6050-raw-path.md` |
| yuyuyureka (m1n1 PR #610, T6050/T6051) | macOS 26.2b2 and 27.0b2 | not stated | m1n1 | not stated | m1n1 runs, SMP broken | **second-hand only**: quoted in edimoldovan `CPU-START.md` and rolotrealanis `smp-t6050-raw-path.md`. Not read directly: it's upstream m1n1 (rule 7) |
| birkskyum, J716c M5 Max | 27.0.1 (26A434), iBoot 20457.1.29 | none | none (ADT from macOS only) | none | n/a | [#293 body](https://github.com/omacom/linux-aurora/issues/293) |
| Gravity Linux (M5 Pro/Max) | "as of macOS 27.0 Beta 5" | — | — | — | SMP blocked | quoted in both docs above |
| antiapplefox/m5-linux | research from the 26.5 IPSW (mBoot-18000.120.36) | — | — | — | no boot claimed | [README](https://github.com/antiapplefox/m5-linux) |

## Facts that matter for us
1. **Apple fixed a raw-boot-object issue in stage-2 mBoot for M5 Pro/Max/Ultra** in macOS 27.3 beta 1 (26C5035r). REPORTED quote of the release notes, "mBoot > Resolved Issues": "Only a single core is available when you boot Linux or other third-party operating systems from a custom raw boot object on Mac computers with M5 Pro, M5 Max, and M5 Ultra chips. (182898702)". Confirmed working only after the **stub was recreated** on 27.3b1 (rolotrealanis98).
2. **An iBoot-side size cliff exists, but it's layout-relative** (REPORTED, rolotrealanis98): ~0x4D0000 boots and ~0x4F0000 loops on J716s, and similar cliffs are seen on T8132/T8140. Their failure looks different from ours: "needs to be reinstalled" recovery or a hang, **not** an iBoot panic + PanicMedic. That cliff doesn't explain our failure, since our 192 KB probe failed too.
3. That repo also documents iBoot counting failed boots and dropping to recovery; macOS clears the count after a good boot. This matches our PanicMedic data (report 15).
4. Only the **1TR paired with the stub** can run kmutil ("Boot policy error … code pairing" otherwise), and a new restore bundle needs a new LocalPolicy (`bless` error 11 "AP boot mode"). Both REPORTED.

## Assessment [HYPOTHESIS]
The top-ranked cause is now **H4-firmware**: stage-2 mBoot-18000.161.10 (26.6.x) itself mishandles raw `fuos` boots on T6050. Every known-good point is 18000.120.36 or 20457.x, and our failure is size-independent and in iBoot. This is a correlation, not proof: probe2's result and our image content (H2/H3) remain open.

## Options (need owner/PM approval: these are firmware/OS changes)
1. **Recommended:** update Macintosh HD to macOS **27.3 beta 1 or later**, or the 27.x release that contains the fix, then **recreate** the stub from it (delete and re-create the stub + new 1TR policy; macOS's own data untouched). This gives the known-good stage 2 that boots *and* has SMP. Costs: a beta OS on the main install; a full stub rebuild and 1TR ceremony.
2. Update to stable **macOS 27.x** (20457.x stage 2, reported to boot raw m1n1, single-core) and recreate the stub.
3. Recreate the stub from a **26.5** restore bundle (18000.120.36, betizzel's working setup). This needs the 26.5 IPSW/bundle instead of the on-disk clone, and Apple signing for 26.5 is likely gone. Not recommended.
4. Change nothing and wait for probe2. If probe2 also panics, the firmware explanation gets stronger.

## Rule 7 record
Only public docs and issue text were read; no code was used. rolotrealanis98/m5pro-linux @aa42195e, antiapplefox/m5-linux and edimoldovan/kernel have no root AGENTS/CLAUDE/GEMINI.md and no license file (antiapplefox has only a `.claude/settings.json`). No upstream m1n1 repo, PR or code was opened; PR #610 is cited second-hand.


## Update 2026-11-04: NATIVE result supersedes the ranking above
**probe2 RAN on mBoot-18000.161.10 (NATIVE, J714s).** probe2 is 196,608 B, 16 KiB padded, with a branch at **file offset 0** to the entry. Result: **no iBoot panic**, the Mac stays powered on, black screen. There is no trusted framebuffer yet; a fix using the vram region from our ADT is in progress.
- **H4-firmware (stub stage 2 18000.161.x) is refuted:** this firmware does launch raw fuOS objects.
- **H-ENTRY is confirmed:** iBoot enters a raw fuOS at **file offset 0**, not at 0x800, on this firmware/kmutil combination, despite `--entry-point 2048`. The earlier images (m5boot, m5boot-gz, probe v1) had no valid code at offset 0, which explains the post-`fuos` iBoot panic.
- **Consequence:** every boot object must start with a branch at offset 0 (or carry its entry at 0). A macOS/firmware update is **not** needed for single-core boot. The 27.3b1 stub fix (above) still matters for SMP later.
- The text above is kept as written; its firmware ranking and recommendation are superseded by this result.


## CORRECTION 2026-11-04: the probe2 NATIVE claims above are RETRACTED
The owner photo shows step2-fast.sh printed "This is not the recoveryOS paired with Omarchy … Press enter to shut down" on **every** fast cycle. **probe2, gz2, beacon and beacon3 were never installed** (kmutil never ran); the black screen was the shutdown. Therefore:
- "H-ENTRY confirmed (entry at file offset 0)": **RETRACTED; H-ENTRY is UNTESTED**.
- "H4-firmware refuted" and "our code runs natively": **RETRACTED**; no new NATIVE evidence exists.
- The last real NATIVE results are still m5boot / m5boot-gz / probe v1 (iBoot panic after the `fuos` load).
- Cause of the failed cycles: report 18, correction section.


## NATIVE update 2026-11-04 (owner-verified; supersedes the open ranking for this question)
**beacon3 painted GREEN on stub firmware mBoot-18000.161.10.** beacon3 is a raw image with a **branch at file offset 0** plus **16 KiB padding**, and it was installed via `finish-install.sh` (a real kmutil install, unlike the retracted probe2 cycles). This is the first native code execution.
- The stock-image iBoot panic on 26.6.2 (ours and, REPORTED, asahi stage 1 on J613) is **avoided by our header**: a branch at offset 0 and/or 16 KiB padding. Which of the two matters isn't separated yet.
- The 26.6.x firmware itself doesn't block raw boots, so Plan B (report 22) stays a fallback only.
- The earlier retraction (probe2) stays as written; this result comes from a different, verified install.
