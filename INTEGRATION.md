# Installer integration and release contract

Our deliverable is a normal Omarchy installation on explicitly qualified Apple Silicon Macs. We collect demonstrated public work, integrate it into the existing [Omarchy Mac Installer](https://github.com/omacom/omarchy-mac-installer), test the complete installed system, and expand support through releases. New hardware research is outside this workstream.

**No M5 installer release is qualified here yet.** The [canonical status ledger](STATUS-2026-11-08.md#full-laptop-integration-checklist) remains the source of native hardware evidence. This document tracks release admission, not another experiment log.

## Reuse the existing installer

The existing installer already has a macOS UI, pinned installation engine, signed catalogs, verified downloads, disk-layout-bound plans, Recovery enrollment and removal/recovery flows. Its image builder also carries the standard Limine/EFI UKI packaging and validation path. Retain those facilities and trust checks; the missing work is model-specific integration and qualification, not inventing signing or kernel packaging. Contribute the required integration rather than creating a competing partitioner or asking users to assemble research scripts.

The audited upstream installer snapshot is [c07e54c](https://github.com/omacom/omarchy-mac-installer/tree/c07e54c2134a8ec1415e7e2b917589ae1d3d7dc9). Its public catalog policy requires all 35 legacy boards in a nonempty catalog and blocks M4+. We reuse its existing sealed developer catalog mechanism for a separate J714s candidate payload, while keeping that public policy unchanged. Removing a host restriction or adding a model name is not hardware support.

## Published integration source

- [Installer branch](https://github.com/TripleU613/omarchy-mac-installer/tree/codex/m5-installer-integration), frozen at [`61bd334`](https://github.com/TripleU613/omarchy-mac-installer/commit/61bd3349b74eac454b55b0194a00b02da194e9e8): exact J714sap / T6050 / AP-board08 recognition and Apple 27.3 build26C5035r restore selection; private Centauri preparation through the normal vendor archive; board/firmware-bound common Stage1 metadata; matched first-UKI parameters; developer-only admission with generic-loader fallback refused. Default legacy image behavior and public support admission remain unchanged.
- [Package recipes at `bf09884`](https://github.com/TripleU613/omarchy-pkgs/commit/bf098840308602cd2d5a99fa8445353a3386290d): the matching J714s loader, kernel and Mesa source inputs. The runtime kernel archive has been built and its matching-module/crypto closure checked. [Mesa's ARM CI build passed](https://github.com/TripleU613/omarchy-pkgs/actions/runs/42649339647); archive readback and installation qualification remain separate. Native headers/DKMS remain unqualified. These recipes are not a published installable image.

The installer portable suite reported 836 tests, 31 skipped and zero failures. Focused image/profile checks and independent review also passed. Actual patched engine inspection/planning ran against read-only host fixtures; actual loader and runtime-kernel archive bytes passed their component checks. Fixture filesystems, source checks and package artifacts do not prove a physical install. The rebuilt engine archive is retained locally and its exact identity is in the source lock; no hosted installer release is claimed.

## Model admission

| State | Meaning |
|---|---|
| Candidate | Public implementation or native research result exists; no public installation is offered. |
| Qualification | A pinned stack is undergoing complete install, boot, update and recovery checks on the exact board/firmware combination. |
| Supported release | A published release passed its declared installation and hardware requirements on that combination; limitations are shown before installation. |

J714s / Mac17,9 / T6050 is a **candidate**: 15 CPUs, native GPU rendering, scoped RAM/storage checks and a bounded Wi-Fi connection are demonstrated. These results span recorded profiles. They do not prove a clean installation of one combined release. Other M4/M5 models remain candidates until their own evidence is recorded; a J714c or J716s result cannot qualify J714s, or vice versa. Existing installer-supported models keep their upstream status; this project does not re-certify them merely by listing them.

Each admitted profile records exact board identifiers, firmware/build range, source revisions and patch order, configuration, artifact sizes/digests, test evidence and a known-good recovery target. A family name such as “M5” is insufficient.

## One coherent release

Ship or reference a matched set: installer/engine, enrolled loader contract and stage2, kernel, DTBs, initramfs, exact-release modules, root filesystem and compatible Mesa/session integration. Build these from pinned sources with attribution and per-file licenses. Resolve license mismatches before redistribution: a top-level MIT claim does not override a derivative file’s GPL header, and a source repository with no general license is not blanket permission to redistribute its contents. The earlier research N1 delta has an explicit missing-baseline limit; its hashes alone are not a reproducible release.

Obtain Apple firmware through the installer's legitimate preparation/download path. Keep proprietary inputs, tickets and user credentials private; publish preparation code and provenance, not private firmware blobs or secret-bearing logs. Validate target identities and artifact integrity before use.

The default user flow must finish installation, Recovery authorization and a normal graphical login without a proxy connection, developer terminal, manual patch application, test-kernel selection or copied credentials. Explain the unavoidable Recovery step in the app. Updates must preserve a bootable prior component set and a documented macOS recovery path. Do not promise an automatic pre-Linux fallback until it has been tested.

## First-release gates

- [x] Reuse the existing installer and its developer model/payload route, with reviewed source in an owned fork and public admission unchanged.
- [ ] Qualify the exact model-specific release before public catalog admission, preserving signature, disk-plan and host-identity checks.
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

Adapt the existing installer acceptance runbook to the selected board before running it: its historical M1 Broadcom firmware and speaker-test steps are not M5 N1 or speaker-safety qualification. Check the installed profile’s actual driver/firmware path and keep audio disabled until its own safe routing and protection are qualified.

Record component adoption and native outcomes in the canonical ledger and release evidence. Keep exploratory scripts and historical diagnostics outside the normal installation flow. A release's support matrix must describe what the installed system actually does, not everything a source branch contains.
