# 37 — What powers the MTP on T6050, and how aurora brings it up

**Bottom line:**
- The PS_PROT register isn't the MTP's power switch. It's a block shared by about 45 DARTs, and each DART picks its own slice of it. My t07 write hit slice 0. MTP's slice is 13, and I never read it.
- The MTP's PMGR power domains exist on T6050 (16 `MTP_*` entries) but have no register the AP can write. Those domains are probably always on, as Asahi treats them on T602x. Power is now an unlikely cause of the dead MTP.
- Aurora never cold-starts the MTP on these chips. Their loader starts it and hands Linux a running session (`apple,rtkit-handoff = "mtp-live-v1"`). Aurora also found that 25G83 MTP firmware dies when Linux wakes it after an earlier boot stage put it to sleep.
- Our MTP is stopped at hand-off and never runs after RUN. The next step is read-only: check that the firmware is really in SRAM, and read slice 13.

## 1. The t07 result (NATIVE, `reports/native-t07.txt`)
- **Before the write:** PS_PROT+0 read 0x0501a040.
- **The write:** `ps_on` set the target field to 0xf.
- **After:** the read-back was 0x0501a040 again, and the actual field stayed 0x4 for 10 ms.
- **Re-probe:** the stock re-probe again failed with -62, and no input devices appeared.
- **Side effects:** none seen. The write was ignored.

## 2. Correction to report 36: PS_PROT is shared, indexed by slice (from the ADT)
`reports/04-j714s-full.txt` (macOS ioreg; the raw dump isn't published) shows:
- **Every DART lists `PS_PROT`.** Its `instance` list includes `FPAG`/`PS_PROT` as a register window.
- **There are only two physical PS_PROT blocks** (16 KiB each):
  - **0x2803f0000:** used by the other DARTs, among them pmp0, sio, sep, pcie, display, dcp and ane.
  - **0x2890fc000:** used by mtp, aop, usb0-2, scaler, ave, jpeg, avd and apr1.
- **Each DART picks a slice** with `clock-protection-slice-index`:
  - dart-mtp: 13
  - dart-aop: 12
  - dart-usb0: 4, 5, 3, 4
  - dart-auss0 (on the other block): 13
- **What this means** (name-based interpretation): PS_PROT is clock protection that lets a DART's registers be reached safely while a power state changes. It isn't the coprocessor's own power state.
  - Report 36's "MTP is clock-gated (actual 0x4)" read the wrong word. It stays in that report as written; this report corrects it.
  - The t07 write targeted a word shared by other blocks. It was harmless, but **don't write PS_PROT again.**
- **Slice offset is unknown.** I don't know where slice 13 sits in the block (+0x34 at a 4-byte stride, or +0x68 at 8 bytes). t02 and t07 only read +0x00 to +0x1c, which was all zero apart from +0.

## 3. Correction to the T6050 DT comment: MTP PMGR domains exist but have no register
The PMGR node's `devices` table has 661 entries of 48 bytes, with the name at +32 and the device id at +26.
- **16 MTP entries exist.** They are MTP_FABRIC (parent NUB_FABRIC), MTP_GPIO, MTP_BASE, MTP_PERIPH, MTP_SCM_QSPI0, MTP_CPU, MTP_DMA, MTP_DMA2, MTP_SHIM_PCLK, MTP_SCM_FABRIC, MTP_SPI0, MTP_I2CM0, MTP_QSPI0, MTP_SCM_QSPI0_S, MTP_UART0 and MTP_SRAM, plus MTP_FAB_V.
- **None of them has a register.** Every MTP_* entry has flags 0x10 and a zero PS register and offset. This also holds for all SMC_*, AOP_FILTER/AOP_FR/AOP_DART, and the *_AONPCIE_V entries.
  - By contrast, real AP-controlled domains carry a register and offset. For example, ATC0_USB_AON has offset 0x148 in PMGR register window 2, and NUB_FABRIC has 0x1a8.
- **The MTP node itself has no power hooks.** `mtp@94600000` has empty `power-gates` and `clock-gates`, and `iop-mtp-nub` has `pre-loaded = 1`. Neither has a `notify-pmp`-style list.
  - macOS boots the MTP through RTBuddy alone, without a PMGR write.
- **Asahi does the same on T602x** (in-tree `t602x-pmgr.dtsi:2141`): "MTP stuff is self-managed". There, ps_mtp_* are `apple,always-on`, and the only thing Linux enables is `ps_mtp_fabric`.
- **HYPOTHESIS:** on T6050 the MTP power domains are always on, or owned by an always-on controller (SMC or PMP side). Either way the AP isn't expected to touch them.
  - The comment in `src/linux-asahi-wip72/arch/arm64/boot/dts/apple/t6050.dtsi:436` ("no MTP_* pmgr device at all") is wrong about the table. Its conclusion still holds: there is no PMGR domain Linux can attach.

## 4. How aurora does it (REPORTED; source read)
Source: `github.com/aurora-silicon/linux` @ `2661d71e16` (integration/aurora), licensed GPL-2.0 (COPYING). The repo has no CLAUDE.md, AGENTS.md or GEMINI.md at its root. I didn't read their m1n1 or aura loader.
- **Adopting a running session.** `drivers/soc/apple/rtkit-helper.c` and the `apple,rtk-helper-asc4.yaml` binding add `apple,rtkit-handoff = "mtp-live-v1"`:
  - The boot stage hands over the MTP running.
  - It also hands over the buffer list (`apple,rtkit-buffers`) and no-map reserved memory.
  - It keeps an identity (DVA == PA) DART bypass.
  - Linux adopts the session without restarting the MTP or taking it to QUIESCED. The probe refuses a handoff whose CPU isn't running.
  - Driver comment: "MTP firmware cannot always be restarted once it has been taken to QUIESCED or SLEEP".
- **Their T6050 keyboard needs that handoff.** Branch `t6050/mtp` (commit 23ddeb0e35, dockchannel-hid) enables T6050 keyboard reports on open, keyed on `apple,no-stm` and on whether the handoff is `mtp-live-v1`. So their T6050 keyboard depends on a loader-produced session.
  - Their public T6050 DTs (branch `j716c/t6050-dt`: j775d, die0) have no MTP node, so I found no public T6050 MTP DT.
- **25G83 firmware dies on wake after an earlier stop.** Commit cc245bb21e on branch `satchlj/j613-25g83-mtp-no-uboot-session` covers J613 (T8122) on **25G83, the same macOS build as ours**.
  - When U-Boot started the MTP and then quiesced it, the Linux wake (0x220) made the firmware data-abort.
  - Started fresh by Linux, the same firmware works. That commit is compile-tested only.
- **Their PMGR change doesn't touch the MTP.** Branch `t6050/pmgr` (commit 8b56d67e12) only adds `apple,preserve-active-control`: it leaves an already-active control word alone. It has no MTP power sequence.

## 5. How our case differs
- **CPU_CONTROL reads "stopped" at probe** (gz14, report 30 correction). So no earlier stage handed over a live session, and it isn't the satchlj case either: that firmware ran, crashed and wrote a crash log, while ours never sends a single message. The ADT says `pre-loaded = 1` for macOS boots. **Nobody has checked whether iBoot preloads the MTP on the fuOS path** — the open question.
- **After Linux sets RUN, the CPU never runs.** The mailbox inbound queue fills (2→4) and is never drained, the outbound queue stays EMPTY, and there are no DART faults (t02).
- **Possible causes, ranked:**
  1. **The firmware isn't in SRAM.** iBoot may skip the MTP preload when booting a custom kernel, so RUN executes nothing. A read-only check settles it.
  2. **The wrapper or CPU needs something before RUN.** The +0 register (0x94c00001) may be a boot base that also needs a reset pulse or a valid image header.
  3. **A power or clock domain is off.** This is less likely now: the domains look always on (§3), and macOS boots the MTP without a PMGR write.

## 6. Ranked plan
1. **t09, read-only, next native boot.** Extend the `m5_mtp` dump with an `sram` region (reads only) and a full PS_PROT window. Then:
   - (a) Dump the first 0x100 bytes of the TEXT segment at 0x294c00000 and the start of DATA at 0x294c54000. An Arm vector table or Mach-O header means the image is present; all zeros means it isn't.
   - (b) Dump PS_PROT 0x2890fc000 from +0x000 to +0x100, to find slices 12 (AOP) and 13 (MTP) and compare them.
   - (c) Dump the ASC registers (+0x0 to +0x100) and the wrapper before and after the stock re-probe.
   - No writes.
2. **If SRAM is empty: ask m5boot** (add the question to `~/m5boot/spec/inputs.md`). Is the MTP image present when m5boot starts? Can m5boot load the MTP firmware from the ADT segment ranges? Then we'd need a firmware source:
   - The macOS-extracted `AppleMTPFirmware` is Apple firmware, so it stays off-repo and is loaded at runtime from the macOS partition, the way the Asahi installer does it.
   - The owner must approve this.
3. **If SRAM holds the image but the CPU still won't run:** get a running session.
   - Option A: have m5boot be the "producer". It would start the MTP, do the RTKit hello, and hand Linux a `mtp-live-v1`-style session (buffer list plus reserved memory). That's what aurora's design needs, and it means m5boot implements a minimal RTKit (clean-room).
   - Option B: compare the wrapper and ASC registers with a working coprocessor (AOP or SMC under Linux, read-only) to find a missing reset or boot step.
4. **Don't pursue PMGR or PS_PROT writes for the MTP.** There's no AP register for its domains, and PS_PROT is shared.
5. **Fix the DT comment** in `t6050.dtsi` (devices table, §3) in the next DT revision.

Labels: §1 NATIVE; §2–3 come from the NATIVE macOS ADT, and the readings of them are marked HYPOTHESIS; §4 REPORTED (source read); §5–6 HYPOTHESIS and plan.
