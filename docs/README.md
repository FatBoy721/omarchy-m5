# Docs index

Where everything is. **New here? Read [`../FOR-AURORA.md`](../FOR-AURORA.md)
first** - the curated front door (the three things worth your time, and what to
skip). This index is the fuller map.

## SMP (resolved 2026-11-06)

- Fixed by Apple's mBoot in macOS 27.3 beta 1: rebuild the stub
  ([`bringup.md` -> Stub firmware refresh](bringup.md#stub-firmware-refresh-all-cores));
  the kernel needs patches 0009 and 0010. Summary in the root
  [`README.md`](../README.md#smp-fixed-by-apples-firmware).
- **[`smp-t6050-findings.md`](smp-t6050-findings.md)** - the pre-fix
  investigation: hardware measurements of the failed starts and the theories
  disproven on hardware (locked RVBAR, iBoot WFI sled, CTRR/CTXR
  execute-regions). Its SPTM attribution does not explain the failure; the
  hv-trace autopsy in the lower half is optional.
- Supporting evidence: [`../scripts/probes/`](../scripts/probes/) (probe
  scripts), [`../patches/m1n1/`](../patches/m1n1/) (bootloader changes), and
  [`research/probe-logs/`](research/probe-logs/) (raw captures).

## Build & install

- **[`bringup.md`](bringup.md)** - the tethered dev loop (`make` targets, macOS
  quirks) and the **one-time on-device install** (partitioning + `kmutil`),
  including resize / re-install.

## Background / planning

- **[`PLAN.md`](PLAN.md)** (2026-09-21) - the original phased plan and Phase-0
  findings. Historical framing; current status lives in the root
  [`README.md`](../README.md).
- **[`research/`](research/)** - four Phase-0 deep-dives (`kernel-boot-m5.md`,
  `m5-pro-hardware-matrix.md`, `omarchy-arm-ecosystem.md`,
  `dualboot-partitioning.md`), plus `research/probe-logs/` and
  `research/smc-keys-j714s.json`. Broad context; skim as needed.
