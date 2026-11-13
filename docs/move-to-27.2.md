# Moving the J714s Linux side from the 27.3 beta stub to 27.2

Research and plan, 2026-11-12. Nothing on the Mac was changed while writing it. The Mac was
unreachable (root@10.168.168.116 timed out), so every Mac-state question is written below as a
preflight check.

Each claim is labelled:
- **[verified]**: checked here, against a file, an IPSW or a saved log.
- **[derived]**: worked out from verified facts, not run.
- **[reported]**: someone else's claim that we have not reproduced.
- **[untested]**: nobody has run it.

## Summary

- **Upstream's 27.2 route is a padded Mach-O Stage 1.** You enrol Aura's Mach-O boot object, padded
  for a 128 MiB code window, with `kmutil configure-boot --compress` and no `--raw`. kmutil records
  `kcbz : 0` for it, so iBoot does not start SPTM. The secondary CPUs come up confined to the window,
  and Linux runs at EL2 on every CPU, with no Aura monitor underneath.
  - aurora-installer does this on every M4-or-later Mac, but it refuses the J714s.
  - The only T6050 known to boot this way is Jens Axboe's K116s, on its own 27.2 build (26B8125)
    **[reported]**.
- **Our route is not SPTM-mediated, as far as our files show.** We enrol m1n1 as a **raw** object
  (`--raw --entry-point 2048 --lowest-virtual-address 0`). On a raw object iBoot does not load SPTM
  either. All 15 CPUs come up only because Apple fixed raw boot objects in the 27.3 beta 1 mBoot
  (182898702). A saved bare-metal log shows Linux started at EL2 on all CPUs. See section 2.
- **The 27.2 stub must be built from the IPSW.** macOS stays on 27.3 beta 1, so cloning the host (what
  `prep-stub.sh` and `refresh-stub-firmware.sh` do) would give 27.3 again. The IPSW is
  `UniversalMac_27.2_26B123_Restore.ipsw`, and its J714s iBoot is `mBoot-20457.41.3`. We have no tool
  for this yet. It needs a restore bundle assembled the way asahi-installer's `stub.py` does it, and
  the IPSW's encrypted (AEA) BaseSystem decrypted.
- **Physical steps: two, plus Touch ID.** One macOS session (FileVault unlock), one 1TR session, and
  re-enrolling one finger.
- **Rollback keeps the 27.3 stub.** The 27.2 stub goes in its own new APFS container. Going back to
  27.3 is then a startup-disk choice, with no 1TR.
- **Touch ID: plan to re-enrol.** A new stub is a new volume group. The T6050 Secure Enclave identity
  is `/chosen/apfs-preboot-uuid`, so the existing enrolment is orphaned.
- **Our 27.3 patches do not all carry over.** The 27.2 GPU, display, ANE, AVE and camera each need
  27.2 rows. Some can't be written until the first 27.2 boot, because their values come from that
  boot's ADT. The PCIe storage fix (0007), the softdep (0009), the notch default (in 0003), the camera
  driver commits (0005) and VRR (0008) are not tied to a firmware version.

## 1. How aurora-silicon boots an M5 (T6050) on 27.2

### 1.1 The maintainer's statement, checked against the code

> "27.2 is our current bleeding edge target as under Mach-O (with SPTM disabled) we don't face the
> SMP bug patched in 27.3b, and also support additional sysregs (TSO & deep sleep prereqs)."

**"Mach-O with SPTM disabled" means a Mach-O boot object with `kcbz` 0.**
- aurora-silicon/aura `docs/macho-boot-object.md:7-13` (main 0fb98b8d):
  - kmutil records `kcbz`, the size of the object's `__TEXT_BOOT_EXEC`.
  - "macOS 27.2 iBoot loads TXM, ExclaveOS and SPTM and enters SPTM only when `kcbz` is nonzero.
    With `kcbz` zero it skips that loader and jumps to the object's entry, as it does for a raw boot
    object. In this mode the GXF registers are writable."
- `aura-boot.macho` has no `__TEXT_BOOT_EXEC`. It comes from aura #29 (DjDeveloperr, "Boot without
  SPTM").

**The cost: confined secondaries.**
- iBoot leaves four CTXR windows armed and locked on the secondary CPUs (`macho-boot-object.md:75-95`).
- So the object is padded:
  - `tools/macho_boot_object.py --execute-window`, or aurora-installer's
    `MachOBootObject.expandExecuteWindow`, adds a 128 MiB window.
  - It is enrolled with `--compress`.
  - The kernel is built with `CONFIG_ARM64_CTXR_EXECMEM`.
  - Aura moves the kernel into the window and enters it at EL2 with spin-table
    (`macho-boot-object.md:124-160`).

**Order in 1TR.**
- Enrolling a Mach-O object turns Kernel CTRR back on (`macho-boot-object.md:63-68`).
- aurora-installer runs `bputil -nc` and then `kmutil` (aurora-installer `macOS/Recovery/README.md`,
  "Review policy" and "Updating Stage 1").

**The SMP bug.**
- Apple's 27.3 beta 1 mBoot release note: "Only a single core is available when you boot Linux ...
  from a custom raw boot object on Mac computers with M5 Pro, M5 Max, and M5 Ultra chips
  (182898702)". See `docs/omarchy-m5-pro/m5-omarchy/reports/19-firmware-matrix.md:21`.
- The bug is in the **raw** path. A Mach-O object with `kcbz` 0 goes through Aura's CTXR probe and
  spin-table release instead (`macho-boot-object.md:97-122`).
- So on 27.2: raw means one CPU, and padded Mach-O means all CPUs.
  - Our own record of the one-CPU case is `docs/smp-t6050-findings.md:1-10`.
  - All CPUs at EL2 on a T6050 is **[reported]** in linux#1724: Jens Axboe's K116s, "All CPU(s)
    started at EL2", on 18 CPUs, "from a padded Stage 1 (CTXR window) on the 27.2 stub".

**TSO and deep-sleep sysregs.**
- At EL2 Aura can set `ACTLR` and the per-core deep-sleep enable (`macho-boot-object.md:110-118`).
- On a J616s, "Apple TSO works" (`macho-boot-object.md:278-284`).
- On a T6050 this is **[reported]** by the maintainer and not measured here.

### 1.2 What runs where

| Piece | What upstream uses on 27.2 | Source |
| --- | --- | --- |
| Stub firmware | the machine's own 27.2 restore image. K114/K116 get `UniversalMac_27.2_26B8125_Restore.ipsw`. The J714s has no entry, and the universal 27.2 is 26B123 | aurora-installer `NativeInspectionPolicySource.swift:65` (chip 0x6050 has a minimum macOS of 27.2), `:295-305`, `:374-385` |
| Stage 1 | `aura-boot.macho` (the raw `aura.bin` wrapped as `MH_FILESET`), its config filled by `tools/fill_stage1_config.py`, padded, enrolled `--compress` | aura `docs/macho-boot-object.md`, `docs/j700-install.md:9-30`, aurora-installer `Recovery/README.md` "Boot mode" |
| Stage 2 | the ESP's `m1n1/boot-ctxr.bin`, an Aura `ESP_STAGE2=1` build. A padded Stage 1 is filled with that path, and an unpadded one keeps `m1n1/boot.bin` | `macho-boot-object.md:188-198`, aurora-installer `Recovery/README.md` "Stage 2 paths" |
| Aura build | release 1.0.0b12 (ea20cedb). Qualified in its notes on J316s, J413 and J616s only, through aura-try Stage 2 trials with the Stage 1 untouched. 1.0.0b11 adds Neo J700. **No T6050 in either qualification table** | aura `docs/releases/1.0.0b11.md`, `1.0.0b12.md` |
| Kernel | `integration/aurora` with `CONFIG_ARM64_CTXR_EXECMEM=y` and spin-table CPUs. The T6050 tree already has `enable-method = "spin-table"` and `cpu-release-addr` (`t6050-base.dtsi:49-53`). The "T605x: none" row in `macho-boot-object.md:261` is stale | aurora-silicon/linux `arch/arm64/boot/dts/apple/t6050-base.dtsi` |
| U-Boot (EFI path only) | aurora-silicon/u-boot #32 (62ee4709, merged 2026-11-07) places Linux in the window. A zboot kernel can't be placed and falls back to one CPU | `macho-boot-object.md:200-216` |

**Upstream Aura main does not yet hand over a T6050 on 27.2** **[verified]**.

On main 0fb98b8d:
- The DCP hand-off admits 27.0 only (`src/kboot_display_handoff.c:3316`, `if (os_firmware.version != V27_0)`).
- The camera hand-off admits 27.0 only (`src/kboot.c:9397`).
- The G17S GPU admits only 26A428.
- `firmware.c:219` knows 27.2 as `mBoot-20457.41.3`, but only for naming the version.

The K116s runs on Jens's private `aura-internal` branches. Its 27.2 GPU (aura #187) and camera
(aura #188) are open PRs, for build 26B8125, not 26B123.

### 1.3 The installers

- **aurora-silicon/aurora-installer** (79a7549) is the installer that does Mach-O on M4 and later. It
  **refuses the J714s**:
  - `NativeFirmwareSelectionTests.swift:265-268`: "No other Mac is offered the 27.2 firmware, and
    no other T6050 board is admitted", with `XCTAssertThrowsError(... "apple,j714s" ...)`.
  - `scripts/tests/test_distribution_payload.py:23`: "boards the release doesn't support, such as
    the M5 Pro J714s".
  - It also partitions a fresh install. It cannot add a stub to an existing setup.
  - Its useful parts:
    - `Recovery/Tools/ExecuteWindowTool.swift`, the same padding as Aura's `--execute-window`.
    - `RestoreImage/bin/omarchy-restore-image`, a macOS binary that decrypts an IPSW's AEA
      BaseSystem: `omarchy-restore-image INPUT_AEA INPUT_SHA256 OUTPUT_DMG`.
- **omacom/omarchy-mac-installer** (c07e54c): no T6050, no 27.2 entry, no Mach-O enrolment. Our
  patched copy (`installer/patches`, `installer/patches-upstream-27.3`) pins the J714s to 27.3
  (`installer/patches/0002...:681-690`).
- **joshuaswarren/aura** `mt-boot/*` and `sgup/*`:
  - `mt-boot/neo-trial-b` and `-cda450d` are MacBook Neo (T8140) trial branches: U-Boot watchdog,
    i2c2 repeater tuning.
  - `sgup/speaker-id-trial-*` hand the speaker ID straps to the kernel.
  - None of them concerns the T6050 boot path.
- **Hand enrolment:** aura `tools/recovery/enroll-stage1.sh` (`docs/recovery-enroll.md`).
  - It checks pairing (`bputil -d -v`) and `kcbz` 0, then asks for a typed `yes`.
  - It takes `--compress` for a padded object and `--keep` for a rollback image.
  - "The script has not been run in Recovery" (`recovery-enroll.md:94`).

### 1.4 Getting a 27.2 stub while macOS stays on 27.3 beta 1

**The IPSW** **[verified]** (api.ipsw.me for Mac17,9 on 2026-11-12, and a range-read of the IPSW
with `docs/omarchy-m5-pro/m5-omarchy/tools/ipsw-peek.py`):

| Build | URL | sha256 | J714s iBoot | Signed |
| --- | --- | --- | --- | --- |
| **27.2 26B123** | `https://updates.cdn-apple.com/2026FallFCS/c9671975-52db-4fb5-9af2-00217169ba8d/UniversalMac_27.2_26B123_Restore.ipsw` (25.6 GB) | `6613b34e8589db2202a01ec37a2648afb141ece13428175183f8f3e38438534f` | `mBoot-20457.41.3` | yes |
| 27.2.1 26B131 | `.../c202a724-db7e-4d56-917b-110aa0226507/UniversalMac_27.2.1_26B131_Restore.ipsw` | `233e85a0...0814f` | `mBoot-20457.41.3` | yes |

- Use **26B123**. Upstream's GPU firmware identity (#1173, `M5_GRAPH_26B123`) and Aura's `V27_2` are
  for it.
- 27.2.1 has the same iBoot string, and its T6050 AVE firmware is byte-identical **[verified]**. Its
  GPU firmware digest was not checked.
- The J714s identity is "Customer Erase Install (IPSW)", board 0x08, chip 0x6050. Its BaseSystem is
  `022-22150-174.dmg.aea`, 1.31 GB, starting with `AEA1`, so it is **encrypted**.

**The rule** [reported, asahi-installer `main.py:587-601`, via
`docs/omarchy-m5-pro/m5-omarchy/reports/22-stub-firmware.md:19`]: a stub may be older than the system
firmware, never newer. 27.2 under a 27.3 beta 1 system firmware is allowed.

**What has to be built**, because nothing does it for a J714s yet:
1. A restore bundle from 26B123, made as asahi-installer `src/stub.py` `install_files()` makes one.
   - Keep only the J714s identity in BuildManifest.
   - Take every Manifest path except BaseSystem, OS, `Ap,SystemVolumeCanonicalMetadata`,
     RestoreRamDisk, RestoreTrustCache and `Cryptex*`.
   - Add the Bootability bundle.
   - The member list is in `reports/22-stub-firmware.md:13-22`.
   - `ipsw-peek.py --get` fetches members by HTTP range, without downloading 25 GB.
2. `arm64eBaseSystem.dmg` = the decrypted `022-22150-174.dmg.aea`.
   - On the Mac's macOS, with aurora-installer's `omarchy-restore-image`.
   - Or on the PC, with Eryk Wieliczko's Go `macos-firmware-extract` (MIT).
   - The key comes from Apple's FCS key URL, which is in the archive metadata.
3. A `prep-stub.sh` mode that fills the new volume group from that bundle instead of `ditto "$PB/restore"`
   (`scripts/prep-stub.sh:333-356`).
4. A Mach-O variant of `finish-install.sh`'s `step2.sh`. Today it runs `kmutil ... --raw`
   (`docs/bringup.md:61-66`). It should run `bputil -nc` and then
   `kmutil configure-boot -c <padded>.macho --compress -v <stub>`. Or use Aura's `enroll-stage1.sh --compress`.

A firmware refresh in place fails (`bless` error 11, "AP boot mode"; `docs/bringup.md:184-186`). So a
new firmware always means a new volume group: either new volumes in a container, or a new container.

**1TR and security policy** (aurora-installer `Recovery/README.md`, `docs/bringup.md:56-70`):

| Step | Where | Physical? |
| --- | --- | --- |
| Create the stub volumes, bless the stub | macOS, as admin (`sudo`, `bless --setBoot` asks for the password) | **Yes:** macOS has to be running, and FileVault is on, so someone types the unlock password at the Mac |
| Enter the stub's paired recoveryOS | power off, hold power until "Loading startup options", choose the stub, which `.IAPhysicalMedia` makes boot into its recovery | **Yes** |
| `bputil -nc -v <VGID>` (Permissive Security), then `kmutil configure-boot -c <padded> --compress -v <stub>` | 1TR Terminal. Asks for the owner's password, more than once | **Yes:** typing at the Mac. aurora-silicon/recovery-ssh can relay a shell from 1TR to a controller on the LAN, but one `curl` line still has to be typed in Recovery |
| `kmutil --compress` | 1TR | waiting only: "may run for 30 minutes" (aurora-installer `Recovery/README.md`, "Code window") |

No `bputil` change to macOS. macOS keeps Full Security.

## 2. What our stack does now

**[verified]** from `docs/bringup.md`, `patches/upstream-27.3/README.md`, and the memory notes
`m5-daily-boot-upstream`, `m5-cleanup-state` and `m5-boot-capture`.

| Stage | Today |
| --- | --- |
| Stub | "Omarchy" APFS container (nvme0n1p3), rebuilt 2026-11-06 from the 27.3 beta 1 host: `mBoot-20457.60.65.0.1` (`bringup.md:161-197`) |
| Security | `bputil -nc` (Permissive) in the stub's 1TR (`bringup.md:151-159`) |
| Stage 1 | our patched m1n1, plain, its chainload target compiled in, enrolled **raw**: `kmutil configure-boot ... --raw --entry-point 2048 --lowest-virtual-address 0` (`bringup.md:1626-1629`). The rollback image is in `omarchy-stage1/` on p4 |
| Proxy | stage-1 m1n1 offers USB proxy 1209:316d for 10-15 s on the cable port; `~/m5/tools/m5catch.py` and `catch-loop-up.sh` catch it |
| Stage 2 | p4 `m5local/cpu.bin`, or a RAM loader: Aura main d35655304e + 0002/0003/0006/0007 plus a `boot=` / `chosen.*` tail. Daily: `loader-daily-up-bm.bin` → p4 `m5local/daily-up` (up273-8). Fallback: `loader-daily-dcp-bm.bin` (dcp-try, `7.3.0-j714s-sleep`) |
| Kernel | `integration/aurora` + 0001/0004/0005/0008/0009 (`linux-aurora-upstream`, up273-10) |
| Roots | p5: dev Linux (60 GiB). p7/p8/p9: installed upstream image -7/-8 (ESP, boot, btrfs root) |

**Why "SPTM-mediated" does not match.**
- `docs/smp-t6050-findings.md:181-184`: "iBoot loads SPTM only on the kernelcache path ... m1n1 is
  installed `--raw` ... no SPTM is loaded at all".
- Aura's own doc says a raw object is jumped to directly (`macho-boot-object.md:11-13`).
- A saved bare-metal J714s log of the raw path on the 27.3 stub
  (`~/m5/private/ctxr-v5b-evidence-20261108/s27c-run-20261108T014537Z.txt`, kernel 7.2.2-m5slim)
  reads "CPU: All CPU(s) started at EL2" **[verified]**. That is Linux at EL2 with no SPTM, and no
  monitor under it.
- No saved dmesg of the Aura/up273 stack is on the PC. Those logs are on p5 under `/var/lib/m5test`.
  Two read-only checks would settle it:
  - on the Mac: `dmesg | grep 'started at EL'`;
  - in 1TR: `bputil -d` (Kernel CTRR status).
- The real difference from upstream:
  - we are **raw**, upstream is **Mach-O (`kcbz` 0)**;
  - we get SMP from Apple's 27.3 beta 1 fix to the raw path;
  - upstream gets SMP from Aura's CTXR probe and spin-table, which 27.2 allows.
- The maintainer may have read our 27.3 dependence as SPTM. Answer with the facts above, and don't
  argue the label.

## 3. What carries over to 27.2

### 3.1 Our 27.3 patches

| Patch | On 27.2 | Work needed |
| --- | --- | --- |
| 0001 linux #1173 + rolo's three commits | #1173 already carries the **26B123** G17S InitData layout and identity (`M5_GRAPH_26B123`). Upstream now has a 27.2 DCP method table (`drivers/gpu/drm/apple/iomfb_v27.c:118-126` `dcp_methods_27_2`, chosen by compat `"27.2.0"` at `:205-210`), so the 27.3 table and the 27.3 swap conversion go unused | keep #1173 (still open upstream) and 450cfbf77385 / e25c83799018. The 27.3 table/swap commit can stay (unused) or be dropped |
| 0002 Aura GPU/DCP hand-off | **GPU: yes.** It admits 26B123 G17S (patch line ~198, "27.2 (26B123)"). **DCP: no.** The gate admits `V27_0 \|\| V27_3B1` only (patch line ~94), so on 27.2 the panel stays on simpledrm | add `V27_2` to the T6050 DCP gate, publishing compat `<27 2 0>` (the kernel's table key). The DCP image UUID check (`T6050_DCP_UUID`, 27.0's) needs the 27.2 UUID, read from the ADT on the first 27.2 boot. **[derived]** |
| 0003 notch default + M5 Max 27.3 digest | notch default: firmware-independent. The Max 27.3 row is irrelevant | none |
| 0004 ANE/AVE | **AVE:** 27.2 is refused safely. `ave_fw_find_build()` matches by sizes, 27.2 has 27.3's sizes, so it picks the 26C5035 entry, and the CRC differs ("unsupported firmware"). **ANE:** 27.2's layout matches no build entry, so it is refused before power-up | new rows, below |
| 0005 camera driver (edimoldovan) | the driver and DT are firmware-independent. The IMX958 setfile comes from macOS's `appleh16camerad`, which stays 27.3 | none in code. Setfile against 27.2 ISP firmware is untested |
| 0006 Aura camera row | J714s rows exist for 27.3 only. Aura main admits T6050 ISP only on 27.0 (`kboot.c:9397`). #188 has a K116s 27.2 row | a J714s 27.2 row: sensor 0x74, TEXT/DATA phys and sizes from the 27.2 ADT `isp0` (Aura logs them) |
| 0007 Aura PCIe storage auto-PM | PMGR behaviour of APCIE_SYS_ST0, not firmware-specific **[derived]** | none. Worth sending upstream on its own |
| 0008 VRR | rides on the firmware-27 panel parser, and 27.2 uses the same `iomfb_v27` | retest `vrr_capable` on 27.2 |
| 0009 softdep | module load order, firmware-independent | none. Send upstream on its own |

**AVE on 27.2** **[verified]**.
- T6050's encoder firmware is `Firmware/ave/AppleAVE2FW_H17D.im4p`. Control: in 27.0 (26A428) its
  `__TEXT` is 0x154000 with CRC32 `87279429`, exactly 0004's `AVE_FW_TEXT_CRC_T6050_26A428` and size.
- 26B123 H17D:

| Build | TEXT | DATA |
| --- | --- | --- |
| 27.0 26A428 | 0x154000, CRC `87279429` | 0x134000 |
| **27.2 26B123** | **0x158000, CRC `d33ed3b4`** | **0x134000**, CRC `d25829d5` |
| 27.3 26C5035r (0004) | 0x158000, CRC `c25b4ddb` | 0x134000 |

- 27.2.1 (26B131) H17D is byte-identical to 26B123's.
- The fix: `{ "26B123", 0x158000, 0x134000, 0xd33ed3b4 }`, plus the CRC in `ave_known_text_crc[]`.
  `ave_fw_find_build()` must then select by CRC as well as size, because 26B123 and 26C5035 share
  sizes.
- Which command layout 26B123 takes (26A428's, as 27.3 does?) is **[untested]**. Probe-only until an
  encode passes.

**ANE on 27.2** **[derived, partly unverified]**.
- No IPSW member is named for T6050. The H17 images (`h17_ane0/1_fw_hyperion_j71y`,
  `h17_ane_fw_theia_d9x/j73y`) share one layout per release:

| Release | TEXT | DATA | Span |
| --- | --- | --- | --- |
| 27.0 | 0xc0000 | 0x2ac000 | 0x36c000 |
| 27.2 | **0xbc000** | **0x2b0000** | 0x36c000 |
| 27.3 (0004, measured on the Mac) | 0xec000 | 0x280000 | 0x36c000 |

- 27.0's sizes match 0004's 27.0 entry exactly. **But** none of the 27.0 TEXT sha256s equals the
  kernel's `ane_t6050_text_pin_27_0` (`93ae3a37...d0ee438b8f`). So these files are not proven to be
  the T6050 image, and the 27.2 sizes above are a strong guess, not a fact.
- Take the 27.2 row from the first 27.2 boot:
  - the ADT `ane0` segment-ranges (Aura logs them);
  - the TEXT sha256 the driver prints when it refuses ("preloaded TEXT sha256").
  - Then add `{ "27.2", { 0x10000000000, 0x10000000000 + TEXT }, { TEXT, DATA }, pin }`.
- IPC sizing: 0004 already sizes it from the firmware's request.

**GPU firmware digests** for 26B123 come from #1173 via 0002. They are not re-derived here.

### 3.2 Touch ID

**[derived]** from aurora-silicon/linux `tools/aurora-sep/OS-IDENTITY.md` and `XART-SAFETY.md`
(integration/aurora) and `drivers/soc/apple/profile.rs`:

- **T6050 takes T6040's profile** (`profile.rs:470-477`). Its identity source is
  `IdentitySource::Chosen` (`profile.rs:770` asserts it for T6040): the 16-byte SEP OS identity is
  `/chosen/apfs-preboot-uuid`, "the booted volume group".
- **A new stub is a new volume group.** "Recreating the volume group ... can change chosen and needs
  the same care" (`OS-IDENTITY.md:51`). "Changing the identity of an installed system orphans
  everything enrolled under the old one" (`OS-IDENTITY.md:5-8`).
- **`aurora-sep-policy-change --expect`** (`XART-SAFETY.md:120-222`) covers a **boot-policy change
  inside the same lane**: a new Stage 1 or a Mach-O conversion. It lets the enclave rewrite one
  kind-4 record once.
- The move to 27.2 does both: new policy and new identity.
- **What could keep the enrolment** **[untested]**:
  - pin the old identity with `apple_sep.os_uuid_hi/lo`, which takes precedence over chosen
    (`OS-IDENTITY.md:18-24`);
  - and arm `--expect` for the policy rewrite.
  - Against it: `OS-IDENTITY.md` warns "never test identity changes on a machine with enrolments
    that matter", and the old 27.3 stub's lane would then be shared by two boot policies.
- **Recommendation: re-enrol.** It is one finger, about 2 minutes at the Mac.
  - Before the move: `fprintd-delete tripleu` on the dev Linux, and stop `aurora-sep.service`.
  - Then nothing writes enclave state on the first 27.2 boot until we choose to.
  - Do not restore old keybag or host files afterwards: "file rollback does not roll back the
    enclave's counters".
  - macOS's own Touch ID records stay untouched, because the xART guard protects them. That was
    verified at enrolment (`docs/left-out.md`, Touch ID row).
- **Before anything:** keep the iBoot System Container backup
  (`~/m5/backup/iboot-system-container-2026-11-12.img.zst`). Also take a fresh `aurora-sep-policy-change`
  backup (`/var/lib/aurora-rollback/...`) as evidence.

### 3.3 Disks and roots

| Thing | On 27.2 |
| --- | --- |
| macOS (p2) | untouched. Stays on 27.3 beta 1 |
| Stub (p3), 27.3 | **kept** as the rollback (plan below) |
| ESP p4 (`m5local/*`, the old `cpu.bin`) | old files stay for the 27.3 stub. The 27.2 Stage 1 is pointed at a **new** folder (`m5local/s272/boot-ctxr.bin`). That is a deliberate boot-file write to p4, which needs the owner's OK under the RAM-only rule |
| Dev Linux p5 | carries over: the root is firmware-independent. It needs a 27.2 kernel (up272-N, modules on p5) and its loader file on p4 |
| Installed image p7/p8/p9 | its packages are 27.3-specific (0002/0006 gates, 0004 rows), so it won't get the display, ANE, AVE or camera on 27.2. Its own chain goes through U-Boot's EFI path. edimoldovan's U-Boot 70e99081 contains u-boot #32 (`compare 62ee4709...70e99081`: ahead 5, behind 0) **[verified]**, and our kernel config has `CONFIG_EFI_ZBOOT` unset, so the UKI path can use the window **[derived]**. It needs a rebuilt image (27.2 packages, Stage 2 at `m1n1/boot-ctxr.bin`) or a reinstall. It is also the candidate source of free space (below) |
| RAM catcher (`catch-loop-up.sh`, `loader-*-bm.bin`) | built around **m1n1's** stage-1 proxy. After the move, Stage 1 is **Aura**. Its proxy window is set with `--window-ms` in the Stage 1 config (`j700-install.md:36-42`). Whether Aura Stage 1's proxy enumerates on our cable port is **unknown**: Aura **Stage 2's** proxy does not (`m5-ram-only-tests` memory). Chainloading under CTXR uses aura #186's copy stub, because the locked RVBAR moves each boot |
| `loader-daily-dcp-bm.bin` fallback (old m1n1 kernel) | **does not carry**: its kernel has no `CONFIG_ARM64_CTXR_EXECMEM`. On 27.2 a raw path is one CPU anyway |

## 4. Migration plan

The design:
- a **second stub** for 27.2, in its own APFS container, beside today's 27.3 stub;
- **one** 1TR session, which enrols a padded Aura Stage 1 that has a proxy window;
- after that, everything is file changes on the ESP and RAM tests.

### Phase 0: build and prepare, no Mac changes (about 3-4 h of machine time)

1. **Kernel up272-1** (ush). `integration/aurora` at the current pin, plus:
   - #1173 and rolo's 450cfbf77385 / e25c83799018;
   - 0004 + the 26B123 AVE row (select by CRC);
   - 0005, 0008, 0009.

   About 40 min. Keep `CONFIG_ARM64_CTXR_EXECMEM=y`. Check that the dtb keeps `enable-method = "spin-table"`.
2. **Aura** (d35655304e or main 0fb98b8d). 0002 + `V27_2` in the T6050 DCP gate, 0003, 0006 (the 27.2
   row is left for later), and 0007. About 10 min. Build:
   - the Stage 1 flavour: `aura.bin`;
   - the Mach-O wrap and padding: `tools/macho_boot_object.py --execute-window aura-stage1-filled.bin aura-stage1-padded.macho`;
   - the ESP Stage 2: `ESP_STAGE2=1`, to be written to p4 as `m5local/s272/boot-ctxr.bin` with a
     `boot=` tail naming the up272 kernel on p4.
3. **Fill Stage 1:** `tools/fill_stage1_config.py --esp-partuuid <p4> --stage2-path m5local/s272/boot-ctxr.bin --window-ms 15000`.
   - Check in macOS: `kmutil inspect -z -B ... --show-mach-boot-properties` must give `kcbz : 0` and
     the expected `kcrz`.
   - Keep the raw `aura-stage1-filled.bin`. Its unpadded wrap is the rollback inside the 27.2 stub.
4. **Stub bundle from 26B123** (PC):
   - range-fetch the J714s members (section 1.4) and assemble `restore/`;
   - fetch `022-22150-174.dmg.aea` (1.3 GB).

   About 30-60 min, depending on the network. New tool, `tools/stub-from-ipsw.py`, ported from
   asahi-installer's `stub.py` (MIT).
5. **Scripts:**
   - `prep-stub.sh --bundle DIR --container NEW` (new container, populated from the bundle);
   - a Mach-O `step2.sh`: `bputil -nc -v VGID`, then `kmutil configure-boot -c ... --compress -v`.
     Or stage Aura's `enroll-stage1.sh` with `--compress --keep`.

   Dry-run both against stand-in tools, as `enroll-native.sh` was.

### Phase 1: RAM-only pre-tests on today's 27.3 setup (about 1 h, hands-free)

- **R1: does Aura Stage 1's proxy reach the PC?**
  1. Chainload the **raw** filled Aura Stage 1 (with `--window-ms`) from the m1n1 stage-1 proxy.
  2. Watch for 1209:316d on the PC.

  This decides whether the catcher survives the move. It is only an approximation: the USB state
  after a chainload differs from a cold iBoot start.
- **R2:** up272-1 through today's loader on 27.3. It should boot as up273-10 does, with ANE and AVE
  refused safely (27.3 rows are dropped only if we drop them). This catches build regressions before
  the firmware changes.
- **If R1 fails:**
  - fill Stage 1 with no window;
  - use aura-try one-shot Stage 2 trials (1.0.0b11 "#82") for tests;
  - keep a known-good `boot-ctxr.bin` fallback on p4.

  Say so to the user before Phase 3, because hands-free recovery gets weaker.

### Phase 2: Touch ID (2 min, on the dev Linux over ssh)

1. `aurora-sep-policy-change --expect`. This is for its backup, not to keep the enrolment.
2. `fprintd-delete tripleu`.
3. `systemctl disable aurora-sep.service`.
4. Leave `/etc/modprobe.d/aurora-sep-xart.conf` in place until re-enrolment.

### Phase 3: make the 27.2 stub (physical step 1: about 30-45 min, the user at the Mac for ~2 min)

**Preflight** (read-only, from the dev Linux and then macOS):
- `sfdisk -l /dev/nvme0n1` and `diskutil list` / `diskutil apfs list`: free space, and the stub
  container's usage.
- `cat /proc/device-tree/chosen/firmware-version`, which should be 20457.60.65.0.1.
- That `omarchy-stage1/` (the m1n1 rollback) is on p4.

**Space for a new ~7 GB container.** Do not shrink macOS. Pick one:
- **(a) Shrink p9**, the image's btrfs root. From the dev Linux:
  1. `btrfs filesystem resize -8G` on it, mounted.
  2. Shrink p9's GPT entry (`sgdisk`) to match, keeping a 1 GiB margin.

  p5 is not touched, so no dev-initrd size pins break.
- **(b) Delete p7-p9.** The image needs rebuilding for 27.2 anyway, and that frees ~55 GB.
- **(c) A second volume group inside the existing 6 GB container.** Only if `diskutil apfs list`
  shows ≥3 GB free there. It is untested for stubs, because Asahi uses one container per stub.

**Steps:**
1. **Physical: boot macOS and unlock FileVault.** To get to macOS: power-hold picker → Macintosh HD.
   Or, if asahi-bless/aurora-bless is on p5, set the next boot to macOS from Linux first. From then
   on, `ssh macbook` does the rest.
2. On macOS:
   1. Decrypt the BaseSystem: `omarchy-restore-image ...`.
   2. Create the container in the free space: `diskutil addPartition`, as asahi does.
   3. `prep-stub.sh --bundle` for the volumes: System/Data/Preboot/Recovery, the restore bundle, and
      `arm64eBaseSystem.dmg`.
   4. `finish-install.sh` with the Mach-O step2 and the **padded** object as `boot.bin`.
   5. `bless --setBoot` the new stub, with the admin password over ssh.
   6. Check with `bputil -d`-free reads: `diskutil info`, and that the new stub's Preboot
      `restore/.../iBoot.j714s.RELEASE.im4p` is 26B123's (1,479,797 B, `mBoot-20457.41.3`).
3. Copy `boot-ctxr.bin`, the up272 kernel, the dtb and the initrd to p4 `m5local/s272/`, and the up272
   modules to p5. Leave everything else on p4 as it is.

### Phase 4: 1TR (physical step 2: 15-45 min, the user at the Mac throughout)

1. Shut down, wait 15 s, hold power until "Loading startup options", and choose the **new** stub. Its
   recovery opens and runs step2. If no Terminal opens: Utilities → Terminal → run `step2.sh`.
2. step2 checks `bputil -d -v` for "Paired" and "one true recoveryOS", then:
   - `bputil -nc` (password twice);
   - `kmutil configure-boot -c <padded> --compress -v <stub>` (password, then up to 30 min of
     compression);
   - removes `.IAPhysicalMedia`.
3. Restart.

If pairing is wrong, run `bless --setBoot --mount <stub>` and re-enter Options
(`bringup.md:1588-1598`). That costs one more power-hold.

**Fewer keystrokes:** run aurora-silicon/recovery-ssh's controller on the PC (Linux is supported for
LAN). Then the user types one `curl ... | sh` in Recovery and we drive the rest, but the user still
answers the password prompts.

### Phase 5: first 27.2 boots (hands-free if R1 passed, about 1 h)

1. The catcher sees Aura Stage 1's window. On a miss, Stage 1 loads `m5local/s272/boot-ctxr.bin`.
2. Check:
   - `/proc/device-tree/chosen/firmware-version` = `mBoot-20457.41.3`;
   - "All CPU(s) started at EL2" on 15 CPUs;
   - `/chosen/aurora,ctxr-exec-window`;
   - Wi-Fi (0007 path), NVMe, GPU `26B123 ... G17S`;
   - DCP `eDP-1` 3024x1964 (with the `V27_2` gate);
   - trackpad;
   - and that no SError or Oops appears.
3. Collect the 27.2 ANE segment-ranges and refused TEXT sha256, the ISP `isp0` segments and the DCP
   image UUID. Then add the ANE, camera and DCP-UUID rows, rebuild, and RAM-test.
4. Retarget the catcher (`catch-loop-up.sh`, aura #186 copy-stub chainload) and set the new daily
   loader.

### Phase 6: Touch ID (physical step 3: about 2 min)

`aurora-sep-policy-change --status` must be clean. Then put the opt-in back, start the service and
enrol: `fprintd-enroll`, with touches at the Mac. Then `fprintd-verify` before and after a reboot.

### Rollback to 27.3

| From | How | Physical? |
| --- | --- | --- |
| A bad 27.2 kernel or Stage 2 | the catcher or a RAM loader, or restore `boot-ctxr.bin` on p4 from the backup | no |
| A bad 27.2 Stage 1 | 1TR of the 27.2 stub: enrol the kept unpadded or raw image (`enroll-stage1.sh --keep`) | yes (1TR) |
| Give up on 27.2 | choose the old "Omarchy" stub as startup disk: power-hold picker → Omarchy, or `bless --mount <old stub> --setBoot` from macOS. The old stub keeps its raw m1n1, its Permissive policy, its p4 `cpu.bin` and `daily-up`, and its own Touch ID lane | one power-hold (about 1 min), or none from an unlocked macOS |

Re-enrolment is needed again after a rollback: identity follows the volume group. Removing the 27.2
stub later is the same container deletion as in `bringup.md:88-103`, minus the macOS resize.

### Physical steps, plainly

1. Unlock macOS once (FileVault password).
2. One 1TR session: hold power, pick the stub, type the password 3-4 times, wait up to 30 min.
3. Re-enrol one finger (about 2 min).
4. Only if something goes wrong: a power-hold to pick the old stub, or a second 1TR.

### Time

| Phase | Time |
| --- | --- |
| 0 build/prepare | 3-4 h machine time, 0 user time |
| 1 RAM pre-tests | about 1 h, hands-free |
| 2 Touch ID prep | 2 min |
| 3 stub | 30-45 min, about 2 min user |
| 4 1TR | 15-45 min of user presence |
| 5 first boots and row collection | 1-2 h, hands-free if R1 passed |
| 6 Touch ID | 2 min user |

## 5. Risks

- **Nobody has booted a J714s on 27.2 Mach-O.**
  - The T6050 evidence is K116s on 26B8125 (linux#1724, aura #186/#187/#188, all Jens Axboe via
    Thomas Glanzmann), on private `aura-internal` branches.
  - Our 128 MiB padded object would be its first J714s boot. The aurora-installer README says "This
    128 MiB size has not been booted yet" for its own release; it was booted on a J616s with 1.0.0b7.
- **Hand-built 27.2 stub.**
  - The stub.py port and AEA decryption are new code.
  - A wrong bundle fails at `bless`, or in 1TR ("macOS needs to be reinstalled"). It does not affect
    macOS or the old stub.
- **The catcher may not survive** (R1). Aura Stage 2's proxy is unreachable on our cable port today.
  - If Stage 1's is too, recovery from a bad boot needs the watchdog: packaged Aura disables it on
    T6050 (`wdt-version` 3).
  - Or a power-hold.
- **CTXR window rules** (`macho-boot-object.md:162-186`): a kernel outside the window, or a `boot=`
  image that is too big, makes Aura refuse ("No usable window"), and the boot falls into the proxy.
  Kernel and initrd sizes must fit.
- **What a confined boot loses:**
  - CPU hotplug, and so suspend-to-RAM through hotplug;
  - PSCI reset/off, so restart goes through `macsmc-reboot` or the watchdog;
  - kexec.
  - s2idle (lid sleep) is unaffected **[derived]**.
- **27.2 rows we can't write in advance:** DCP UUID, ANE pin and layout, camera. The first boot will
  have simpledrm (unless the DCP UUID matches 27.0's), and no ANE, AVE or camera.
- **Touch ID** has to be re-enrolled. Pinning the old identity is possible but untested.
- **Space:** shrinking p9 is a btrfs shrink on the image root. If it fails, delete p7-p9 instead
  (the image needs rebuilding anyway).
- **The 27.2.1 temptation:** same iBoot, but the GPU firmware digest is unchecked. Stay on 26B123
  unless upstream moves.
- **Upstream drift:** Aura main still lacks T6050 27.2 GPU/DCP/ISP admission, so our 27.2 rows
  (0002 `V27_2`, AVE `d33ed3b4`, the ANE and ISP rows) are the PR candidates, with 0007 and 0009.

## Sources (local copies used)

- aurora-silicon/aura main 0fb98b8d: `docs/macho-boot-object.md`, `docs/recovery-enroll.md`,
  `docs/j700-install.md`, `docs/t6050-linux.md`, `docs/releases/1.0.0b11.md`, `1.0.0b12.md`,
  `src/firmware.c:219`, `src/kboot.c:9397`, `src/kboot_display_handoff.c:3316`. PRs #29, #186,
  #187, #188.
- aurora-silicon/aurora-installer 79a7549: `macOS/Recovery/README.md`,
  `macOS/Sources/AuroraAppleInstaller/NativeInspectionPolicySource.swift`,
  `macOS/Tests/AuroraAppleInstallerTrustCoreTests/NativeFirmwareSelectionTests.swift:195-269`,
  `macOS/scripts/assemble-distribution-payload.py:401-406`,
  `macOS/scripts/tests/test_distribution_payload.py:23`, `macOS/RestoreImage/README.md`.
- aurora-silicon/linux `integration/aurora`:
  - `arch/arm64/boot/dts/apple/t6050-base.dtsi:49-53`;
  - `drivers/gpu/drm/apple/iomfb_v27.c:118-210`, `dcp.c:5271-5285`;
  - `drivers/accel/ane/ane_fw_platform.c:45-50`;
  - `drivers/soc/apple/profile.rs:470-477`;
  - `tools/aurora-sep/OS-IDENTITY.md`, `XART-SAFETY.md:120-262`;
  - PRs #1173, #1724, #1646, #1650.
- aurora-silicon/u-boot #32 (62ee4709). aurora-silicon/recovery-ssh README.
- joshuaswarren/aura `mt-boot/neo-trial-b`, `mt-boot/neo-trial-cda450d`, `sgup/speaker-id-trial-{b8,cda450d,d83}`.
- omacom/omarchy-mac-installer c07e54c.
- api.ipsw.me `Mac17,9`. Range reads of the 26A428, 26B123 and 26B131 IPSWs (`ipsw-peek.py`): the
  J714s iBoot strings, AVE H17D and the H17 ANE `__TEXT`/`__DATA` segments.
- This repo:
  - `docs/bringup.md:21-70,151-197,1550-1647`;
  - `docs/smp-t6050-findings.md:1-10,181-184`;
  - `patches/upstream-27.3/README.md` and patches 0002, 0004;
  - `installer/recipes/aurora-sep-upstream/README.md:205-213`;
  - `installer/recipes/linux-aurora-upstream/config:622,2221`;
  - `installer/recipes/m1n1-aurora-upstream/PKGBUILD`;
  - `docs/omarchy-m5-pro/m5-omarchy/reports/19-firmware-matrix.md`, `22-stub-firmware.md`.
