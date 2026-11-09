# Consolidated upstream PRs (TripleU613)

These were open PRs / branches on separate forks. They now live here, and the
PRs and forks are closed. Each `.mbox` is the PR's full commit series
(`git am` against the listed base). Authorship inside each patch is preserved.

| File | Was | Base | What |
| --- | --- | --- | --- |
| `linux-aurora-414-j714s-board-dts.mbox` | omacom/linux-aurora#414 | `integration/aurora` `8eddf5aeb6ac` | J714s board DTS, stacked on rolotrealanis98's #413 (J716s T6050): 24 commits, includes the #413 stack |
| `m1n1-39-t6050-no-host-prep.mbox` | omacom/m1n1#39 | `integration/aurora` `7f6df96591b7` | `T6050_NO_HOST_PREP` build switch, stacked on edimoldovan's #30: 10 commits |
| `m1n1-40-max-cpus-override.mbox` | omacom/m1n1#40 | `integration/aurora` `7f6df96591b7` | build-time `MAX_CPUS` override (default 32) |
| `rolo-linux-1-j714s-g17s-gpu-profile.mbox` | rolotrealanis98/linux#1 | `pr/m5-gpu-27.2` `34f2f5bb4d03` | J714s G17S voltage profile + fuse-mask guard (functionally already in `patches/linux-aurora-installer`) |
| `m5pro-linux-1-e2-m1n1-sizes.mbox` | rolotrealanis98/m5pro-linux#1 | `main` `aca60e017768` | per-image m1n1 size check for Rolo's e2 GPU tooling |
| `m5pro-linux-2-j714s-distro-coverage.mbox` | rolotrealanis98/m5pro-linux#2 | `main` `aca60e017768` | J714s pass in `test-update-payload`, J714s evidence for GAPS #23 |
| `m5pro-linux-n1-loader-admission.mbox` | TripleU613/m5pro-linux branch (no PR) | `main` | require complete bounded J714s N1 host tunables |

Which of these the J714s installer flavor already carries:
[`docs/installer-stones.md`](../../docs/installer-stones.md).
