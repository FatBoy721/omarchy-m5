# m5boot: independent boot object for the M5 Pro MacBook Pro (J714s / T6050)

You are the **implementer** of m5boot, a minimal raw boot object that Apple's iBoot launches (`kmutil configure-boot --raw`) to boot Linux directly on this Mac. It's part of an independent Omarchy port, **not** an Asahi contribution.

## Clean-room rules (hard)
- **Never** read, fetch, or search m1n1 or anything derived from it: AsahiLinux/m1n1, aurora-silicon/aura or m1n1, edimoldovan/m1n1, omacom/m1n1, betizzel's m1n1 patches. Also don't read `~/m5-omarchy/` (it contains m1n1 analysis), except the files explicitly copied into `spec/` here and the build artifacts listed in `spec/inputs.md`.
- Allowed sources only:
  - Apple XNU open source (APSL)
  - the AsahiLinux/docs repo
  - Linux kernel sources and docs
  - libfdt (dtc)
  - the spec in `spec/`

  Check each source's license and AI instructions before use, and cite each one in `NOTES.md`.
- If a fact you need isn't in an allowed source or the spec, mark it **HYPOTHESIS** with the runtime check that settles it. Never guess silently.

## Hardware-safety rules (hard)
m5boot writes only: the watchdog-disable register, its own RAM, and the framebuffer. No PMGR/clock/power, SMC, NVMe/storage, or NVRAM writes.

## Workflow
- Tasks arrive as `tasks/NN-*.md` from the PM. Write `NOTES.md` (design + sources) and code under `src/`. Commit often.
- Finish each task with `DONE NN`, or `BLOCKED NN: <need>`. Don't ask questions mid-task unless truly blocked. Pick the conservative option and record it.
- Model: Opus 5.5, effort low (owner rule).

- Never open interactive question dialogs. Write BLOCKED NN: <question> instead and stop.
