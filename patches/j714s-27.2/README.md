# J714s on the macOS 27.2 stub (one image line)

Kernel and Aura for the one J714s (14" MacBook Pro, M5 Pro, T6050) Omarchy image on Apple's
non-beta firmware 27.2: restore image `UniversalMac_27.2_26B123_Restore.ipsw` (sha256
`6613b34e...8534f`), J714s boot firmware `mBoot-20457.41.3`. Stage 1 is Aura as a padded Mach-O
boot object with no `__TEXT_BOOT_EXEC` (`kcbz` 0, so iBoot does not start SPTM), enrolled with
`kmutil configure-boot --compress` after `bputil -nc`; Linux runs at EL2 on every CPU inside the
128 MiB code-execute window, as aurora-silicon targets 27.2 (`docs/move-to-27.2.md`).

Status (2026-11-13): **builds, not booted.** No J714s has run a 27.2 stub yet. The kernel also
keeps every 27.3 beta 1 row, so it can be RAM-tested on today's 27.3 setup first (Phase 1 R2 of
`docs/move-to-27.2.md`).

Recipes: [`installer/recipes/linux-aurora-j714s`](../../installer/recipes/linux-aurora-j714s)
(`linux-j714s-27.2.patch` is `linux/*.patch` concatenated) and
[`installer/recipes/m1n1-aurora-j714s`](../../installer/recipes/m1n1-aurora-j714s)
(`aura-j714s-27.2.patch` is `aura/*.patch` concatenated).

## Bases

- **Kernel:** aurora-silicon/linux `integration/aurora` at `572eb88e8642` (2026-11-13). Already
  merged there and so in the image: DjDeveloperr's display ADMAC and firmware 27 DisplayPort audio
  (#1748, #1749) and the J714s dcpext0 DP audio node (#1750); the J714s Secure Enclave (#1325);
  CLPC floors and sampling (#1324, #1555, #1556) and platform profiles (#1655, #1656); the T6050
  CPU PMU (#1628); JPEG encode (#1675); ProRes (#1586; no T6050 init rows public, so it stays
  unused); the MagSafe PD controller (#1686); USB4 and external displays (#1515 and follow-ups);
  the SEP pnon digest and trusted-accessory service (#1720, #1734); joshuaswarren's GPU mailbox
  polling (#1601); erikwb's #1608/#1609.
- **Aura:** aurora-silicon/aura `main` at `2232ae7a` (2026-11-13). Includes DjDeveloperr's display
  ADMAC tunables for DP audio (#207), sithglan's chainload copy stub (#186), the MTE tag store
  (#184), the M5 Pro boot path (#173), `firmware: add macOS 27.2` (d05ed948) and the ANE/AVE
  hand-offs (#169, #171).

## Kernel patches (`linux/`, apply in order with `git am` or `patch -Np1`)

| # | What | Whose |
| --- | --- | --- |
| 0001 | GPU InitData and firmware identity for 27.2 (26B123) and 27.3 (26C5035r), aurora-silicon/linux #1173 (open), resolved against the Graph refactor. The 26B123 fwid digest `2b4613c6...913f0fd9` was re-derived from the IPSW (below) | Rolando Trevino (rolotrealanis98) |
| 0002-0004 | Firmware 27 adaptive-sync parameter name; no panel brightness after a DCP crash; the full 27.3 IOMFB method table and swap record (only used on a 27.3 stub; 27.2 uses upstream's `dcp_methods_27_2`) | Rolando Trevino |
| 0005 | The K114/K116 27.2 (26B8125) G17S identity, #1650 (open) | Jens Axboe (via sithglan) |
| 0006-0007 | T6050 at EL2: vGIC SEIS treated as broken, WFxT treated as absent, #1724 (open). Needed once Linux runs at EL2 under the Mach-O Stage 1 | Jens Axboe (via sithglan) |
| 0008 | ANE and AVE on 27.3, ported onto the new AVE probe (`fw_data_size_alt`); builds may share sizes, so the AVE TEXT CRC selects the build | this repo (was upstream-27.3/0004) |
| 0009-0015 | Front camera: IMX958 setfile 2226_02, noise reduction gains, lens shading target and metering, camera light, J714s presets (omacom/linux-aurora #422) | Eduard Moldovan (edimoldovan); J714s DT by this repo |
| 0016 | VRR on the firmware 27 panel, opt-in `appledrm.fw27_panel_vrr=1` (j716s-next 8ab10100a4) | Rolando Trevino |
| 0017 | appledrm soft-depends on `atc-t6050-dp`, so dcpext0/2 find their route PHYs | this repo (was upstream-27.3/0009) |
| 0018 | ANE and AVE on 27.2 (26B123): layouts from the IPSW. ANE: 27.2 layout recognised, refused until its TEXT pin is known, and the refusal prints the digest. AVE: 26B123 admitted, probe only unless `apple_ave.ave_t6050_27_2_layout=1` | this repo |

`patch -Np1` of `linux-j714s-27.2.patch` on the `572eb88e` GitHub tarball (sha256
`260acb56...2b31ec`) gives the tree that was built (ush `~/m5-build/up272-1/src`, branch
`up-2721`). Config: unchanged from `linux-aurora-upstream` (`olddefconfig` adds nothing);
`j714s-required.config` now also requires `ARM64_CTXR_EXECMEM`, `APPLE_ADMAC` and
`SND_SOC_APPLE_T8152_AOP_AUDIO`.

## Aura patches (`aura/`, `git am` on main 2232ae7a)

| # | What | Whose |
| --- | --- | --- |
| 0001 | T6050 GPU hand-off: a build table (27.0, 27.2 26B123, 27.3 beta 1); DCP hand-off on 27.3 beta 1 with compat `<27 3 0>` | this repo, values from #1173 (Rolando Trevino) |
| 0002 | Notch rows shown by default on M5 (`chosen.asahi,show-notch=0` opts out) | this repo, after FatBoy721/edimoldovan's m1n1 work |
| 0003 | The M5 Max 27.3 G17S digest (aura #172) | joshuaswarren |
| 0004 | The T6050 camera table and the K116s 27.2 row (aura #188, open) | Jens Axboe, ported by Thomas Glanzmann |
| 0005 | J714s camera on 27.3 beta 1 | this repo |
| 0006 | T6050 GP PCIe: the auto-PM storage domain may gate itself (lost Wi-Fi, early hangs) | this repo |
| 0007 | The K116s 27.2 (26B8125) G17S digest (aura #187, open), carried onto 0001's table | Thomas Glanzmann, from Jens Axboe's #1650 |
| 0008 | **Internal display on 27.2:** admit `V27_2`, publish compat `<27 2 0>` (the kernel's `dcp_methods_27_2` key), pin the 27.2 DCP image `C51FB0C8-C45D-39B0-85BC-520E600FC950` | this repo |
| 0009 | **J714s camera on 27.2:** sensor 0x74, the IPSW's ISP segments | this repo |

The recipe also packages the Stage 1 tooling: `aura-j714s-stage1 --esp-partuuid UUID OUT` fills
the raw Stage 1 in place (Aura's `fill_stage1_config.py`, Stage 2 `m1n1/boot-ctxr.bin` by default)
and pads it with `macho_boot_object.py --execute-window`. A test object gave `kcrz 153141248`,
the value the 2026-11-07 padded trial on this J714s enrolled with; `--unpadded` makes the
rollback object. Nothing enrolls anything.

## 27.2 values, from the IPSW

Read on ush from the J714s identity ("Customer Erase Install (IPSW)", ApChipID 0x6050, ApBoardID
0x08) of `UniversalMac_27.2_26B123_Restore.ipsw`, with `pyimg4` and a Mach-O parser. Each method
was first checked against 27.0 (26A428, range reads), where the answer is known.

| Piece | Manifest member | 27.2 value | Method check on 27.0 |
| --- | --- | --- | --- |
| GPU | `Firmware/agx/armfw_g17x.im4p` + `armfw1_g17x.im4p` | G17S images `6299EB93-B771-3834-89CB-05410554188F` (TEXT 0x50000) and `28166DD7-1246-3583-A4AE-4B7CFD146DE5` (TEXT 0x54000); fwid digest with #1173's boot-filled ranges zeroed: `2b4613c62a8a007f22a94101702c9ac6c4e90f2e123f3b36fbe6ffea913f0fd9` = #1173 and Aura 0001 | - |
| DCP | `Firmware/dcp/t605xdcp.im4p` | image UUID `C51FB0C8-C45D-39B0-85BC-520E600FC950` | 27.0's pinned `64863924-...` is the Mach-O at 0x10f8608; 27.2's at 0x1114608, and each UUID appears at the same five payload offsets |
| ANE | `Firmware/ane/h17_ane0_fw_hyperion_j71y.im4p` | TEXT 0xbc000, DATA 0x2b0000 (span 0x36c000) | sizes match 27.0's row; the file's TEXT sha256 (`d4a64be9...` on 27.0) is **not** the preloaded pin (`93ae3a37...`), so the 27.2 pin can't come from the IPSW |
| AVE | `Firmware/ave/AppleAVE2FW_H17D.im4p` | TEXT 0x158000 CRC32 `d33ed3b4`, DATA 0x134000 | 27.0 TEXT CRC `87279429` = the kernel's constant |
| ISP | `Firmware/isp_bni/adc-nyx-sc7x.im4p` | TEXT 0xc1c000, DATA 0x13d0000, uuid `889F5ADB-BDE7-3B93-A531-24587C4CF3D5` | 27.0 sizes = Aura's pinned sizes |

## What the first 27.2 boot must collect

Everything below is fail-closed until confirmed: a mismatch refuses that one device and the boot
goes on.

1. `/proc/device-tree/chosen/firmware-version` (or Aura's log) = `mBoot-20457.41.3`, and "All
   CPU(s) started at EL2" on 15 CPUs, `/chosen/aurora,ctxr-exec-window` present.
2. **ANE TEXT pin.** The driver logs `H17 ANE: preloaded TEXT sha256 <64 hex>` and refuses. Put
   it in `ane_t6050_text_pin_27_2` (0018), rebuild, check `READY` and `/dev/accel/accel0`. Also
   log the ADT `ane0` segment-ranges from Aura (expect TEXT 0xbc000 at DVA 0x10000000000).
3. **DCP UUID.** Aura logs `DCP image <uuid>, firmware-compat 27.2.0` when it hands over, or
   `DCP image <uuid> is not C51FB0C8-...` when it refuses (simpledrm). If refused, the logged UUID
   goes into 0008.
4. **GPU:** `GPU firmware build: 26B123 ... G17S`; the ADT `iop-gfx-nub`/`iop-gfx1-nub` `uuid`s
   should be `6299EB93-...` and `28166DD7-...`.
5. **Camera:** Aura's `isp0` sensor type (0x74) and segment-ranges (TEXT 0xc1c000, DATA
   0x13d0000, remap 0x10000000000 / 0x10000c1c000) and their physical addresses; `/dev/video0`
   streams. The IMX958 setfile still comes from macOS 27.3's `appleh16camerad`; whether it suits
   the 27.2 ISP firmware is untested.
6. **AVE:** `firmware build 26B123 (TEXT 0x158000 CRC d33ed3b4 ...)`, `probe only`. Then reboot
   with `apple_ave.ave_t6050_27_2_layout=1` and encode H.264 and HEVC (30 frames each, decode,
   PSNR) before making it the default.
7. **Wi-Fi port 0** (Aura's `storage after ...` lines), trackpad, NVMe, SError/Oops-free journal,
   and a reboot (`macsmc-reboot`; there is no PSCI reset under the window).

## Next re-pin

Merged upstream at 06:12 UTC on 2026-11-13, after both pins (572eb88e is 04:38 UTC, Aura 2232ae7a
is 02:07 UTC), so this series still carries them and the built packages stay as they are:
- aurora-silicon/linux #1745 (17903f58cab4) is kernel 0017 (the appledrm softdep): drop it.
- aurora-silicon/linux #1747 (e3acfff0d34f), the AVE 27.3 table: 0008's AVE half overlaps it.
  Rebase 0008 and 0018 onto it, keeping 0018's 26B123 row and CRC selection.
- aurora-silicon/aura #203 (e3c1075f4144) is Aura 0006 (the storage auto-PM fix): drop it.

## Packages (built 2026-11-13 on ush; the Mac was unreachable)

The kernel was cross-built on ush (`OMARCHY_CROSS_KERNEL=1`, kernel package only: the headers
package would carry x86 host tools; build it natively for headers). Aura is bare-metal, so its x86
build is the same code. The rest were built in an Arch Linux ARM container under qemu-user
(`ArchLinuxARM-aarch64-latest`, signature checked). Every `check()` passed. Files on ush in
`~/m5-build/pkg272/out/`. None of these has been installed or booted.

| Package | sha256 | Bytes |
| --- | --- | --- |
| `linux-aurora-7.3.0.aurora17.v272-1-aarch64.pkg.tar.zst` (`7.3.0-17.v272-1-ARCH`) | `7ed9869122af9ac70361a41521833fd495f8a98edbb1ee01a4c513bb03fa19e2` | 44157755 |
| `m1n1-aurora-1.6.1.aurora24.v272-1-aarch64.pkg.tar.zst` | `1f30e3fffb1b6a36cad8e5b91d4cd8b844a5ded50565c9f82ff2c3a420b094bf` | 2458500 |
| `speakerguardd-v2-1.0.0alpha.1-40.1-aarch64.pkg.tar.zst` (ships disabled) | `d8078f1a9bf9cf6370fb521770623940803c42bead95e346a1fb59c024929440` | 1751517 |
| `aurora-speaker-upgrade-0.1-15-any.pkg.tar.zst` (ships disabled) | `f63d4dcd1b50e51a6c4a373d0ace10b4b909308f23607204f4dc28d538ac4934` | 66114 |
| `aurora-sep-1.17.g8679514f4dff-1-any.pkg.tar.zst` (read-only: `xart_writes=0 provision_keybag=0`) | `6fa7ec892ea43462a5cbaa4d59bc5db224040c30ca342e0ef0a80d6be17f411c` | 72452 |
| `libfprint-aurora-1.94.100-1-aarch64.pkg.tar.zst` | `6f4c2ca4c795f66d0b700c935be6c6646d9b974d19e0a1e6b5d1235d710d8172` | 521161 |

aurora-sep stays at 8679514f: up to 572eb88e only its read-only status tool changed (two new
diag lines), and the SEP UAPI header is byte-identical (sep-bio 5, sep-key 4). The kernel keeps
the speakersafetyd hold for the J714s, so the speakers stay silent until speakerguardd v2 is
switched on with this Mac's tuning.


## Upstream since the pins (2026-11-13)

- Merged: aurora-silicon/linux #1724 (Jens Axboe's T6050 EL2 errata), our 0006–0007; drop them at the next re-pin. Also #1745 and #1747 (our 0017, 0008 part) and aura #203 (our Aura 0006), plus aura #213 (post-M4 ANS started for the payload) and aura #206 (K114c camera).
- Reference for HDMI: aurora-silicon/linux #1565 (J575c HDMI, 7robertodantas) is the first merged Apple Silicon HDMI path in this tree. The J714s HDMI port (`atc3-dpphy`, `dp2hdmi-gpio0`) still needs a DT port.
- Also merged after the pins (take at the next re-pin): #1791 J714s left-front USB-C USB4/Thunderbolt router (DjDeveloperr; the right port already had one), #1835 J714s camera sizes from sensor config 6 (DjDeveloperr; compare with our edimoldovan presets 0009–0015), #1763 SEP sse/skdl/hibe, #1610 GPU GEM residency (erikwb), #1634 tiled 5K displays (joshuaswarren), aura #187 (drop our Aura 0007) and aura #188 camera table (drop our Aura 0004). DjDeveloperr's J714s deep-sleep series #1772–#1785 was closed for rework.
