# Installer integration and release contract

Our deliverable is a normal Omarchy installation on explicitly qualified Apple Silicon Macs. We collect demonstrated public work, integrate it into the existing [Omarchy Mac Installer](https://github.com/omacom/omarchy-mac-installer), test the complete installed system, and expand support through releases. New hardware research is outside this workstream.

**No M5 installer release is qualified here yet.** The [canonical status ledger](STATUS-2026-11-08.md#full-laptop-integration-checklist) remains the source of native hardware evidence. This document tracks release admission, not another experiment log.

## Reuse the existing installer

The existing installer already has a macOS UI, pinned installation engine, signed catalogs, verified downloads, disk-layout-bound plans, Recovery enrollment and removal/recovery flows. Its image builder also carries the standard Limine/EFI UKI packaging and validation path. Retain those facilities and trust checks; the missing work is model-specific integration and qualification, not inventing signing or kernel packaging. Contribute the required integration rather than creating a competing partitioner or asking users to assemble research scripts.

The audited installer snapshot is [0fe0d903](https://github.com/omacom/omarchy-mac-installer/tree/0fe0d90378158b954526231423ff2c35ebbcd080). Its catalog policy requires all 35 legacy boards in a nonempty catalog and blocks M4+. Model-specific releases therefore need an explicitly reviewed catalog/engine contract before adding a qualified new board. Removing a host restriction or adding a model name is not hardware support.

## Model admission

| State | Meaning |
|---|---|
| Candidate | Public implementation or native research result exists; installation is not offered. |
| Qualification | A pinned stack is undergoing complete install, boot, update and recovery checks on the exact board/firmware combination. |
| Supported release | A published release passed its declared installation and hardware requirements on that combination; limitations are shown before installation. |

J714s / Mac17,9 / T6050 is a **candidate**: 15 CPUs, native GPU rendering, scoped RAM/storage checks and a bounded Wi-Fi connection are demonstrated. These results span recorded profiles. They do not prove a clean installation of one combined release. Other M4/M5 models remain candidates until their own evidence is recorded; a J714c or J716s result cannot qualify J714s, or vice versa. Existing installer-supported models keep their upstream status; this project does not re-certify them merely by listing them.

Each admitted profile records exact board identifiers, firmware/build range, source revisions and patch order, configuration, artifact sizes/digests, test evidence and a known-good recovery target. A family name such as “M5” is insufficient.

## One coherent release

Ship or reference a matched set: installer/engine, enrolled loader contract and stage2, kernel, DTBs, initramfs, exact-release modules, root filesystem and compatible Mesa/session integration. Build these from pinned sources with attribution and per-file licenses. Resolve license mismatches before redistribution: a top-level MIT claim does not override a derivative file’s GPL header, and a source repository with no general license is not blanket permission to redistribute its contents. The current published N1 delta has an explicit missing-baseline limit; its hashes alone are not a reproducible release.

Obtain Apple firmware through the installer's legitimate preparation/download path. Keep proprietary inputs, tickets and user credentials private; publish preparation code and provenance, not private firmware blobs or secret-bearing logs. Validate target identities and artifact integrity before use.

The default user flow must finish installation, Recovery authorization and a normal graphical login without a proxy connection, developer terminal, manual patch application, test-kernel selection or copied credentials. Explain the unavoidable Recovery step in the app. Updates must preserve a bootable prior component set and a documented macOS recovery path. Do not promise an automatic pre-Linux fallback until it has been tested.

## First-release gates

- [ ] Agree on the target installer fork/upstream contribution path and qualify model-specific catalogs without weakening signature, disk-plan or host-identity checks.
- [ ] Publish complete build inputs and a matched artifact manifest; build in CI and verify a clean rebuild rather than relying on private accumulated worktrees.
- [ ] Install to a clean supported layout through the app and Recovery flow, then reach the normal user desktop with matching modules and automatic GPU/session selection.
- [ ] Verify repeated normal startup and shutdown, restart, macOS selection and Recovery access. The J714s cold-picker boot works, but a warm next-only attempt returned to macOS and restricted-profile physical poweroff is unresolved.
- [ ] Integrate ordinary Wi-Fi authentication and verify saved-network reconnection after restart. The current equivalent-PMK workaround passed bounded traffic; a driver fix and general reconnect behavior are unqualified.
- [ ] Qualify built-in keyboard/trackpad operation on the combined release, battery/charger reporting and safe normal CPU/thermal policy. Preserve the successful CPU/RAM/storage evidence; repeat only when the integrated stack changes relevant behavior.
- [ ] Declare and test display controls, lid/sleep/wake, audio, Bluetooth and external-device support. Any intentionally deferred feature must be visible before install; missing safe basic laptop operation blocks an ordinary-use laptop release.
- [ ] Exercise interrupted downloads, refused unsupported models/firmware, failed enrollment, update rollback and removal without damaging macOS or user data. Scrub support logs and keep credentials out of diagnostics.

## Concrete upstream candidates

Edimoldovan reports a J714c chain using stage1 → stage2 through asahi-scripts → U-Boot → Limine → EFI kernel packages, with ANS handoff changes and an SMC poweroff fix ([reported integration](https://github.com/omacom/linux-aurora/issues/293#issuecomment-6712674405)). Review and reuse this ordinary boot/package route before inventing another loader flow. It is another machine’s integration evidence, not a J714s qualification result. Pin the actual loader, U-Boot and kernel revisions in the selected profile before building or promoting it.

## Integration order

1. Audit the existing installer and source contributions; select the smallest exact model/firmware target with sufficient evidence.
2. Package its demonstrated stack and close installer integration gaps. Upstream useful isolated changes with original authors credited.
3. Qualify the complete installed release and recovery/update paths. Publish support only after those checks pass.
4. Watch upstream for proven improvements, pin each candidate, review compatibility, and rerun only affected qualification. Promote additional profiles through the same gates.

Record component adoption and native outcomes in the canonical ledger and release evidence. Keep exploratory scripts and historical diagnostics outside the normal installation flow. A release's support matrix must describe what the installed system actually does, not everything a source branch contains.
