# omarchy-j714s 1: the J714s does not boot after "Finish setup" (2026-11-13)

Offline diagnosis, written while the Mac sat in recovery and could not be reached. Every claim
comes from code, release artifacts or saved logs. Labels:
- **[verified]**: checked here against a file or artifact.
- **[derived]**: worked out from verified facts.
- **[reported]**: someone else's result, not reproduced.
- **[open]**: needs data from the Mac.

## What happened

| Step | Observed |
| --- | --- |
| 1 | The macOS app partitioned the disk and built a new stub from `UniversalMac_27.2_26B123_Restore.ipsw` (J714s iBoot `mBoot-20457.41.3`). The system firmware stays at 27.3 beta 1 (`mBoot-20457.60.65.0.1`). |
| 2 | The Mac switched itself on and off repeatedly until the owner held power and picked the new stub. |
| 3 | In the stub's 1TR, the Recovery app's "Finish setup" ran `bputil -nc` and then `kmutil configure-boot -c <padded> --compress -v <stub>`. |
| 4 | Booting the stub now shows an Apple progress bar for about 4 s, then the Mac powers off. |
| 5 | Nothing appeared on the PC's USB cable. |

## Short answer

- **The boot most likely fails before Aura's Stage 1 runs, or in its first instructions.** The
  likely mechanism is an iBoot panic at or after the `fuos` (custom boot object) load.
  - This Mac has failed this way before: logo, power-off, repeated, then recovery
    (`docs/omarchy-m5-pro/JOURNEY.md`, 2026-11-04 rows; report 15).
  - An iBoot panic leaves a PanicMedic/SOCD record. macOS turns it into a panic report on its
    next boot.
- **The object we enrolled has the same layout as the one this Mac booted on 2026-11-07** [verified].
  The entry point, padding, `kcrz` and every segment match, and so does the wrapper, except
  three UUIDs. The layout, entry point and padding are **not** the cause.
- **The 2026-11-07 trial does not isolate a single cause.** Four things changed between that
  boot and this one:
  1. `--compress` (the trial stored the object uncompressed);
  2. the stub iBoot, 18000.161.10 then and 20457.41.3 now;
  3. the system firmware, 26.6.2 then and 27.3 beta 1 now;
  4. the Aura build, 1.0.0b9 then and b12 with our patches now.
- **No fix is proven, so no default was changed.** The next session is one variable at a time,
  in 1TR, and needs no new build. It starts with re-enrolling the same object **without
  `--compress`**. See "Retest plan".

Confidence:
- iBoot-level failure (iBoot panic, or a fault in Aura's first instructions that iBoot's own
  vectors catch): **medium**.
- Which of the four changes causes it: **low** until the panic report is read.

## Evidence

### The shipped object [verified]

Downloaded from `j714s-developer-image-omarchy-j714s-1` by HTTP range read of the zip parts, and
from `installer-build-inputs-j714s-d96c04cf8da5`:

| File | sha256 | Bytes |
| --- | --- | --- |
| image `esp/aurora/stage1-j714s.macho` = m1n1-aurora `aura-boot.macho` | `a42c3a94…65ac` | 1,818,624 |
| image `esp/aurora/stage1-j714s.bin` = m1n1-aurora `aura-raw.bin` | `f6963215…c91f` | 1,703,936 |

Load commands of the shipped object:
- `MH_FILESET` with 11 commands.
- No `__TEXT_BOOT_EXEC`, so `kcbz` is 0.
- `LC_UNIXTHREAD`: pc `0xfffffe0007014800`, which is raw + 0x800; x16 `0xfffffe0007014000`, which is
  Aura's `_vectors_start` (the value kmutil 27.2 records as `kcev`).
- `__TEXT` at `0xfffffe0007004000`. `__TEXT_EXEC` at file offset 0x10000, 0x1a0000 bytes.
- Aura's load header `AURALOAD` sits at raw + 0x808.
- The config block `AURORA-S1-CFG01` is at raw offset 0x118820, under Aura's 0x120000 DCP-log
  limit.

Then the engine's fill (`omarchy_asahi.fill_aurora_stage1` with `window_ms` 0 and
`m1n1/boot-ctxr.bin`) and carry (`omarchy_macho.fill`) were run, followed by the padding of
aura's `macho_boot_object.py --execute-window`. The padding is the same arithmetic as the Recovery
app's `expandExecuteWindow`: 16 MiB + 2 MiB − 16 KiB + 128 MiB. Result:
- 153,190,400 bytes;
- `__TEXT_EXEC` 0x91fc000, so `kcrz` is 153,141,248;
- `__PRELINK_INFO` at 0x920c000, `__DATA` at 0x9210000, `__LINKEDIT` at 0x9214000.

### The 2026-11-07 trial object [verified]

`~/m5/private/ctxr-v5b-evidence-20261108/fuos-stored-s4ctxr.img4` is the IMG4 that kmutil stored
in the stub's Preboot. Its payload is the 153,190,400-byte object `4f318f1b…` (extracted to
`~/m5/work/install-failure-20261113/trial-20261107-4f318f1b.macho`).

Compared byte for byte with the padded object above:
- The first 64 KiB differ only in the fileset and member `LC_UUID`s (0x28–0x37 and 0x81b0–0x81bf).
- `__DATA` and `__LINKEDIT` are identical.
- `__PRELINK_INFO` differs only by its UUID.
- Every segment address and size is identical, and so are the entry pc and `kcrz`.

| | 2026-11-07 trial (booted, Aura proxy on the cable) | omarchy-j714s 1 (fails) |
| --- | --- | --- |
| Wrapper, entry, padding, `kcrz` | as on the right | identical except UUIDs |
| Aura | 1.0.0b9-dirty. Raw image 0x3e0000. No `AURORA-S1-CFG01` block; its own proxy window | 1.0.0b12-g2232ae7a + our 0001–0009. Raw image 0x1a0000. Config: `window_ms` **0**, `m1n1/boot-ctxr.bin` |
| kmutil | the 26.6.2 stub's recovery, **no `--compress`**: the IMG4 holds the full 153 MB payload | the 27.2 stub's recovery, **`--compress`** (LZFSE in Preboot) |
| Stub iBoot | `mBoot-18000.161.10` (26.6.2, host clone) | `mBoot-20457.41.3` (26B123, assembled from the IPSW) |
| System firmware | 26.6.2 | 27.3 beta 1 (newer than the stub) |
| Security | `bputil -nc` then kmutil | the same: the app always runs `bputil -nc -v <VGID>` (`RecoveryBootPolicy`). There is no separate "permissive" path |

### What the upstream controls cover [verified]

- The K116s that boots a padded Stage 1 on 27.2 [reported, linux#1724] uses build **26B8125**.
  That IPSW's `iBoot.k116s.RELEASE.im4p` is also **`mBoot-20457.41.3`** (range-read here). The
  iBoot train is the same as ours. The differences are:
  - another board;
  - system firmware and stub firmware are the same build there, while ours are 27.3 beta 1 over
    27.2;
  - Jens's private Aura branches.
- aurora-installer at HEAD (5fc3946) pins 26B123 with **no boards admitted**
  (`scripts/firmware-qualification.json`: `"boards": {}`).
  - Aura has run from a 26B123 stub on a J813 (T8142) and a J873g (T8152) (aura d05ed948,
    8d439e68, 1db02321).
  - No T6050 has run from a 26B123 stub.
- aurora-installer enrols every M4-or-later Mac with `--compress`. A 256 MiB object has booted on
  a J700, and a 128 MiB object on a J616s, both on 18000.161.x OS firmware. Neither has been
  tested on a T6050 or on 27.2. Its README says "This 128 MiB size has not been booted yet" for
  its release flow.
- The stub file selection is the same in asahi `stub.py`, which our engine uses, and in
  aurora-installer's `NativeStubFilePlan`. Both skip `BaseSystem`, `OS`,
  `Ap,SystemVolumeCanonicalMetadata`, `RestoreRamDisk`, `RestoreTrustCache` and `Cryptex*`.

### Why "nothing on USB" says little [derived from Aura 2232ae7a]

- The engine fills `window_ms` 0 (`BOARD_MACHO["j714sap"].window_ms`). So even a healthy
  Stage 1 never opens a proxy on a normal boot.
  - `docs/move-to-27.2.md` Phase 0 step 3 planned `--window-ms 15000`.
- One proxy should still have appeared. `chainload_load()` opens `stage1_recovery_window()` when
  the PMU boot record shows that the previous boot stopped before an OS.
  - That record is read before Aura clears it (`stage1_read_boot_record()`, then
    `pmu_clear_panic_counter()` for T6050).
  - So, after several failed boots, silence means one of three things:
    - Stage 1 never reached `chainload_load()` on any boot;
    - the PMU record read fails on this Mac;
    - USB on the cable port does not come up under this Stage 1.
- Before its logo, Aura runs `firmware_init`, `gxf_init`, `mcc_init`, `mmu_init`, `aic_init`,
  `smp_init` and `pmgr_init`.
  - A fault there resets through `wdt_reboot()`: the Mac restarts by itself.
  - It hangs only if the ADT pointer isn't set yet.
  - That a `wdt_reboot()` reset really restarts a T6050 is **[derived]**: its ADT has
    `wdt-version` 3, and packaged Aura does not arm its own watchdog there.
- A fault in Aura's first instructions, before its vectors are installed, may be caught by iBoot's
  vectors and recorded as an **iBoot panic** after `fuos`. This is report 15's hypothesis H3, not
  a verified fact.
  - So an iBoot panic record does not by itself clear Aura. The breadcrumbs and the panic site
    narrow it down.

### Step 2 (cycling before any enrolment)

At step 2 no boot object was enrolled, so Mach-O, `--compress`, the entry point and Aura cannot
explain it. Two cases:
- Cycling is the documented result of booting the unfinished stub normally **[verified]**. The
  shipped engine's `main.py:791-793` says: "If you end up in a bootloop or get a message telling
  you that macOS needs to be reinstalled, that means you didn't follow the steps above properly.
  Fully shut down your system ...". Expect it whenever the Mac was started normally rather than
  through hold-power → Options.
- **Ask the owner whether step 2 looked like step 4** (progress bar, then off after a few
  seconds). If it did, the stub's normal-boot path (its Preboot firmware set, personalised for
  27.2 under a 27.3 beta 1 system) fails whatever object it boots. In that case ranks 3 and 4
  below move to the top.
  - The 1TR boot that worked probably uses the stub's Recovery-volume set, not its Preboot set.
    This is **[derived]** from the Asahi boot-flow docs and not checked on this Mac. If so, it
    doesn't rule this out.

## Ranked causes

| # | Cause | For | Against | Confidence |
| --- | --- | --- | --- | --- |
| 1 | **27.2 iBoot fails on the `--compress`ed 146 MiB fuos on this J714s**: a decompressed-size or placement limit in the 26B123 J714s iBoot, so iBoot panics after the load | The only J714s Mach-O boot was uncompressed. The progress bar and power-off match iBoot loading, then panicking. Compression is the one enrolment-side change | Compressed padded objects boot on J616s and J700 (other chips, 18000.161.x). K116s on 20457.41.3 probably used aurora-installer's `--compress` (not confirmed) | medium-low |
| 2 | **Aura b12 + our patches faults at or just after entry under the 27.2 hand-off** (first instructions, `gxf_init`/`mcc_init`/`smp_init` with the locked CTXR/RVBAR state) | Aura has never run as Stage 1 on a T6050 from a 26B123 stub. This build has never run on this Mac in any mode ("builds, not booted"). The b9 that booted here is far older. A fault before Aura's vectors exist may look exactly like an iBoot panic (H3) | Upstream main runs the same Stage 1 code on T6050 (J775D, K116s). Our patches touch only kboot hand-offs and PCIe, which run after the logo | medium-low |
| 3 | **Stub normal-boot firmware set from the IPSW** (personalised Preboot `boot/<nsih>`): a missing or mismatched piece under the 27.3 beta 1 system firmware | First stub this Mac has run that was assembled from an IPSW rather than cloned. Step 2 may have shown the same symptom | The stub's 27.2 recoveryOS boots. The selection equals asahi's and aurora-installer's. A failure in the firmware set ends earlier in the breadcrumbs (`sepi`, `isys`, `csys`, `trst`), not at `fuos` | low (rises if step 2 looked like step 4) |
| 4 | **27.3 beta 1 system firmware (LLB) under a 27.2 stub** on T6050, on the normal path | No Mac is known to run this pair. K116s runs a matched pair | The asahi rule allows an older stub, and the 27.2 recoveryOS boots under the same LLB | low |
| 5 | Entry point, slide, padding, `kcrz` or the 153,141,248 window | - | Byte-identical layout to the trial that booted here; `kcrz` is the value the trial enrolled | ruled out |
| 6 | The Stage 1 config fill changes the object after kmutil measures it | - | The engine fills before staging. Recovery checks the staged SHA-256, pads, and passes kmutil the final file, so the IMG4 digest covers the filled bytes. Nothing writes it after kmutil | ruled out |
| 7 | Wrong boot policy from "permissive" | - | `bputil -nc` then kmutil Mach-O is the trial's and upstream's order. Kernel CTRR comes back on at Mach-O enrolment, as Aura's doc expects. `bputil -d` will show it | very low |

## What to collect when the owner is back

Do everything read-only first. Nothing below changes the Mac.

### A. In the recovery the Mac is in now (Utilities → Terminal)

The Mac may be in the **system** recovery (PanicMedic or failed-boot fallback), not the stub's
paired one. Everything in A is read-only, so it works in either.

**Identify the new stub by volume group, never by name.** The image's volume name is "Omarchy",
and so is the old 27.3 stub's.

```sh
# 1. Failed-boot and panic markers iBoot left in NVRAM
nvram -p | grep -iE 'panicmedic|failboot|boot-volume|boot-note|panic' | sed -E 's/(boot-note|boot-info-payload)\t.*/\1 <omitted>/'

# 2. Containers, volume groups, and which group is the NEW (27.2) stub
diskutil apfs list
diskutil apfs listVolumeGroups
#    For each candidate group: its Preboot restore bundle names the build. The new stub says 26B123 / 26.2.123.
#    (mount that container's Preboot first: diskutil mount <PrebootDevice>)
for g in /Volumes/Preboot*/*/restore; do echo "$g"; grep -A1 -E 'ProductBuildVersion|RestoreLongVersion' "$g"/SystemVersion.plist "$g"/RestoreVersion.plist 2>/dev/null | grep string; done
VG=<that group's UUID>
SYSDEV=<that group's System volume device, from listVolumeGroups>
STUB=$(diskutil info "$SYSDEV" | awk -F': *' '/Mount Point/{print $2}')   # mount it first if empty
echo "VG=$VG STUB=$STUB"; cat "$STUB/Aurora/Recovery/State/installation.json" | head -5   # must exist only on the new stub

# 3. The stub's boot policy: Paired, security mode, Kernel CTRR, custom kernel hash
bputil -d -v "$VG"

# 4. What kmutil stored, and its size (compressed: well under 153 MB)
diskutil mount <the new stub's Preboot device>      # read-only use only
ls -l /Volumes/Preboot*/"$VG"/boot/*/System/Library/Caches/com.apple.kernelcaches/
ls -l /Volumes/Preboot*/"$VG"/boot/*/usr/standalone/firmware/ 2>/dev/null | head -50

# 5. The Recovery app's own log, receipt and the padded object it enrolled
ls -la "$STUB/Aurora/Recovery/State/"
cat  "$STUB/Aurora/Recovery/State/installation.json"
cat  "$STUB"/Aurora/Recovery/State/operation-*/installer.log
ls -ls "$STUB"/Aurora/Recovery/State/operation-*/stage1      # 153190400 bytes, sparse
kmutil inspect -z -B "$(ls -d "$STUB"/Aurora/Recovery/State/operation-*/stage1 | head -1)" --show-mach-boot-properties

# 6. Firmware versions
sysctl kern.osversion 2>/dev/null; nvram -p | grep -iE 'system-firmware|os-firmware' ; ioreg -p IODeviceTree -l -d 2 | grep -iE 'firmware-version|os-firmware' | head
```

Copy the output to a USB stick, or take photos. Step 5's `installer.log` holds the full
`kmutil inspect` and `configure-boot` transcript.

### B. In macOS (startup options → Macintosh HD, FileVault unlock)

```sh
# The panic report iBoot left. This is the key item.
ls -lt /Library/Logs/DiagnosticReports/ | head -20
sudo cat /Library/Logs/DiagnosticReports/*.panic | head -200     # look for "SOCD report detected: (iBoot panic)"
log show --last 3h --predicate 'process == "kernel" && eventMessage CONTAINS[c] "panic"' | tail -50
```

In the panic JSON, read:
- `panicString`;
- the SOCD record's `iBoot Panic: <hash>:<line> | ... | Build: RELEASE:mBoot-…`. The build tells
  which iBoot panicked: the stub's 20457.41.3 or the system's 20457.60.65.0.1;
- the **last breadcrumbs**. `fuos` completing 3000f/3000c/3000d/30010 and then the panic means
  hand-off or Aura's first instructions (causes 1 and 2). Stopping at `sepi`, `isys`, `csys`,
  `trst` or `dtre` means the stub's firmware set (causes 3 and 4);
- `PanicMedicEntryBootStage`.

Bring the `.panic` file and the stored `kernelcache.custom.*` back to the PC. Decompress its
LZFSE payload, then use `fuos-inspect.py` to compare it with `stage1`: the bytes iBoot got are
then known.

### C. Ask the owner

1. Did step 2 show the same progress bar and power-off as step 4?
2. Did the screen ever show the Omarchy logo or white text? Aura draws its logo before
   `run_actions`.
3. Did the Mac go to recovery by itself after several power-offs (PanicMedic or the failed-boot
   count), or did they hold power?
4. How long did "Finish setup" take, and did it report success?

## Retest plan (1TR, one variable per enrolment, no new build)

**Getting into the right 1TR.** "Finish setup" removed `.IAPhysicalMedia`, so picking the stub in
the startup picker now boots the failing object, not the stub's recovery. 1TR follows the
**default** startup disk; a one-time pick does not select the paired recovery (report 18
correction, report 21). So:
1. Make the new stub the default. It probably still is, because the app blessed it. Check in
   recovery with `bless --info --getBoot`. If it isn't, run
   `bless --mount "$STUB" --setBoot` and give the owner's password.
2. Shut down, wait 15 s, hold power until "Loading startup options", choose **Options**, and open
   Terminal.
3. Resolve `VG` and `STUB` as in section A, then gate on pairing:
   ```sh
   bputil -d -v "$VG" | grep -iE 'paired|one true recoveryOS|security mode|kernel ctrr'
   ```
   It must say **Paired**. If it doesn't, stop: a kmutil run here would not install (as in the
   2026-11-04 retracted cycles).

All objects below are Mach-O. Run `bputil -nc -v "$VG"` before each enrolment, as the app does.

**Confirm that each enrolment installed something new**, so a failure can't be another object
that was never installed:
```sh
ls -lT /Volumes/Preboot*/"$VG"/boot/*/System/Library/Caches/com.apple.kernelcaches/kernelcache.custom.*   # note names, sizes, times
# ... enrol ...
ls -lT /Volumes/Preboot*/"$VG"/boot/*/System/Library/Caches/com.apple.kernelcaches/kernelcache.custom.*   # a new file of about 153 MB (uncompressed) must appear
```
Then restart into the stub (it is the default), and watch the PC (`dmesg -w`) and the screen for
about 60 s.

1. **Without `--compress`, same object** (tests cause 1):
   ```sh
   S=$(ls -d "$STUB"/Aurora/Recovery/State/operation-*/stage1 | head -1)
   kmutil inspect -z -B "$S" --show-mach-boot-properties     # kcbz 0, kcrz 153141248
   bputil -nc -v "$VG"
   kmutil configure-boot -c "$S" -v "$STUB"                  # no --compress: about 146 MiB in Preboot
   ```
   - The Recovery app keeps its operation directory after a successful install **[derived]**: no
     code path removes it, and `installation.json` names it.
     - If `stage1` is missing, rebuild the same object on the PC. Fill the shipped
       `stage1-j714s.bin` with the `espUUID` from `$STUB/Aurora/Recovery/InstallData/install-config.json`
       and `m1n1/boot-ctxr.bin`, with window 0 (`aura-j714s-stage1 --raw stage1-j714s.bin
       --esp-partuuid <uuid> OUT`, or its two tools).
     - Check that the unpadded carry matches the receipt's `stage1SHA256`.
   - If it boots (Aura logo, then U-Boot or Linux), cause 1 is confirmed. The fix is below.
   - If not, go to 2.
2. **The 2026-11-07 trial object, uncompressed** (`4f318f1b`, in
   `~/m5/work/install-failure-20261113/trial-20261107-4f318f1b.macho`). Copy it to a FAT USB stick
   on the PC; Recovery can read it from `/Volumes/<stick>`. Then:
   `kmutil configure-boot -c /Volumes/<stick>/trial-20261107-4f318f1b.macho -v "$STUB"`.
   - It opens its own proxy, `aura uartproxy 1.0.0b9`, on the cable about 10 s after power-on.
   - **It enumerates:** the 27.2 iBoot, the stub and the 27.3 beta 1 system firmware hand off
     fine, and the fault is in our b12 Stage 1 (cause 2).
   - **It does not enumerate:** the fault is at the 27.2 stub, iBoot or system-firmware level
     (causes 3 and 4). The panic breadcrumbs then decide.
   - **What it boots after its window is not known.** No `chainload=` or ESP path could be found
     in the object, and the partition table has changed since 2026-11-07. Have the PC claim the
     proxy as soon as it enumerates (`~/m5/tools/m5catch.py`, which holds it in the proxy). If
     no PC is attached, the owner holds power to switch off once the result is seen.
   - Afterwards, re-enrol the object from retest 1 or the eventual fix. Don't leave the trial
     object enrolled.
3. Only if 2 points at Aura: on the PC, fill the shipped raw Stage 1 for the new ESP's PARTUUID
   (from `installation.json`) with `--window-ms 15000`. Wrap and pad it with the m1n1-aurora
   tools (`aura-j714s-stage1 --window-ms 15000`), enrol it uncompressed, and bisect Aura (b9 →
   b12 → +patches) through its proxy.

A further check needs no enrolment. If the old 27.3 stub still boots its raw m1n1 chain, run
`docs/move-to-27.2.md` Phase 1 R1 with the shipped `aura-raw.bin`, chainloaded from the
watchdog loader. It exercises this Aura build's pre-logo init on this Mac for the first time,
although under 27.3 beta 1 rather than the 27.2 hand-off.

To leave this state at any time: startup options → Macintosh HD, or the old 27.3 "Omarchy" stub
if it is still present. Both are unchanged.

## Fix

- **If retest 1 boots:** enrol without `--compress` on the J714s. Recovery app
  (`installer/patches-j714s/0002`):
  - `AuraBootMode.enrollmentArguments` stops appending `--compress` for this board. Better, the
    engine's macho mode manifest carries `"compress": false` and Recovery honours it.
  - `stageExpandedStage1` stops requiring `--compress` in `kmutil configure-boot --help`.
  - The free-space check already requires the whole 146 MiB.
  - The 60-minute timeout stays harmless.
  - Docs that say "`--compress`" for the J714s must change (`installer/README.md`,
    `patches/j714s-27.2/README.md`, `docs/move-to-27.2.md`).
- **In every case:** the J714s Stage 1 needs a proxy window while the line is a developer build.
  - Engine `BOARD_MACHO["j714sap"].window_ms` 0 → 15000, as `docs/move-to-27.2.md` planned.
  - The next failure then shows on the cable whether Aura ran.
  - The cost is 15 s per boot. Drop it once boots are routine.
- Not a fix: downgrading the system firmware (the rule is to stay on Apple's latest).

Nothing in `installer/patches-j714s` or the recipes was changed for this note. The retest picks
between the fixes above. omarchy-j714s 2, if built on the same patch set, repeats this enrolment
exactly (`--compress`, `window_ms` 0). Don't offer it for installation on a J714s until retest 1
or 2 has answered.

## Files

- Shipped object and inputs: `/tmp/inv-1113/` (scratch). Range reader `scripts/rzip.py`, Mach-O dump
  `scripts/machodump.py`, trial comparison `scripts/cmp_trial.py`.
- Saved for the retest: `~/m5/work/install-failure-20261113/` (trial object `4f318f1b`, an example
  padded object, the two scripts).
- Trial evidence: `~/m5/private/ctxr-v5b-evidence-20261108/`, `~/m5/private/smp-evidence-20261108-macho/`.

## Update 2026-11-13 afternoon: collected from macOS — the cause is simpler

Read-only, from macOS over ssh:
- The new 27.2 stub is volume group `44EF390C-16A3-4083-9AB8-5A72E15CAE3A` (`disk4s2`, mounted as "Omarchy 1"); NVRAM `boot-volume` points at it.
- `bputil -d -v 44EF390C-…`: **OS Pairing Status: Not Paired, Security Mode: Full, CustomKC/fuOS hash: absent.**
- The stub's `Aurora/Recovery/State` has only the 11:12 `app-update-*` (status `committed`, the macOS app installing the Recovery app). **No `operation-*` directory and no `installer.log`**: the Recovery app's "Finish setup" never ran an enrolment.
- No `.panic` report; NVRAM has `panicmedic-telemetry`/`panicmedic-timestamps` from the failed boots of the unenrolled stub.

So the 4-second progress bar and power-off is iBoot trying to boot a stub with no paired OS and no custom kernel, not a fault in our Mach-O object, `--compress` or Aura. The owner's recovery choice ("the permissive option") was not our Finish-setup flow, or was applied elsewhere; it did not reach this stub (still Full).

**Fix:** redo step 5 in the new stub's own recovery and complete Omarchy's "Finish setup" (it runs `bputil -nc` + `kmutil configure-boot`). The ranked causes above remain the plan B if a real enrolment then fails.

## Update 2026-11-13 12:50: enrolled correctly the second time; the loop is the NVMe hand-off (aura #213)

- The second 1TR "Finish setup" ran (`installer.log`: `bputil -nc`, `kmutil configure-boot … --compress`, kcrz 153141248, completed; policy Permissive, CTRR off, coih present). Stage 1's embedded config is right (ESP PARTUUID 7196bcf0-…, `m1n1/boot-ctxr.bin`, window 0).
- Symptom then: Omarchy logo (iBoot runs our Aura Stage 1, so `--compress` is fine), power-off, loop.
- **Cause (very likely):** release 1's Aura is main `2232ae7a`. It has `adf55805` ("power a post-M4 ANS off after use") but not `aaec599f` / aura #213 ("start a post-M4 ANS an earlier stage powered off before any payload"). Stage 1 reads Stage 2 from NVMe and powers ANS off; Stage 2 hands its embedded U-Boot a powered-off ANS; U-Boot can only adopt a running one (`Failed to probe 'nvme@…': err=-19`) and resets.
- **Fix without 1TR:** Stage 2 is an unsigned ESP file. `m1n1/boot-ctxr.bin` on the new ESP was replaced with release 2's Aura Stage 2 (main `22b71758`, has #213) + the original DTB/U-Boot payload tail (sha256 `c4211d92…`); original kept as `boot-ctxr.bin.orig`.
- **Result:** booted once into the new stub (one-time `bless --nextonly`) at 12:48; it did not fall back to the default (old) stub or macOS for 8+ minutes, where every earlier attempt looped within seconds. On-screen confirmation by the owner is pending.
- Release 2 already pins Aura `22b71758`, so it carries the fix. An installed release 1 must get m1n1-aurora v272-2 before any package update rewrites `boot-ctxr.bin`.
