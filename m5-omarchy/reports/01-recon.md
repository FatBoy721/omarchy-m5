# 01 — Recon: M5 (T6050) support status

Researched 2026-11-04. Upstream SHAs: m1n1 `70757dc7`, asahi-installer `e93743d`. Details, PR tables and the repo map are in `01-recon-appendix.md`. **[guess]** marks inference.

## TL;DR

1. **Mission-level constraint: Asahi bans LLM contributions.** The [policy](https://asahilinux.org/llm-policy/) "broadly forbid[s] the use of generative AI tooling for material contributions". LLM-drafted issues get closed, and "a contributor using an LLM to interpret a trace made using the m1n1 hypervisor may be issued with a first and final warning". This is already enforced on M5: m1n1 issue [#706](https://github.com/AsahiLinux/m1n1/issues/706) was a careful, scrubbed T8142 ADT recon, and it was closed for being AI-drafted. Every m1n1 PR requires the author to certify they used no LLM. **Consequence:** nothing a Claude session writes goes to Asahi. the owner reports in their own words, from their own observations, and hypervisor tracing stays human-driven.
2. **Our chip is T6050 (M5 Pro), and upstream support is minimal.** m1n1 has CPU IDs, the UART base, pmgr support and the SMP start offset. SMP itself was broken when added ([#610](https://github.com/AsahiLinux/m1n1/pull/610)): the secondary cores power on but never run code. No public upstream commit has touched T6050 since 2026-06-29. No public Asahi kernel tree has a T6050 or T8142 device tree.
3. **Aurora Silicon (upstream of Omarchy's Mac kernel) has a T6050 series, but it's a different architecture and its claims are unverified.** Linux runs as a guest under "Aura", their GPL fork of m1n1 that acts as an EL2 monitor with "SPTM mediation". Linux reaches native firmware calls through it ("APIF"). [guess: from the x16/x0–x5 wire format, Apple's own SPTM stays resident and Linux dispatches into it.] Their site marks J714s "works" (18 cores, NVMe, Wi-Fi, keyboard…), but the source of that data is "Project owner confirmation in this session". Their own discussion [#142](https://github.com/aurora-silicon/linux/discussions/142) says, for J714S: "No matching working-tree DTS or named-board runtime result found". The T6050 branches are "build- and host-tested only".
4. **No public, hardware-verified M5 GPU work exists.** Asahi lists the GPU as WIP for base M3 only, and TBA for M3 Pro/Max, M4 and M5. Aurora runs G17P (A18 Pro) and defines an M5 (G17G/G17S) Mesa runtime. Its kernel reserves those uAPI numbers but implements none of them, and its cited `t6050-gpu` snapshot is not a public branch.

## Q1. m1n1 on M5 today

- **IDs:** M5 Pro = **T6050** ("Sotra", MIDR 0x64 M-core / 0x65 P-core). M5 Max is labelled T6051 ("Sotra C") in [`b2d3f5eb`](https://github.com/AsahiLinux/m1n1/commit/b2d3f5eb). The [device list](https://asahilinux.org/docs/hw/devices/device-list/) has J714sAP = Mac17,9 = T6050. *Inconsistency:* `soc-codenames.md` lists M5 Max as T6050 too, and one J716C owner's ADT shows `chip-id 0x6050`. For J714s, every source says T6050.
- **Merged:**
  - [#578](https://github.com/AsahiLinux/m1n1/pull/578): pmgr, giving device-mode USB on the M5 Max MBP.
  - #610: UART at `0x505200000`, the SMP offset and chickens. It boots on core 0, an M-core; secondary cores are broken.
  - Generic M4+ work: SPMI gen4, SARTv4, NVMe, WFI handling, SPTM in the hypervisor ([#698](https://github.com/AsahiLinux/m1n1/pull/698)).
- **Hypervisor:** #737/#738/#740/#741/#754 are merged. [#758 "M5 hypervisor"](https://github.com/AsahiLinux/m1n1/pull/758) is open with no reviews. The chip-specific parts are T8142 (#737 CPU startup/MCC, #758 chip checks); the rest is generic M5 hypervisor work found through the M5 kernelcache.
- **Hardware:** Yureka has an M5 Max MBP and tested T6050/T6051 on 26.2b2 and 27.0b2. Sven works on T8142 [guess: base M5]. There is no public J714s tester.
- **SMP on T6050:** no evidence of a fix. M4 was fixed by the CTRR_M4 reserve plus disabling WFI (#657). [guess] Still broken or untested.

## Q2. Linux kernel on M5

- **Asahi:** no T6050/T8142 code. I checked the DT directories, branch names, code search, and the Yureka, Sven and Janne forks. The newest DTs are M4/A18 Pro in `apple-soc/dt-7.5`. The [7.2 report](https://asahilinux.org/2026/08/progress-report-7-2/) (Aug 2026) and [MacG](https://www.macg.co/macos/2026/08/asahi-linux-se-rapproche-dune-sortie-sur-les-mac-m3-et-progresse-deja-sur-les-m4-et-m5-310683) say NVMe works on M4 and "early M5", PCIe enumerates, a multi-core crash was fixed, and "not much else is working". The [M5 table](https://asahilinux.org/docs/platform/feature-support/m5/) is TBA everywhere.
- **Aurora/omacom:**
  - `t8142-j813` (base-M5 Air) DTs by Acelogic: boots from RAM with panel, keyboard, trackpad and USB3, in software rendering.
  - The T6050 `t6050/*` APIF series by DjDeveloperr, on Linux 7.3: not hardware-qualified.
  - Per Aurora's docs, M5 Pro Wi-Fi/BT is Apple **N1**, which Asahi has no driver for. But the base-M5 ADT in #706 shows `bcm4387`, so step 1 below checks this.

## Q3. How to boot m1n1 on an M5 today

**The Asahi installer can't do it.** `main.py:973` rejects any chip or device missing from its tables, and expert mode doesn't bypass that check. The tables stop at M3. Omarchy's installer refuses "M4 and later" explicitly.

**Manual path** ([m1n1 guide](https://asahilinux.org/docs/sw/m1n1-user-guide/), [tethered boot](https://asahilinux.org/docs/sw/tethered-boot/), installer `step2.sh`):
1. Create a second APFS container with macOS ≥26.x to act as the stub OS.
2. From the stub's own 1TR, run `bputil -nc -v <VGID>`. This makes the stub Permissive; macOS stays Full Security.
3. Run `kmutil configure-boot -c m1n1.bin --raw --entry-point 2048 --lowest-virtual-address 0 -v <stub vol>`.
4. Run `csrutil disable && nvram boot-args=-v` to enable the proxy-mode backdoor.
5. Optional: `csrutil authenticated-root disable`, which turns on debugusb UART ([`1a0e81f9`](https://github.com/AsahiLinux/m1n1/commit/1a0e81f9)).

[guess] A locally patched installer that adds `0x6050`/`j714sap` is the alternative. Omarchy's overlay already does this for `0x8140`.

**Second machine:** ush running m1n1 `proxyclient`, connected by USB-C to a Thunderbolt port on the MacBook.

**Recovery:** first, the boot picker gets back to macOS, which is untouched. Last resort is a DFU **revive** (keeps data), then **restore** (erases). DFU needs a second Mac **physically connected by cable**, running Apple Configurator or Finder ([Apple](https://support.apple.com/en-us/108900)). another Mac (a second machine) has to be in the room; Tailscale doesn't help. The DFU port on M4/M5 MBPs is front-left per a wiki; verify it against Apple's article first.

## Q4. M4 learnings that carry over

- **SPTM is mandatory for XNU on M4+.** Sven's SPRR/GXF emulation brought the hypervisor back (slower tracing). The M5 hypervisor work builds on it.
- **Core configuration is locked down from M4:** chicken bits are set and locked by mBoot, and WFI loses state. m1n1 disables WFI; Linux needs the idle-loop parameter (now in linux-next) and a cpuidle driver.
- The NVMe (ANS2) firmware ABI changed in the macOS 15 bundle. It's fixed in m1n1 and Linux.
- **GPU generations** (Aurora naming, not confirmed by Asahi): M3 = G15, M4 = G16, A18 Pro = G17P, M5 = G17G/G17S. GPU and DCP firmware ABIs are pinned to one macOS version per generation (M1/M2 → 13.5, M3 → 14.8.3). Asahi hasn't picked an M5 target yet.

## Q5. Omarchy layer

**omacom** is Omarchy's GitHub org; malik-na and maralcbr are members.
- It packages the Mac stack: `omarchy-mac-pkgs`, built through `omarchy-pkgs` and published to pkgs.omarchy.org.
- Its installer is a Swift app plus the Asahi v0.9.2 engine.
- It syncs its kernel (`linux-aurora`), m1n1 and Mesa from **Aurora Silicon** ([aurorasilicon.org](https://aurorasilicon.org)).
- Supported: M1–M3 and the A18 Pro Neo. M4+ is refused.
- `maralcbr/omarchy-m-testing` is the hardware-test catalogue.

**Adding a chip** (inferred):
1. Bootloader support.
2. DTs and drivers in linux-aurora.
3. Engine overlay chip/device entries plus `supported-models.json`.
4. The `omarchy-mac-boot` DTB selector.
5. Qualification in omarchy-m-testing.

## Q6. Where to coordinate

**Asahi:** OFTC IRC, TLS on port 6697 ([community](https://asahilinux.org/community/)).
- `#asahi-dev` is for development.
- `#asahi-alt` is for **unofficial third-party distro ports**. That's where Omarchy belongs.
- `#asahi-re` keeps tainted/decompilation discussion separate.
- The Matrix space is `#asahilinux:matrix.org`.
- Etiquette: no ETA questions, scrub serials/MACs/nonces, and follow the LLM policy.

**Aurora:** GitHub Discussions; #142 is the M5 MBP thread.

## Q7. Proposed ladder for J714s

Each step needs PM approval; steps 2–3 need the owner's hands (Rule 1).

| # | Experiment | Needs | Risk |
|---|---|---|---|
| 1 | **Read-only dump** (`ioreg -p IODeviceTree -l`, `bputil -d`, scrubbed). Confirm chip-id, board-id, clusters (2×6 M + 1×6 P?), UART `0x505200000`, iBoot version, the `wlan-pcie` compatible (N1 or Broadcom), and which compatibles m1n1 doesn't know. | A task allowing read-only `ssh macbook`. | None. |
| 2 | **Tethered m1n1 proxy, no Linux** (stub + Permissive on the stub only + `kmutil`, proxyclient on ush). Goal: m1n1 banner and `shell.py`, then retest `smp_start_secondaries` (#610). | About 40 GB for the stub, a USB-C cable, the owner in 1TR, a co-located Mac. | Low. macOS stays Full Security; worst case is a DFU revive. |
| 3 | **First kernel:** a minimal hand-written `t6050-j714s.dts` (CPUs, AIC3, UART, simplefb) plus an asahi kernel via `linux.py`. Goal: earlycon output and penguins. | Step 2 working. | Low (RAM only). Watch WFI/idle and the M-core boot CPU. |

## Decisions for the PM

1. **LLM policy.** How do we contribute, if at all?
   - (a) the owner-only human reports.
   - (b) Keep our work in our own repo or Omarchy/Aurora.
   - (c) the owner asks in `#asahi-alt` what testing help Asahi would accept.
2. **Base layer.** Pick one:
   - (a) Upstream m1n1 + Asahi: native and clean, but T6050 is barely past SMP.
   - (b) Aurora Aura/APIF: claims more, but it's unverified and [guess] depends on Apple's SPTM, and Asahi won't take code derived from it.

   Cheap check first: ask in Aurora #142 whether any J714s boot log exists.
3. **Recovery.** Approve a Mac being physically next to the MacBook before step 2.
