# Public sources, provenance, and contributor task map (as of 2026-11-08)

This lists the public work we read or reused, how we used it, and where it does **not** fit this machine. Each project keeps its own licence and authorship. We don't submit anything to Asahi Linux, per their LLM policy.

**Status words:**
- **Adopted:** in a build we ran natively.
- **Adopted (offline):** in a build that is source-reviewed but not run yet.
- **Candidate:** read and mapped, not in any build.
- **Incompatible / blocked:** does not fit J714s on current firmware, with the reason.

**Current native route (2026-11-08):** the refreshed 26C5035r stub and public-source-derived m1n1/ESP storage chain now run all 15 CPUs and a hardware-rendered Omarchy desktop. All 15 CPUs passed pinned known-answer checks; Aurora reports 16 enabled GPU cores, four public GPU programs passed, and both Hyprland and a normal UWSM-managed client reported Apple G17S. This is short functional evidence; persistent isolated integration and broader qualification remain unfinished. The older 26.6.2 source notes below remain historical unless explicitly updated. Exact artifact identities and native limits are in [STATUS-2026-11-08.md](STATUS-2026-11-08.md).

- CPU integration: [TripleU613/linux-aurora](https://github.com/TripleU613/linux-aurora) at `87d61271369d9f3f5974df8663f5d0f1f77031fd` plus the local reviewed guards/config; native release `7.2.11-j714s-cpu-local`.
- Loader: [omacom/m1n1](https://github.com/omacom/m1n1) at `02785a35e046901d5686ab9059b2c08b6256752a` plus the reviewed local USB safety/configuration changes; the enrolled stage1 and public `boot=` storage route are adopted natively. Original per-file licences/attribution and the recorded owner AI project exception remain applicable.
- GPU: [Aurora #1173](https://github.com/aurora-silicon/linux/pull/1173) base `34f2f5bb4d03bbe3acce237cb67af8dc9972aa4a`, public [rolotrealanis98/m5pro-linux](https://github.com/rolotrealanis98/m5pro-linux) integration at `f60c7be55712f9f0e9abd95d72786fa4179cb292`, and local reviewed J714s metadata/guards are **adopted natively**. Firmware admission, actual fuse masks, rendering/compute and the accelerated desktop are verified on J714s; no thermal/performance/long-soak qualification is implied.
- Mesa: [rolotrealanis98/mesa](https://github.com/rolotrealanis98/mesa) at `043a4c58080c4951fea3797fe45fc6898ce77632`, with the public build/session recipes and four tests from m5pro-linux: **built and adopted natively** in an isolated prefix. Actual Apple G17S rendering/pixels/compute and a normal managed client passed, without system Mesa replacement. Persistence is still being prepared. The earlier voltage/firmware blockers describe the previous profile.

**Earlier source map:** the rows below preserve how the 26.6.2/aura prototypes and other candidates were assessed. They do not override the current native CPU status above. Their source findings are not automatically hardware qualification.

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
| omacom/m1n1 PR [#33](https://github.com/omacom/m1n1/pull/33) (head `275ecc4205ad`), [#34](https://github.com/omacom/m1n1/pull/34) (head `f1a942e393d1`) | #33: forwarding RVBAR from a chainloaded stage 2 (J716s/J714c). #34: the loader side of the N1 Wi-Fi bring-up | #33 **not adopted**: on our route RVBAR already equals aura's vectors, so there is nothing to forward. #34 **not yet read or used** (now permitted under the owner exception) | MIT. **omacom/m1n1 `main` carries upstream's AI-ban AGENTS.md**, the PR heads don't. Reading and reuse are covered by the owner project exception (2026-11-08). Anything taken keeps its attribution |
| aurora-silicon/linux [#1012](https://github.com/aurora-silicon/linux/pull/1012) (head `b1615e3fca90`) | The G17 GPU base under #1173 | **Blocked** (same as #1173) | GPL-2.0 |
| aurora-silicon/linux [#1182](https://github.com/aurora-silicon/linux/pull/1182) (head `a0e28f1c1ab6`), [#1183](https://github.com/aurora-silicon/linux/pull/1183) (head `2fdad550cebb`) | The canonical PRs for the N1 cold-train pieces we mapped from rolo's tree (J716s; J714c Wi-Fi/6 GHz/BT, REPORTED) | #1182: compared, no functional difference from our unpublished N1 candidate, which also carries one extra rolo patch. #1183: **used as the DT model** for that candidate (offline; one open question: whether `dart_apcie0` takes the SYS_GP power domain) | GPL-2.0 |
| edimoldovan/linux-aurora `t6050-j714c-gpu-main` @ `1f71340256fb` | J714c (27.3) GPU/PMP bring-up in progress ("PMP powered", REPORTED) | **Not adopted**: it is the G17C (M5 Max) + PMP series, a different GPU from our G17S | COPYING present, no AI instructions file |
| aurora-silicon/linux [#1079](https://github.com/aurora-silicon/linux/pull/1079) (merged), [#1184](https://github.com/aurora-silicon/linux/pull/1184) (open); found via [aura #114](https://github.com/aurora-silicon/aura/pull/114) | CTXR-execmem follow-ups to #985 | **Adopted (offline)** in an isolated *next* candidate kernel tree: it compiles, has **not been booted**, and is not part of the prototype above | GPL-2.0 |
| aurora-silicon/linux [#1085](https://github.com/aurora-silicon/linux/pull/1085) (merged) | J714c (M5 Max 14") DT | **Used as a DT model** for our unpublished N1 candidate (offline) | GPL-2.0 / MIT DT |
| aurora-silicon/linux [#826](https://github.com/aurora-silicon/linux/pull/826) (merged), [#1171](https://github.com/aurora-silicon/linux/pull/1171) (merged), [#1108](https://github.com/aurora-silicon/linux/pull/1108) (closed), [#1177](https://github.com/aurora-silicon/linux/pull/1177) (open) | T6050 cpuidle; M4 26.6.2 firmware paths; a draft T6050 DT; the M5 Max render-context layout | **Not adopted:** #826's equivalent is already present; #1171 is M4-only, with no SMP effect and no T6050/G17 files; #1108 is reference only; #1177 is G17C (M5 Max) | GPL-2.0 |
| [AsahiLinux/m1n1](https://github.com/AsahiLinux/m1n1) | — | Its CLAUDE.md/AGENTS.md asks AI tools not to use it (since 2026-07-14). **Owner project exception (2026-11-08):** licensed public m1n1 sources may be read, compared and built locally for this project, with licences and attribution kept; the notice is recorded. Basis of the small m1n1/ESP chain now in preparation (not installed) | MIT |

## Our own unpublished work (not available publicly yet)
- The T6050-confined aura patch, plus the bundle builder and contract checks for the all-15 prototype.
- The 7.3 CTXR kernel integration, DT and keyless initrd.
- The current GPU integration with J714s metadata (native short rendering/compute and desktop tests passed; complete local integration not exported yet).
- The N1 Wi-Fi sequence (builds 3408/3410).
- The loader SMP diagnostics and Mach-O wrapper (beyond aura's tool).
- The operator scripts (install, restore, readback, first contact).

The older published snapshots are in `m5boot/` and `m5-omarchy/`, and `patches/` holds kernel diffs up to #28. Please reply in the [omacom/linux-aurora#293](https://github.com/omacom/linux-aurora/issues/293) thread, where the owner keeps a running status comment (this repo has issues turned off), before relying on any of the work above.

## Contributor task map
| # | Area | What would help | Needs hardware? | Public starting point |
|---|---|---|---|---|
| 1 | GPU | Review/export the J714s integration and isolated persistent package/session route; extend the now-passing native short tests with bounded compatibility/thermal qualification | Source first; owner-controlled hardware later | #1173, pinned Mesa `043a4c5` and the native results/limits in STATUS |
| 2 | GPU | Any **27.2 G17S** hardware result on an M5 Pro (J714s or J716s) | Yes (someone's own machine) | #1173 "Hardware result" section |
| 3 | CPU / RAM / storage | Reproducible export of the now-native 15-CPU route, then bounded current-profile stability/memory/I/O qualification; old one-core benchmarks are historical | Export: no; qualification: yes | Current artifact table and limits in STATUS |
| 4 | Wi-Fi | A NATIVE log of the T6050 `pinctrl_ap` probe at runtime, or of the PCIe system power domain powering on, on any M5 | Yes | #937/#938, rolo's N1 docs |
| 5 | Wi-Fi | The correct T6050 **cio3pllcore** tunable/offset (T8140-style layout vs aura `atc.py`) | No (source reading) | aura, edimoldovan m1n1 |
| 6 | Debug | A **pstore/ramoops** setup known to work on M-series, so a crash within milliseconds leaves a trace | Maybe | Asahi/Aurora kernel trees |

Current results and exact status are in [STATUS-2026-11-08.md](STATUS-2026-11-08.md).
