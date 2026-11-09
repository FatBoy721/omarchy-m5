# 31 — MTP firmware memory: where iBoot puts it, and DTB I3 (built; NATIVE pending)

Correction recorded in report 30: in gz14 the MTP CPU was **stopped** at hand-off, not running.

## 1. ADT facts (our dump, `reports/04-j714s-full.txt`; MTP ASC, nub, DART, mapper)
| Node | Property | Value |
|---|---|---|
| `mtp@94600000` (`iop,ascwrap-v6`, role MTP) | reg | ASC 0x294600000 +0x88000; wrapper 0x294050000 +0x4000 |
| | `segment-names` | `__TEXT;__DATA;__OS_LOG` |
| | `segment-ranges` | 3 entries, below |
| | `iommu-parent` | → `mapper-mtp` (`iommu-mapper`, reg 0) |
| | `clock-gates`, `power-gates`, `clock-ids` | **empty**: no PMGR domain |
| `iop-mtp-nub` (`iop-nub,rtbuddy-v2`) | `pre-loaded` | 1 |
| | `segment-ranges` | identical to the ASC's |
| | other | `no-firmware-service`, `watchdog-enable`, `coredump-enable` 0x40, `cold-boot-after-hibernate`, `sleep-on-hibernate` |
| `dart-mtp` (`dart,t8110`) | reg | DART 0x294800000 +0xc000, **DAPF 0x294810000** +0x4000, PS_PROT 0x2890fc000 +0x4000 |
| | other | `vm-base` 0x100_0000_4000, `vm-size` 0xffff_0000, `dart-tunables-instance-0`, `dapf-instance-0` |

**`segment-ranges` decode** (96 bytes = 3 × 32: `{u64 phys, u64 iova, u64 remap, u32 size, u32 flags}`). [HYPOTHESIS] Field order inferred; it's self-consistent: sizes are contiguous, TEXT+DATA tile the SRAM exactly, `remap` = phys, and the count matches `segment-names`. No public Linux/Asahi doc for the layout was found; the Asahi kernel in our tree doesn't parse `segment-ranges`. So treat this as our decode.

| Segment | phys | IOP address (iova) | size | flags | Where |
|---|---|---|---|---|---|
| __TEXT | 0x294c00000 | 0x1000000 | 0x54000 | 0x3 | MTP SRAM (MMIO space) |
| __DATA | 0x294c54000 | 0x1054000 | 0x6c000 | 0x2 | MTP SRAM |
| __OS_LOG | **0x1000ccdc000** | 0x10c0000 | 0x3000 | 0xa | DRAM |

## 2. Overlap with what m5boot places / Linux allocates (NATIVE gz14 dmesg)
- **TEXT/DATA are SRAM, not RAM**, so no Linux allocation or m5boot placement can touch them. m5boot places kernel/FDT/initrd around 0x100_72c0_0000.
- **OS_LOG 0x1000ccdc000–0x1000ccdeffff lies inside `m5boot-rsv171` (0x100_0400_0000–0x100_23ff_ffff, no-map)**, one of m5boot's carveout reservations. Linux never used it.
- **So neither m5boot nor Linux overwrote the preloaded firmware.** m5boot doesn't have to add a reservation for it. Recommended for m5boot (inputs.md § Input v3): verify the runtime ADT `segment-ranges` against I3's static values.
- **What Linux does change:** `apple-dart` resets the MTP DART at probe (gz14: "DART … locked: 0 initialized") and gives the MTP an empty domain. Any IOVA the firmware uses through the DART is unmapped from then on.
  - The three IOP addresses (0x1000000–0x10c3000) are far below the DART window (`vm-base` 0x100_0000_4000). [HYPOTHESIS] They're IOP-local through the ASC's own remap (`remap` field), so the DART may not even be on their path. I3 maps them anyway, which is harmless if unused.

## 3. DTB I3 (`tools/kernel/dts/t6050-j714s-m5-I3.dtsi`)
- `/reserved-memory`: `mtp-text@294c00000`, `mtp-data@294c54000`, `mtp-oslog@1000ccdc000`. Each has `reg` = phys, `no-map`, and `iommu-addresses = <&mtp iova size>` (upstream reserved-memory binding, as referenced in `drivers/iommu/of_iommu.c`).
- `&mtp`: `memory-region` = those three.
- **Consumed by:** `of_iommu_get_resv_regions()` (`drivers/iommu/of_iommu.c`, called via `iommu_dma_get_resv_regions()` from `apple_dart_get_resv_regions()`, `drivers/iommu/apple-dart.c:1290`). Phys ≠ iova gives `IOMMU_RESV_TRANSLATED` (`iommu_resv_region_get_type()`). `iommu_create_device_direct_mappings()` maps those into the MTP's DART domain when the default domain is set up (`drivers/iommu/iommu.c` ~l.1223). The firmware IOVAs then resolve to the preloaded segments after the DART reset.
- OS_LOG overlaps m5boot-rsv171. Linux only warns about overlapping reserved-memory entries; both are no-map.
- **What I3 does NOT do:** program DAPF or apply `dart-tunables-instance-0` (no allowed layout source, reports 24/28), or reset the IOP via PMGR (the MTP has none).
- **Next native readout:**
  - success: "RTKit booted" plus keyboards in `rootfs-*-input.txt`;
  - same -62: the firmware doesn't start at all. Then DAPF/tunables or an IOP start parameter (`no-firmware-service` / wrapper registers at 0x294050000) become the suspects.

## Deliverables (new filenames; hashes in `~/m5boot/spec/inputs.md` § Input v3)
`build/input-v3/t6050-j714s-I3.dtb`, plus `build/input-v3/Image(.gz)` (identical to input-v2). Initramfs r28a and rootfs v3 unchanged.
