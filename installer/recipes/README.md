# J714s developer image package recipes

Recipes for the three packages the J714s developer installer image takes from
this repo (the rest of its 15-package set is unchanged, see
[`../README.md`](../README.md)). They started as the prepared recipes of
omacom/omarchy-mac-installer `Integration/M5/J714s-Normal-System/prepare`
(omacom/omarchy-pkgs `30a33ee435db`) and differ as follows.

| Package | Version | Change |
| --- | --- | --- |
| `linux-aurora` | `7.3.0.aurora16.j714s3-1` | The merged kernel: rolotrealanis98/linux `34f2f5bb4d03` plus this repo's `patches/linux-aurora` and `patches/linux-aurora-n1` 0001-0008 as one diff (`j714s-merged-source.patch`, harness tree `6fd53e01a76b`). Config `configs/aurora-j714s-n1.config` as built, plus `DM_CRYPT=m` and `DM_INTEGRITY=m` (sd-encrypt). Release `7.3.0-16.j714s3-1-j714s-merged-ARCH`. Source is the GitHub tarball, so its sha256 is pinned. |
| `m1n1-aurora` | `1.6.1.aurora22.j714s3-1` | Adds `patches/m1n1-installer` 0002-0004 (3-cell AIC GPU mailboxes; DCP handoff phandles and firmware-compat) on the frozen loader. |
| `omarchy-aurora-firmware` | `20261014.j714s2-1` | `aop`, `aop_als` and `mt7932-fullmac` are optional in the `aurora-vendor-order` initcpio hook. The J714s has an N1, not the Neo's MT7932, and mkinitcpio failed on the missing module. |

**Unit device tree.** Boot loaders pick `t6050-j714s.dtb`, and the GPU voltage
bins are per chip, so `linux-aurora` installs one unit's tree under that name.
The default is TripleU613's (`t6050-j714s-gpu-tripleu-simpledrm.dtb`: N1 host,
GPU, simpledrm). For betizzel's unit, build with
`_j714s_unit_dtb=t6050-j714s-gpu-n1-simpledrm.dtb`. One image per unit until
the GPU driver picks its bins by fuse match.

Build natively on an aarch64 Arch Linux ARM host (clang 23, rustup) with
`PKGEXT=.pkg.tar.zst makepkg` (ALARM defaults to `.xz`, which the installer
refuses). m1n1's pinned commit is no longer on an omacom/m1n1 branch: fetch it
into the source mirror first
(`git --git-dir=m1n1 fetch origin 02785a35e046901d5686ab9059b2c08b6256752a`).
