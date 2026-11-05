# 03B — PMP on T6050

Public sources only (Asahi code and docs, #293, betizzel's and edimoldovan's repos) plus our scrubbed dump. **[guess]** marks inference. I read no proprietary code.

## What it is
- **The coprocessor:** PMP is Apple's power-management/measurement coprocessor. On J714s it's `pmp0@84E00000`, compatible `iop,ascwrap-v6`, the same ASC wrapper generation as MTP, AOP, ANS, SMC and DCP on this chip. Its nub `iop-pmp0-nub` is `iop-nub,rtbuddy-v2`, which means **RTKit**. It sits behind `dart-pmp0` (`dart,t8110`) with mappers `mapper-pmp0` and `mapper-pmp0-ptd-fwd` (our dump). edimoldovan reports that the IPSW template also lists `pmp1`.
- **Firmware** (Asahi [platform intro](https://asahilinux.org/docs/platform/introduction/) table): PMP firmware lives in **Preboot**, is **loaded by iBoot2**, and is **started by the OS**. That matches J714c: the firmware image is present in `pmp0 reg[2]` (1 MiB, ~95k non-zero words, unchanged), but it is not running.
- **Interfaces:**
  - **PTD window:** `ptd-update-reg-index` reg minus `0x10000`. It's a shared status/request table described by `ptd-range` (32-byte entries `{id, offset, unk[8], name[16]}`; read = offset×16, write = offset×8+0x10000). Entries include `PMP-STATUS`, `SOC-DEV-PS-REQ/ACK` (device power requests), `PMP-TO-GFX` and `GFX-TO-SMC`. edimoldovan posted the full J714c table in #293, and J716c matches it.
  - **PMGR side:** domains with `notify_pmp` (ADT flag) must be switched through PMP, not by plain PMGR writes. On T6050, `cs` (the GPU domain) has it.
- **What macOS runs:** not established from public sources. The IOService plane of `ioreg` would show the macOS driver classes bound to `pmp0`, and our dump only covered IODeviceTree. → Add `ioreg -p IOService -l -w0 -r -n pmp0` to the next read-only dump. That reveals class and driver names without reverse engineering.

## How it works on M1–M3 (Asahi, public)
- **Linux starts PMP itself.** `drivers/soc/apple/pmp.rs` (Asahi kernel `c8ec9be8`):
  - Starts RTKit and endpoint **0x20**.
  - Patches the PMP bootargs found at nub `+0x22c` (offset) / `+0x230` (size), including a DCAP value on T600X.
  - Then serves the firmware's requests: `GET_IOVA_TABLE` 0x10, `MALLOC` 0x12, `FREE` 0x14, `SET_BUF` 0x30, `REGISTER_IOREG` 0x32, `SET_IOREG` 0x34.
- `drivers/pmdomain/apple/pmp-report.c` turns `notify_pmp` domains into power domains that write `SOC-DEV-PS-REQ` and poll `-ACK`/`PMP-STATUS`.
- **m1n1:**
  - `kboot.c` `dt_set_pmp()` copies the PMP ADT properties into the FDT (`1124c22e`, Sasha Finkelstein).
  - `proxyclient/experiments/pmp_init.py` is a host-side start of the same protocol, derived from hypervisor traces of macOS on M1–M3.
  - `tools/pmp_assist.py` decodes `ptd-range` / `soc_device`.
  - `hv/trace_pmp.py` covers T600X, T602X, T8112, T8122, T6030 and T603[14] (Yureka `11934771`).
- So the **protocol is already public** for earlier chips. T6050 is the first chip where "the OS starts PMP" also gates **CPU core release**, not just device power.

## What has been tried on T6050 (#293, 2026-11-03)
- **edimoldovan, J714c:**
  - `ps_pmp` power domain is on.
  - PMP firmware is loaded but `PMP-STATUS`, `SOC-DEV-PS-REQ/ACK` and `PMP-TO-GFX` all read 0.
  - **Reading the PMP ASC block `reg[0]+0x44` raises a SYNC exception from EL2.** `+0x44` is `ASC_CPU_CONTROL` in Asahi's RTKit layout. So m1n1 can't run the M1–M3 start (`pmp_init.py`).
  - A 16 KiB bulk read of the PTD window crashed the proxy; single 32-bit reads are fine.
  - The per-core `cpu-impl-reg` window also SErrors everywhere except `+0x0` (RVBAR) and `+0x100`, even on cpu0.
  - Secondary cores power up (PS reads `0xef20d102`) with the right RVBAR but never fetch.
  - GPU: the G17C firmware initializes, but jobs stall because `cs` won't power on (`notify_pmp`).
- **birkskyum, J716c:** same `ptd-range` and PMP `reg` offsets, so it probably also applies to M5 Max.
- **betizzel, J714s:** its probes (`smp-*.py`, `t6050-smp-probe.py`) reached the same "powers up, executes nothing" state. It attributes this to SPTM, based on disassembly of Apple's SPTM binary (avoid reusing that material).
- **Why base M5 (T8142) works:** scottjones has all 10 cores running on J815, and so does Aurora's J813. edimoldovan: T8142's `pmgr` has `function-pmp_control`, and core release is driven by PMGR registers writable at EL2. On T6050 that function is gone from `pmgr` and the release moved into PMP. Check this in our own data: grep `function-pmp_control` in a `--full` dump.

## Candidate approaches (ranked by feasibility)
1. **Static ADT diff of `pmp0` against `mtp`** (cheap, no hardware). Both are `ascwrap-v6` + rtbuddy-v2, and the kernel *can* start MTP on T6050 (edimoldovan: MTP `CPU_CONTROL` was 0 and the kernel started it). Compare their `reg` lists and wrapper properties.
   - [guess] PMP's CPU-control register sits in a different reg index or a separate wrapper region, the way GFX on ascwrap-v6 has separate "wrapper" and "iop-vbar" bases (edimoldovan's mailbox patch). That would make the `+0x44` fault a wrong-address problem, not a lock.
   - Needs: a `--full` dump (add it to the next dump task).
2. **Check access-control state** (read-only, needs hardware + m1n1). Read the other PMP ASC offsets one by one (`+0x0`, `+0x8000` mailbox), the PMP DART, and the `pmp0` reg[1..n]. That tells "whole block locked" apart from "wrong register". If the mailbox is reachable but `CPU_CONTROL` isn't, [guess] iBoot or the platform security setup protects PMP start for raw boot objects. Low risk. Each probe is a single 32-bit read; never bulk-read.
3. **Port Asahi's `pmp.rs` start to T6050 under Linux** once (1) or (2) finds a writable control path. The protocol, bootargs patch and endpoint 0x20 are already public, so this would unlock `notify_pmp` domains (GPU `cs`) and possibly core release. Medium effort.
4. **Boot through SPTM properly** (Sven's XNU-shim idea, the Aurora/Aura approach). If PMP start or the core-release registers are only reachable when the boot goes through the normal XNU/SPTM path, a loader that sets up SPTM and registers as XNU might get them unlocked. High effort. Depends on Apple binaries, and Asahi's direction there isn't public.
5. **Hypervisor-trace macOS on T6050** to watch how XNU starts PMP and releases cores. This is the classic Asahi method, and `pmp_init.py` came from exactly that.
   - It needs m1n1's SPTM/M5 hypervisor (#698, #737–#758; T8142 so far, T6050 untested). betizzel reports the T6050 guest boot dies at a GXF/`AVNCR_EL2` wall; their m1n1 patch `0006` addresses part of it.
   - **This must be done and interpreted by the owner, by hand,** if any of it is meant for Asahi: the LLM policy explicitly gives "a first and final warning" for LLM-interpreted hypervisor traces.
   - High effort, the highest information value, and the clean-room-compatible route.

## Suggested next tasks
- **Read-only, no MacBook risk:** a `--full` ADT dump plus the IOService plane for `pmp0`, `mtp` and `pmgr`. Fix the dump script's `-n` lookup bug while at it.
- **After 03A works:** probe plan for (2), plus a direct question to edimoldovan, birkskyum and betizzel in #293 (the owner posts). Our J714s would be the second T6050 data point on PMP access.
