# 22 — Plan B: a stub on non-26.6.2 OS firmware (research + plan; no Mac changes made)

## Recommendation
Rebuild the stub from the **macOS 26.5 (25F71) IPSW**. Its J714s stage-2 is **mBoot-18000.120.36**, the exact firmware on which betizzel reports raw m1n1 booting on a J714s (REPORTED, report 19). It also needs **no change to the host macOS** (it stays on 26.6.2).
- Replace the stub **in place**: new stub volumes in the existing 6 GB container, so a new VGID and LocalPolicy. The macOS container, the EFI partition and the Linux partition are untouched.
- The SMP fix needs a 27.3b1+ stub *and* host (report 19), so it's a later, separate step.

Verified on ush, read-only via HTTP range requests (`tools/ipsw-peek.py`, new, stdlib):
| IPSW | J714s identities | `iBoot.j714s.RELEASE.im4p` version string | sha256 | BaseSystem |
|---|---|---|---|---|
| 26.5 25F71 | "macOS Customer"/Erase, plus Customer Erase/Upgrade Install; board 0x08 chip 0x6050 | **mBoot-18000.120.36** | f37219be…4723 | `022-21678-092.dmg.aea`, 1,140,850,688 B, starts `AEA1` (**encrypted**) |
| 26.6.2 25G83 (our current stub) | same | **mBoot-18000.161.10** | 872486a0…209b | — |

## 1. How the installers build a stub from a chosen IPSW
**asahi-installer @e93743d `src/stub.py` (MIT):**
- `load_ipsw()` opens the IPSW URL through `urlcache.URLCache`, which uses HTTP range reads, so only the needed members are downloaded.
- `load_identity()` picks the BuildManifest identity with matching `ApBoardID`/`ApChipID`/`DeviceClass` and `Variant == "macOS Customer"`, `RestoreBehavior == "Erase"`, then writes a BuildManifest holding **only that identity**.
- `install_files()`:
  - System: `bootcaches.plist`, `PlatformSupport.plist`, SystemVersion with "(stub)", the bootable flag.
  - Preboot `<VGID>/<bless2.RestoreBundlePath>`: BuildManifest, SystemVersion, RestoreVersion, bootcaches, `BootabilityBundle/Restore/Bootability` + its trustcache, `Firmware/Manifests/restore/macOS Customer/`, and **every identity Manifest path except** BaseSystem, OS, `Ap,SystemVolumeCanonicalMetadata`, RestoreRamDisk, RestoreTrustCache and `Cryptex*`.
  - Recovery `<VGID>/usr/standalone/firmware/arm64eBaseSystem.dmg` = the identity's BaseSystem.
  - Admin users copied from the host; Finish Installation.app, step2.sh and `.IAPhysicalMedia` installed.
- **Personalization:** none in the installer. The macOS side runs `bless --setBoot --device /dev/<stub sys> --user … --stdinpass` (`main.py:653-680`), then 1TR runs step2 (`bputil -nc`, `kmutil`), which creates the stub's LocalPolicy.
- **Version filter** (`main.py:587-601`, kept by the omarchy engine `omarchy_firmware.py:available_ipsws`): a stub IPSW is offered only if `min_iboot <= system firmware`, `min_macos <= host macOS` and `min_sfr <= host SFR`. So **the stub may be older than the host, never newer.** Asahi still installs 12.3.1 / 13.5 / 14.8.3 stubs on newer hosts.
- [Inference] Because those old builds still install, the stub OS version doesn't need to be currently Apple-signed. 26.5 is signed anyway (below).

**omarchy engine @3dd6799 (MIT; `AGENTS.md` permits agent work):**
- Adds macOS 26 IPSWs (`Engine/patches/0001-omarchy-engine-runtime.patch`): `IPSW("26.6", "26.0", "mBoot-18000.161.9", …, ["j700ap"], …)` and `IPSW("26.6.2", …, ["j613ap","j615ap","j700ap"], …)`; there's **no J714s entry**.
- "A stub on macOS 26 firmware holds its decrypted recoveryOS and two sets of personalized boot objects, which do not fit in 2.5GB" → `STUB_SIZE_MACOS26 = 6GB`. Our stub is 6 GB.
- `omarchy_apple_aea.py`: "A macOS 26 restore image ships its recoveryOS and ExclaveOS images AEA encrypted … decrypts each archive with the key Apple's FCS service releases for it". The decoder is `Engine/RestoreImage` (Swift/CryptoKit, MIT, from erykwieliczko/macos-firmware-extract @71b413af, MIT, which has a Go reference). The key URL is in the archive metadata (`com.apple.wkms.fcs-key-url`, `Archive.swift:121`), limited to `wkms-public.apple.com` / `fcs-keys-pub-prod.cdn-apple.com` (`Transport.swift:6`).

**For J714s:** we don't run either installer, since neither lists j714sap and both also partition. We'd reuse betizzel's `prep-stub.sh` (MIT), which already creates the volume group and supports a "resume" path for an existing container. Only its **populate** step changes: copy a 26.5 restore bundle assembled per `stub.py` instead of `ditto "$PB/restore"`, plus the decrypted 26.5 BaseSystem instead of the host's.

## 2. Signed versions for Mac17,9 (api.ipsw.me, 2026-11-04)
Signed: **27.2** 26B123, **27.0.1**, **27.0**, **26.6.2**, **26.6.1**, **26.6**, **26.5.2** 25F84, **26.5.1** 25F80, **26.5** 25F71, **26.4.1**, **26.4**, **26.3.1**. ipsw.me can lag, and Apple can close signing any time.

Raw boots REPORTED on T6050 (report 19):
- **18000.120.36 (26.5)**: betizzel, J714s.
- **20457.1.29 / 20457.41.x (27.0–27.2)**: edimoldovan, rolotrealanis98.
- 20457.60.65 (27.3b1): rolotrealanis98, with SMP.
- None on 18000.161.x. And on the M3 Air the omarchy engine notes "asahi's Stage 1 makes iBoot panic on 26.6.2" (report 21).

## 3. Choice and risks
| Option | For | Against |
|---|---|---|
| **26.5 stub (recommended)** | Exact board + firmware REPORTED to boot (betizzel); host unchanged; allowed by the "older than host" rule | Single core (no SMP fix); needs AEA decryption of BaseSystem; a 26.5 stub on 26.6.2 system firmware (LLB 18000.161.10) is a combination not reported on T6050, though Asahi runs older stubs routinely |
| 27.x stub | REPORTED on J714c/J716s; 27.3b1 also gives SMP | **Host must be updated to 27.x first** (stub can't be newer than the system firmware), which changes the owner's daily OS. 27.3 is beta. edimoldovan reports "the installed 27.2 beta panicked twice on container operations" (`edimoldovan/kernel` README) |
| 26.5.1/26.5.2 | probably the same 18000.120.x line | not REPORTED; check their iBoot string first with `tools/ipsw-peek.py` |

Further risks:
- **Pairing/default:** a new VGID needs the same two-hold ceremony (report 18 correction). Asahi's "A one-time volume selection does not select its paired Recovery" applies.
- **Refresh in place fails** (REPORTED, rolotrealanis98): "an existing Permissive LocalPolicy can only be rewritten from 1TR, and a new restore bundle needs a new policy". So recreate the volumes, not just the bundle.
- **Mixed versions:** don't keep the 26.6.2 recoveryOS with a 26.5 restore bundle. It's untested; use the matching 26.5 BaseSystem.

## 4. Exact plan (each Mac step needs PM approval; partition-level steps need the owner)
**A. ush (no Mac change):**
1. `tools/ipsw-peek.py <26.5 URL> --get <member> <out>` for every member that `stub.py install_files()` copies (list in §1), plus the BuildManifest reduced to the "macOS Customer"/Erase J714s identity. Assemble `build/stub-26.5/restore/` (a small script, `tools/stub-bundle-ipsw.py`, ported from stub.py, MIT) and a manifest of sha256s.
2. Fetch `022-21678-092.dmg.aea` (1.14 GB) and decrypt it to `arm64eBaseSystem.dmg`. Option: the macos-firmware-extract Go reference on ush, after checking its AI-instructions and license, and with Go as a user-level tool in `tools/`. This is a **separate small task**.

**B. Mac (owner present; macOS container, EFI and Linux partitions untouched):**
```sh
# 0. default = Macintosh HD (System Settings → Startup Disk); record the current stub for undo
diskutil apfs list | grep -A30 Omarchy > ~/stub-before.txt
# 1. remove only the stub's volumes (container disk3 / partition stay)
for v in $(diskutil apfs list -plist <STUB_CT> | plutil -extract Containers.0.Volumes raw -o - - ... ); do sudo diskutil apfs deleteVolume "$v"; done   # PM: list by name first, delete the 4 Omarchy* volumes
# 2. recreate volumes + populate with the 26.5 bundle (prep-stub.sh resume path, populate step swapped)
sudo M5_STUB_BUNDLE=/tmp/stub-26.5 scripts/prep-stub.sh --yes        # patched locally: restore/ + BaseSystem + SystemVersion from the bundle
# 3. verify before arming
shasum -a 256 "/Volumes/Preboot/<newVGID>/restore/Firmware/all_flash/iBoot.j714s.RELEASE.im4p"   # must be f37219be…4723
# 4. arm (blesses the stub, as designed) with the test object
sudo scripts/finish-install.sh --m1n1 /tmp/boot.bin
```
**C. Owner, 1TR:** hold power → Omarchy → Continue → step2 (paired: `bputil -nc` ×2 credentials, `kmutil`) → Enter → boot. Then restore the default to Macintosh HD from macOS.

**Undo:** same as B.1, then the original `prep-stub.sh` (clone of 26.6.2) + `finish-install.sh`. That's today's state. Recovery/macOS are never touched; the paired 26.6.2 macOS recovery stays.

**Replace vs second stub:** replace. A second stub needs another ~6 GB from the macOS container (a resize) and adds a second Omarchy entry to the picker. The current 26.6.2 stub has no value beyond what the undo recreates.

## Open items
- AEA decryption (A.2) is the only new technical piece.
- `prep-stub.sh` populate-step patch (local, MIT).
- The step-B.1 volume-deletion commands get pinned exactly once the PM sends `diskutil apfs list` output (names/IDs aren't recorded here).
