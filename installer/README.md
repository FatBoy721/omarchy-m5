# J714s installer integration (from TripleU613/omarchy-mac-installer)

TripleU613's fork of the Omarchy Mac installer existed only to carry the J714s
normal-system image work. It now lives here; the fork is deleted.

## `patches/`: the installer work

Six commits on top of
[omacom/omarchy-mac-installer `c07e54c2134a`](https://github.com/omacom/omarchy-mac-installer/commit/c07e54c2134a8ec1415e7e2b917589ae1d3d7dc9).
0001-0006 reproduce the fork's final `main` tree exactly (`b3da2a18094e`); with 0007-0010 the tree is `8d8403e67730`.

```sh
git clone https://github.com/omacom/omarchy-mac-installer && cd omarchy-mac-installer
git checkout -b j714s c07e54c2134a8ec1415e7e2b917589ae1d3d7dc9
git am /path/to/omarchy-m5/installer/patches/*.patch
```

| # | What |
| --- | --- |
| 0001 | `Integration/M5/J714s-Normal-System/`: kernel/m1n1 freezes, 15-package candidate manifest, recipes, provenance; `SOURCES.md` contributor inventory |
| 0002 | `j714s-developer` image profile and the manual ARM CI image workflow |
| 0003 | developer image uses the verified `arm-mirror.omarchy.org` ALARM mirror |
| 0004 | select the image profile after the builder installs Python |
| 0005 | native J714s kernel headers build check (not run yet) |
| 0006 | resolve Omarchy desktop packages against matching pinned versions |
| 0007 | merged kernel, loader 0002-0004 and firmware-hook packages from [`recipes/`](recipes); new developer signer `0DA040FF…B6D116B1`; the merged kernel's verified boot arguments |
| 0008 | kernel pkgrel 2 (aurora-n1 0009: the t6050 NVMe compatible U-Boot needs) and the gcc-built `uboot-aurora` (the cross build's arm64 `image_size` was refused by m1n1) |
| 0009 | one image for every J714s: kernel pkgrel 3 (aurora-n1 0010, default DTB `t6050-j714s-gpu-adt-simpledrm.dtb`: GPU voltage bins from the ADT) and m1n1-aurora `j714s4` (m1n1-installer 0005 passes them) |
| 0010 | speakers, microphones, headphone jack and an always-on trackpad: kernel pkgrel 4 (aurora-n1 0011-0012, AOP audio drivers) and `omarchy-aurora-firmware` `j714s3` (edimoldovan's J714 speaker-safety profile and graphs) |
| 0011 | lid sleep, quiet idle clocks, N1 6 GHz: kernel pkgrel 5 (aurora-n1 0013-0016 from FatBoy721 and rolotrealanis98, `UCLAMP_TASK`) and `omarchy-aurora-firmware` `j714s4` (edimoldovan's realtime uclamp sysctl and N1 iwd default) |
| 0012 | the internal display through the DCP by default at full panel height, GPU-rendered desktop: `m1n1-aurora` j714s5 (m1n1 0006-0007), kernel pkgrel 6 (DCP device tree), `omarchy-aurora-firmware` j714s5 (two-card Hyprland session) and the new `hyprland-m5` support package (the builder installs it in the hyprland role); `finish-inputs` counts the profile's roles instead of a fixed 15 |
| 0013 | speakers and jack in PipeWire: `omarchy-aurora-firmware` j714s6 (edimoldovan's J714 UCM profiles, kazuhidet's busy-card discovery) |
| 0014 | hardware video decode: kernel pkgrel 7 (aurora-n1 0017, DjDeveloperr's J714s decoder DT) and `omarchy-aurora-firmware` j714s7 (avd-fw v5-t2 built from source) |
| 0015 | FatBoy721's precheck log fix (keep pacman's reason when the package precheck fails; his PR #4 0008) |
| 0016 | lid angle and ambient light sensors: kernel pkgrel 8 (aurora-n1 0018, DjDeveloperr's AOP sensors) |
| 0017 | USB 2.0 host on USB-C ports 0 and 2: kernel pkgrel 9 (aurora-n1 0019-0023, edimoldovan's T6050 USB 2.0 host PHY) |
| 0018 | USB host on all three USB-C ports: kernel pkgrel 10 (aurora-n1 0024-0032, the rest of edimoldovan's USB series) |
| 0019 | updates keep the J714s packages: the image pin covers every package the set takes from this repo (kernel, m1n1, U-Boot, Mesa, Hyprland, firmware), found by the `update-check` workflow (edge's m1n1-aurora aurora23 would have replaced ours) |

The kernel and m1n1 in 0001 are the same sources as
[`patches/linux-aurora-installer`](../patches/linux-aurora-installer) and
[`patches/m1n1-installer`](../patches/m1n1-installer).

## Status when moved (2026-11-09)

The last CI image run (on 0004) got past the Python fix and failed with "the
package set does not resolve against the pinned databases"; 0006 targets that
and has not been built. No normal-chain (U-Boot/Limine) J714s boot yet. Native
kernel headers/DKMS are an open gap.

## `omarchy-pkgs/`: package recipe build records

The two build-record tags from TripleU613's omarchy-pkgs fork, each 3 commits
on omacom/omarchy-pkgs `master` `30a33ee435db`: the native ARM Mesa candidate
build and the exact runtime-pair (kernel + loader) candidate recipes.

## Build inputs release

The CI-built J714s packages (linux-aurora 7.3.0.aurora15.j714s2, m1n1-aurora,
uboot-aurora, mesa/vulkan-aurora, firmware) plus the pinned omacom packages are
in this repo's release
[`installer-build-inputs-j714s-76004483a972`](https://github.com/betizzel/omarchy-m5/releases/tag/installer-build-inputs-j714s-76004483a972)
(bundle sha256 `76004483a9722fb5...`, with its provenance JSON). Build inputs
only, not an installer release.

## Image build (2026-11-10)

`.github/workflows/installer-image.yml` (manual dispatch) rebuilds the tree
above and builds the image from the bundle in release
[`installer-build-inputs-j714s-1d32202bb6f2`](https://github.com/betizzel/omarchy-m5/releases/tag/installer-build-inputs-j714s-1d32202bb6f2).
The old bundle (`76004483a972`, freeze kernel) got through package resolution
with 0006 and failed in mkinitcpio (`dm_integrity`, `mt7932-fullmac` missing);
0007 and the recipes fix both. Its signing key did not survive the fork, so
0007 replaces it; the new key's private half is kept off the repo.

**Result:** run [42883681094](https://github.com/betizzel/omarchy-m5/actions/runs/42883681094)
built `omarchy-2026.11.10-aarch64-apple-silicon-mac-edge-os-package.zip`
(3.6 GB; root.img 12.9 GB) and its `installer_data.json` for device class
`j714sap`; the image inspection and payload contract checks passed. It is a
CI artifact (kept 7 days), not a release, and has **not been installed on
hardware yet**. Next: install it on a J714s (normal m1n1 → U-Boot → Limine →
EFI Linux chain), then first boot, Wi-Fi, encryption prompt input.

**Boot-chain findings (m1n1 HV, before any disk write):** the first image's
`boot.bin` stopped in m1n1 (`Assertion failed: 'size <= kernel->image_size'`,
the U-Boot payload) and, with that fixed, U-Boot found no NVMe (merged tree's
`apple,t8140-nvme-ans2` only). 0008 fixes both; with them U-Boot reads the
J714s GPT under the HV.
