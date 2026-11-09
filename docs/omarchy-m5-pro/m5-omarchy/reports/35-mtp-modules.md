# 35 — MTP experiments as modules (t02 + t03/t04/t05 ready; VM: mechanics only; NATIVE pending)

**Ready:** `~/m5-omarchy/loop/t02`, `t03`, `t04`, `t05` (each `m5drop/`), described in `tools/loop/README.md` (= `loop/README.md`). Module `m5_mtp.ko` sha256 `ba5f9dd90abca3312e6e2e741b7068a6e062afcc7e6036997ad18b1b258a1260`, vermagic `7.2.2-m5slim+ SMP preempt mod_unload aarch64`. That exact string is in the gz15 loop-v1 Image (`strings`).

## How it was built (no change to the gz15 kernel)
- `build/linux-loop` had no `Module.symvers` (`vmlinux.symvers` only; there are no in-tree modules and MODVERSIONS is off) and no `scripts/module.lds`.
- I copied `vmlinux.symvers` to `Module.symvers` and ran `make modules_prepare` (it only produced `scripts/module.lds`). The Image is still `0c511a53…` afterwards.
- `make M=tools/loop/mtp-mod modules`, then `modinfo`.

## The experiments (sources)
| Set | What | Source for the registers |
|---|---|---|
| t02 | read-only dump (DART PARAMS/ERROR/PROTECT/tunable offsets/ENABLE_STREAMS/TCR/TTBR; mailbox CONTROL; ASC 0x40–0x4c; wrapper, DAPF, PS_PROT first words), stock re-probe, dump again | `drivers/iommu/apple-dart.c` T8110 defines (l.99–154); `drivers/soc/apple/mailbox.c` (CONTROL 0x110/0x114; **RECV registers are never read**, a read dequeues); `rtkit-helper.c` (CPU_CONTROL 0x44); ADT reg windows (report 31) |
| t03 | `TCR \|= BYPASS_DAPF` on sids 0–4 | apple-dart.c `DART_T8110_TCR_BYPASS_DAPF BIT(2)` (l.147); Linux uses it only in `.tcr_bypass` (l.1682), i.e. not in translate mode |
| t04 | ADT `dart-tunables-instance-0` | ADT dump (decode in the README); semantics from `drivers/soc/apple/tunable.c` `apple_tunable_apply()` |
| t05 | t04 + t03 | — |

Every write is logged with old value, new value and readback. Every read logs its address first.

## VM proof (mechanics)
`PAYLOAD=loop/t02/m5drop tools/vmtest/guard-vm.sh t02`: the loop initramfs's `m5-drop` copied the set, sddm's drop-in pulled in `m5-exp.service`, and `m5log/exp-t02-<boot>.txt` appeared on the ESP with the runner log and dmesg. The module loaded and logged `rd 0x294800000` before the expected external abort (nothing at that address in QEMU), so the readout identifies the address of a fatal access.

## For the PM
- Push one set at a time, **merged** with the existing guard + watchdog drop-ins.
- Read `m5log/exp-tNN-<boot>.txt`. For t02, the register values decide whether t03/t04 are worth booting (README "Decides").
- If t02 dies at a window, its last `m5mtp: rd 0x…` line names the address, and later windows weren't read.
