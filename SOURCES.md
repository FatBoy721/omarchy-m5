# Public sources, provenance, and contributor task map (as of 2026-11-08)

This lists the public work we read or reused, how we used it, and where it does **not** fit this machine. Each project keeps its own licence and authorship. We don't submit anything to Asahi Linux, per their LLM policy.

**Status words:**
- **Adopted:** in a build we ran natively.
- **Adopted (offline):** in a build that is source-reviewed but not run yet.
- **Candidate:** read and mapped, not in any build.
- **Incompatible / blocked:** does not fit J714s on current firmware, with the reason.

**Firmware during these results:** macOS 26.6.2 (25G83), stub stage-2 mBoot-18000.161.10. No beta, no stub recreation. (A macOS 27 update of the main macOS started afterwards; see STATUS.)

**Note (REPORTED, public):** every all-core SMP result reported so far on M5 Pro/Max (J714s, J716s, J714c) is on a **27.3 beta 1 stub**. On J714s with stage-2 18000.120.36, the secondaries were reported failing. Our route tests the current 26.6.2 firmware instead.

**How sources were gathered:** public GitHub and the [omacom/linux-aurora#293](https://github.com/omacom/linux-aurora/issues/293) thread, read by our Claude research workers. A planned Antigravity scout could not run (CLI sign-in blocked). Rows added from that research are **candidate/reference only** until adoption is checked.

## Source index
| Source | What we take from it | Status on J714s | Licence / AI instructions (as recorded) |
|---|---|---|---|
| [betizzel/omarchy-m5](https://github.com/betizzel/omarchy-m5) | Stub macOS scripts (`prep-stub.sh`, `finish-install.sh`, run unmodified); first J714s T6050 kernel patches and DT; SMP/WFI findings docs | **Adopted** (stub install, every native boot) | Per-file SPDX MIT on the stub step2 script; **no top-level licence file**, so we don't redistribute modified copies. No AI instructions file |
| [AsahiLinux/linux](https://github.com/AsahiLinux/linux) `asahi-wip-7.2` (branch name at the time; it no longer exists under that name) | Kernel base for our 7.2.x kernels (#28-#32) | **Adopted** | GPL-2.0 |
| Asahi docs, Apple XNU headers (APSL) | Boot-args/ADT format for our own boot object (m5boot) | **Adopted** | Each project's licence |
| [aurora-silicon/aura](https://github.com/aurora-silicon/aura) @ [`5211a863`](https://github.com/aurora-silicon/aura/commit/5211a863fc3f2c8eb56b5feae64cf05cc9a1dca6) | (1) `tools/macho_boot_object.py`, used to wrap our diagnostic as a `kcbz 0` Mach-O. (2) The base of the all-15-core prototype (CTXR-confined EL2, spin-table) | (1) **Adopted** (NATIVE 1-core park, 2026-11-08). (2) **Adopted** with our *unpublished* T6050-confined patch, default off: one NATIVE trial attempted 2026-11-08, Linux not reached (cause not determined) | MIT AND GPL-2.0-only per file; its CLAUDE.md allows AI use |
| [aurora-silicon/linux #985](https://github.com/aurora-silicon/linux/pull/985) (merged) | Linux at EL2 with code confined to a CTXR window | **Adopted (offline)** in the 7.3 prototype kernel | GPL-2.0. No CLAUDE.md/AGENTS.md (checked) |
| aurora-silicon/linux #985 vs our kexec chain | — | **Incompatible:** #985 refuses kexec while a window is active, so the all-core route is a single-stage boot, with no kexec | — |
| [aurora-silicon/linux #1173](https://github.com/aurora-silicon/linux/pull/1173) (open) | G17S GPU InitData: the driver **source** supports 27.2 and 27.3 firmware; J716s tables. The only **demonstrated hardware** result is G17S on **27.3 beta 1 on J716s** (REPORTED); no 27.2 hardware success was found in the sources we reviewed | **Blocked:** (a) needs 27.x G17S firmware in the stub (the firmware is iBoot pre-loaded; a 26.x stub can't run it); (b) its J716S voltage table is **below** J714s bins at several states (13/14 states differ), so we refuse to init with it | GPL-2.0 |
| [rolotrealanis98/m5pro-linux](https://github.com/rolotrealanis98/m5pro-linux) @ `aa32733` | J716s Wi-Fi/BT bring-up (kernel cold-train series, loader contract); GPU m1n1 handoff and DT patches | **Candidate** (mapped; Wi-Fi pieces informed our N1 work) | LICENSE.md: kernel GPL-2.0-only, DT GPL-2.0+ OR MIT, m1n1 patches MIT, docs MIT. No AI instructions file; we read only the current tree, as its README asks clean-room readers |
| [aurora-silicon/linux #937](https://github.com/aurora-silicon/linux/pull/937) / [#938](https://github.com/aurora-silicon/linux/pull/938) (open) | T6050 PCIe root-port adoption; N1 Wi-Fi/BT driver | **Candidate** for J714s (REPORTED working on J716s with rolo's cold train). Our own N1 attempt (build 3408) failed natively, cause unknown | GPL-2.0 |
| edimoldovan trees (`linux-aurora` `t6050-j714c`, `m1n1` `t6050-aurora`) | J714c (M5 Max) platform port, N1 cold-train parts, PLL/tunable references | **Candidate / reference**. Note: public sources disagree on the T6050 cio3pllcore offset | GPL-2.0 kernel code, authorship kept |
| betizzel/omarchy-m5 @ `f3226fb` (newer) | (a) J714s report in [#293](https://github.com/omacom/linux-aurora/issues/293): on a 26.5 stub, 14/14 secondaries failed; after updating to 27.3b1 **and recreating the stub**, 14/14 started. (b) A WFI register-preserve idle patch (27.3b1) | **REPORTED / reference only.** (a) needs a 27.3b1 stub recreate, which is not approved here. (b) is not adopted. Our current route uses aura's `idle=nop` | **No licence file**, no AI instructions file, so reference only |
| omacom/m1n1 PR [#33](https://github.com/omacom/m1n1/pull/33) (head `275ecc4205ad`), [#34](https://github.com/omacom/m1n1/pull/34) (head `f1a942e393d1`) | #33: forwarding RVBAR from a chainloaded stage 2 (J716s/J714c). #34: the loader side of the N1 Wi-Fi bring-up | #33 **not adopted**: on our route RVBAR already equals aura's vectors, so there is nothing to forward. #34 **not read, not used**, pending a scope ruling on that repo's AI instructions | MIT. **omacom/m1n1 `main` carries upstream's AI-ban AGENTS.md**, the PR heads don't. Reading/reuse of #33 is covered by a recorded owner/management override; #34 still awaits a scope ruling. Anything taken keeps its attribution |
| aurora-silicon/linux [#1012](https://github.com/aurora-silicon/linux/pull/1012) (head `b1615e3fca90`) | The G17 GPU base under #1173 | **Blocked** (same as #1173) | GPL-2.0 |
| aurora-silicon/linux [#1182](https://github.com/aurora-silicon/linux/pull/1182) (head `a0e28f1c1ab6`), [#1183](https://github.com/aurora-silicon/linux/pull/1183) (head `2fdad550cebb`) | The canonical PRs for the N1 cold-train pieces we mapped from rolo's tree (J716s; J714c Wi-Fi/6 GHz/BT, REPORTED) | #1182: compared, no functional difference from our unpublished N1 candidate, which also carries one extra rolo patch. #1183: **used as the DT model** for that candidate (offline; one open question: whether `dart_apcie0` takes the SYS_GP power domain) | GPL-2.0 |
| edimoldovan/linux-aurora `t6050-j714c-gpu-main` @ `1f71340256fb` | J714c (27.3) GPU/PMP bring-up in progress ("PMP powered", REPORTED) | **Not adopted**: it is the G17C (M5 Max) + PMP series, a different GPU from our G17S | COPYING present, no AI instructions file |
| aurora-silicon/linux [#1079](https://github.com/aurora-silicon/linux/pull/1079) (merged), [#1184](https://github.com/aurora-silicon/linux/pull/1184) (open); found via [aura #114](https://github.com/aurora-silicon/aura/pull/114) | CTXR-execmem follow-ups to #985 | **Adopted (offline)** in an isolated *next* candidate kernel tree: it compiles, has **not been booted**, and is not part of the prototype above | GPL-2.0 |
| aurora-silicon/linux [#1085](https://github.com/aurora-silicon/linux/pull/1085) (merged) | J714c (M5 Max 14") DT | **Used as a DT model** for our unpublished N1 candidate (offline) | GPL-2.0 / MIT DT |
| aurora-silicon/linux [#826](https://github.com/aurora-silicon/linux/pull/826) (merged), [#1171](https://github.com/aurora-silicon/linux/pull/1171) (merged), [#1108](https://github.com/aurora-silicon/linux/pull/1108) (closed), [#1177](https://github.com/aurora-silicon/linux/pull/1177) (open) | T6050 cpuidle; M4 26.6.2 firmware paths; a draft T6050 DT; the M5 Max render-context layout | **Not adopted:** #826's equivalent is already present; #1171 is M4-only, with no SMP effect and no T6050/G17 files; #1108 is reference only; #1177 is G17C (M5 Max) | GPL-2.0 |
| [AsahiLinux/m1n1](https://github.com/AsahiLinux/m1n1) | — | **Not used by our AI sessions:** its CLAUDE.md/AGENTS.md asks AI tools not to use it (since 2026-07-14). Forks are judged by their own instructions | — |

## Our own unpublished work (not available publicly yet)
- The T6050-confined aura patch, plus the bundle builder and contract checks for the all-15 prototype.
- The 7.3 CTXR kernel integration, DT and keyless initrd.
- The GPU candidate (hard-disabled on J714s).
- The N1 Wi-Fi sequence (builds 3408/3410).
- The loader SMP diagnostics and Mach-O wrapper (beyond aura's tool).
- The operator scripts (install, restore, readback, first contact).

The older published snapshots are in `m5boot/` and `m5-omarchy/`, and `patches/` holds kernel diffs up to #28. Please reply in the [omacom/linux-aurora#293](https://github.com/omacom/linux-aurora/issues/293) thread, where the owner keeps a running status comment (this repo has issues turned off), before relying on any of the work above.

## Contributor task map
| # | Area | What would help | Needs hardware? | Public starting point |
|---|---|---|---|---|
| 1 | GPU | A decoded **J714s** GPU perf/voltage table from a 27.x ADT, or a source explaining the constant `perf-states-sram` value **1385** on 26.x J714s ADTs | No (ADT/source reading) | #1173 `g17/fw/m5/initdata.rs` (J716S tables), aura `src/kboot_gpu.c` SRAM rule |
| 2 | GPU | Any **27.2 G17S** hardware result on an M5 Pro (J714s or J716s) | Yes (someone's own machine) | #1173 "Hardware result" section |
| 3 | CPU | Experience running **aura** (CTXR / confined EL2) on any T6050: whether iBoot arms CTXR_D over a large Mach-O object; secondary-start behaviour on stage-2 18000.x | Yes | aura `5211a863`, linux #985 |
| 4 | Wi-Fi | A NATIVE log of the T6050 `pinctrl_ap` probe at runtime, or of the PCIe system power domain powering on, on any M5 | Yes | #937/#938, rolo's N1 docs |
| 5 | Wi-Fi | The correct T6050 **cio3pllcore** tunable/offset (T8140-style layout vs aura `atc.py`) | No (source reading) | aura, edimoldovan m1n1 |
| 6 | Debug | A **pstore/ramoops** setup known to work on M-series, so a crash within milliseconds leaves a trace | Maybe | Asahi/Aurora kernel trees |

Current results and exact status are in [STATUS-2026-11-08.md](STATUS-2026-11-08.md).
