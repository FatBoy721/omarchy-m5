# Native J714s N1 integration: frozen source handoff

These are the exact source deltas/config used by the tested N1 integration; no firmware, ticket, device log, credentials, SSID or binary is included. Native connectivity and the saved equivalent-PMK workaround are recorded in the [canonical status](../../../STATUS-2026-11-08.md#native-n1-integration-2026-11-09).

- `kernel-n1-integration.patch`: exact N1 difference from the recorded D415 integration, including reused public driver/binding changes, J714s host/PMGR/SMC adaptation and removal of inferred N1 firmware identity fields. The existing runtime-ADT identity fill is used instead. The AFE gate remains separate from the default-denied radio allowance.
- `loader-0028-rebased.patch`: public 0028 adapted beside existing protected loader changes, plus the J714s-required host-list shape/addition/window checks. No cached tunable array is embedded. The [focused 0029 contribution](https://github.com/TripleU613/m5pro-linux/tree/codex/j714s-n1-loader-admission/contrib/pending/wireless/j714s-host-list-admission) isolates the new admission hardening without reposting the public train.
- `n1.config`: final profile fragment; apply after the matching D415 config and resolve normally. The exact resolved-config hash and actual Image/DTB/S2 identities are in `SOURCE-BUILD-MANIFEST.json`.

## Baseline and reproducibility limit

The kernel delta is against the larger local D415 integration built on Linux `34f2f5bb4d03bbe3acce237cb67af8dc9972aa4a`. That baseline includes its recorded tracked patch plus additional platform/DT/GPU files; this directory does **not** republish the complete baseline. Therefore this is a useful reviewable adaptation handoff, **not a claim that applying this patch directly to that clean commit reproduces the tested image**. The manifest records the inherited tracked-patch hash so a different baseline cannot be mistaken for the tested one. The original working D415 and older rollback profiles were preserved.

The protected S2 base is `02785a35e046901d5686ab9059b2c08b6256752a` plus its existing local boot/storage/SMP/USB safeguards. Those inherited changes are also outside this delta. The actual S2 build retained `RELEASE=1 CHAINLOADING=1 ESP_STAGE2=1`, `MAX_CPUS=24` and `T6050_NO_HOST_PREP`; its raw payload start was measured as `0x390000`, not assumed from an older image. The separate storage-variable tail aligned to `0x394000`. No enrolled S1 change was required.

Public implementation provenance: rolotrealanis98/m5pro-linux [`f60c7be`](https://github.com/rolotrealanis98/m5pro-linux/tree/f60c7be55712f9f0e9abd95d72786fa4179cb292/contrib/pending/wireless), its `pr-kernel-train` nine-driver/two-DT series and loader 0028. Existing upstream authorship and per-file licences remain applicable: kernel changes follow the source files' GPL licensing and the m1n1 helper is MIT. This is public-source reuse, not clean-room work. No human sign-off is generated or asserted.

## Build, validation and operating boundary

The normal LLVM kernel Image.gz/DTB/modules and protected S2 builds exited 0. Image decompression/header/release, exact S2 ELF-to-binary bytes/linker windows and 1,646 matching in-tree modules were independently checked. Actual-helper ASan/UBSan tests and the existing production parser/storage/inflate harness passed positive and negative cases. This is distinct from the subsequent native PCIe/netdevice/connectivity evidence.

This profile permits new PMGR/PHY/PERST/DART/PCIe writes and a separately bounded gP13 off/on/conditional-off sequence; zero radio budget does not mean zero PMGR writes. Failed probe cleanup does not guarantee endpoint power-off. It is not safe to substitute another board's metadata, asset or register values. Firmware remains a legally supplied private rootfs input to the normal kernel firmware loader. No install, boot selection, power command, automatic retry or recovery guarantee is contained in this source handoff.
