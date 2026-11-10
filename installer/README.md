# J714s installer integration (from TripleU613/omarchy-mac-installer)

TripleU613's fork of the Omarchy Mac installer existed only to carry the J714s
normal-system image work. It now lives here; the fork is deleted.

## `patches/`: the installer work

Six commits on top of
[omacom/omarchy-mac-installer `c07e54c2134a`](https://github.com/omacom/omarchy-mac-installer/commit/c07e54c2134a8ec1415e7e2b917589ae1d3d7dc9).
0001-0006 reproduce the fork's final `main` tree exactly (`b3da2a18094e`); with 0007 the tree is `990d586db85a`.

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
[`installer-build-inputs-j714s-213f90ca1b8c`](https://github.com/betizzel/omarchy-m5/releases/tag/installer-build-inputs-j714s-213f90ca1b8c).
The old bundle (`76004483a972`, freeze kernel) got through package resolution
with 0006 and failed in mkinitcpio (`dm_integrity`, `mt7932-fullmac` missing);
0007 and the recipes fix both. Its signing key did not survive the fork, so
0007 replaces it; the new key's private half is kept off the repo.
