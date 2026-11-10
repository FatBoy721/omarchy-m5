# J714s installer integration (from TripleU613/omarchy-mac-installer)

TripleU613's fork of the Omarchy Mac installer existed only to carry the J714s
normal-system image work. It now lives here; the fork is deleted.

## `patches/`: the installer work

Eight commits on top of
[omacom/omarchy-mac-installer `c07e54c2134a`](https://github.com/omacom/omarchy-mac-installer/commit/c07e54c2134a8ec1415e7e2b917589ae1d3d7dc9).
Applying them reproduces the fork's final `main` tree exactly (`b3da2a18094e`).

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
| 0007 | J714s kernel `CONFIG_DM_INTEGRITY=m` and optional Neo `mt7932-fullmac` in `aurora-vendor-order`: `mkinitcpio -P` finishes |
| 0008 | keep pacman's reason in `precheck.log` when the package precheck fails |

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
