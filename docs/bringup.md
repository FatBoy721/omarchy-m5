# Phase 1 bring-up guide - m1n1 → kernel → TTY on M5 Pro

The dev loop is tethered: an installed stage-1 m1n1 chainloads test builds
over USB, so kernel/DT iterations never touch boot policy. Partitioning and
`kmutil` happen once, up front; everything after is memory-only.

```sh
make setup    # brew llvm/lld/dtc/bc/bison/flex/openssl/make/gnu-sed
              # + rust aarch64-unknown-none-softfloat target
make fetch    # clone vendor/m1n1 (main) + vendor/linux (asahi-wip-7.2)
make m1n1     # CHAINLOADING=1 build -> vendor/m1n1/build/m1n1.bin
make dtbs     # overlay dt/ into the kernel tree, build t6050 DTBs only
make kernel   # full kernel (defconfig; KCONFIG=asahi_defconfig to override)
```

macOS quirks handled by the scripts: GNU Make/sed over the BSD versions
(kernel scripts use GNU sed syntax BSD sed silently passes through), and
`scripts/host-shim/` supplies the glibc headers macOS lacks (`elf.h` -
vendored musl copy - `byteswap.h`, `copy_file_range`, `O_LARGEFILE`).

## One-time on-device step (the risky part - do it once, carefully)

`scripts/prep-stub.sh` automates the mechanical half - run it with sudo:

```sh
sudo scripts/prep-stub.sh                  # stub + EFI only
sudo scripts/prep-stub.sh --linux-size 20G    # also carve the rootfs
```

It shrinks the macOS container, creates the 6 GB "Omarchy" stub
(Data+System+Preboot+Recovery volume group), clones this install's
restore bundle / `arm64eBaseSystem.dmg` / `AdminUserRecoveryInfo.plist`
into it (no IPSW download - everything is on-disk), and makes a 500 MB
EFI partition for m1n1. It prints the stub's VGID at the end. All in,
`--linux-size N` takes N + 6.5 GB away from macOS.

Then arm the stub so the picker hands control to *its* paired recoveryOS:

```sh
CHAINLOADING=0 make m1n1          # the installed stage-1 must not be a chainload build
sudo scripts/finish-install.sh    # asks for your macOS admin password (bless)
```

`finish-install.sh` reproduces the state asahi-installer leaves behind
(`src/stub.py` + `src/step2/`): it writes `Finish Installation.app` with
m1n1 as `Contents/Resources/boot.bin`, creates `private/var/db/dslocal` on
the Data volume, sets the APFS bootable fsctl on the System volume,
`bless --setBoot`es it, then hides `SystemVersion.plist` and drops
`.IAPhysicalMedia`.

That last marker is the whole trick: without it iBoot treats the stub as a
normal OS, finds no LocalPolicy, and the picker offers "reinstall". With
it the volume looks like install media, so the picker boots the volume
group's paired recoveryOS and auto-launches the app named in the plist.

Then, in one continuous motion:

1. Shut down fully, wait ~15 s.
2. Press and **hold** power until "Loading startup options..." (tapping
   twice reaches the picker but *not* 1TR - `step2.sh` will refuse).
3. Pick "Omarchy". Its recoveryOS opens a Terminal running `step2.sh`,
   which checks `bputil -d` for `: Paired` + `one true recoveryOS`, runs
   `bputil -nc` (credentials twice), then `kmutil configure-boot -c
   boot.bin --raw --entry-point 2048 --lowest-virtual-address 0`, and
   finally renames `.IAPhysicalMedia` away so the next boot goes straight
   to m1n1.
4. If no Terminal opens: Utilities → Terminal, then run
   `"/Volumes/Omarchy/Finish Installation.app/Contents/Resources/step2.sh"`.

Back out with `sudo scripts/finish-install.sh --undo`.

## Resizing or re-installing

The stub, the EFI partition and the Linux root sit together right behind
macOS (`disk0s2`), and an APFS container only grows into free space
directly after it. None of them can be resized in place: to give macOS
space back (or take more), delete all three, grow macOS, and install
again. That wipes the Arch root and the stub's boot policy, so the
ceremony above runs again.

1. Save what you want from the M5 (it is wiped), from the ThinkPad:

   ```sh
   ssh bay@10.55.0.2 'pacman -Qqen' > m5-pkglist.txt
   ssh bay@10.55.0.2 'sudo tar -C / -czpf - home/bay' > m5-home.tgz
   ```

2. In macOS, make it the default boot volume again **first**: System
   Settings → General → Startup Disk → Macintosh HD.
3. `diskutil list disk0`, and find the three by type and size, never by
   number (macOS renumbers `disk0sN` by disk position): the 6 GB
   `Apple_APFS` container with the `Omarchy` volumes, the `EFI` partition,
   and the `Linux Filesystem` partition. **Never** touch the first
   (`Apple_APFS_ISC`) or the last (`Apple_APFS_Recovery`) partition.
4. Delete them, re-running `diskutil list disk0` between commands, then
   give macOS all of the free space:

   ```sh
   sudo diskutil eraseVolume free free disk0sX     # Linux Filesystem
   sudo diskutil eraseVolume free free disk0sY     # EFI
   sudo diskutil apfs deleteContainer disk0sZ      # the 6 GB Omarchy stub
   sudo diskutil apfs resizeContainer disk0s2 0    # macOS takes the free space
   ```

   Grow macOS before re-installing: `prep-stub.sh` then shrinks it by
   exactly what it needs instead of leaving the old space unallocated. If
   the resize says `Storage system verify or repair failed`, run
   `diskutil repairVolume disk0s2` from recoveryOS and retry (Asahi's
   [partitioning cheatsheet](https://asahilinux.org/docs/sw/partitioning-cheatsheet/)
   covers this and the delete commands).
5. Build the stage-1 m1n1 (`CHAINLOADING=0 scripts/build-m1n1.sh`, on the
   ThinkPad or the Mac) and copy `vendor/m1n1/build/m1n1.bin` to the Mac as
   `~/m1n1-stage1.bin`.
6. On the Mac, in an up-to-date checkout:

   ```sh
   sudo scripts/prep-stub.sh --linux-size 20G
   sudo scripts/finish-install.sh --m1n1 ~/m1n1-stage1.bin
   ```

   then the power-hold → "Omarchy" → `step2.sh` ceremony above. Afterwards
   an unattended power-on lands in m1n1 again.
7. Provision the root, from the ThinkPad's tether directory with the M5
   in m1n1:

   ```sh
   ./chainload.sh
   python3 hv/nvme-proxy-probe.py      # prints the provision-rootfs line
   INITRAMFS=boot/initramfs-provision.cpio ./boot-linux.sh
   ```

   The new partition has no filesystem, so `/init` stays in its shell. On
   the M5's keyboard, type the `provision-rootfs START COUNT` line the probe
   printed, then `reboot -f` (the watchdog resets the M5 into m1n1; or
   power-cycle).
8. First boot from the SSD. The image only knows root (with the ThinkPad's
   `~/.ssh/*.pub` from when it was built) and `boot-m5.sh` waits for `bay`,
   so boot by hand once, then recreate `bay` and restore:

   ```sh
   ssh-keygen -R 10.55.0.2                    # the new root has a new host key
   ./chainload.sh && ./boot-linux.sh          # first boot grows / to the partition
   ssh -t root@10.55.0.2 'useradd -m -G wheel bay && passwd bay &&
       echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/10-wheel-bringup'
   ssh root@10.55.0.2 'pacman -Syu --needed --noconfirm -' < m5-pkglist.txt
   ssh root@10.55.0.2 'tar -C / -xzpf -' < m5-home.tgz
   ```

   From then on `./boot-m5.sh` does the whole cycle again.

## Status: boot policy is DONE (2026-09-21)

The ceremony completed on the M5 Pro. `bputil -nc` set Permissive (3rd
party kexts permitted, CTRR disabled, boot-args filtering disabled),
`kmutil configure-boot` registered m1n1 as the stub's custom boot object,
and the machine now boots iBoot → m1n1 stage1 → framebuffer console at
native 3024x1964 with DARTs initialized. `nvram boot-volume` points at the
stub VGID, so an unattended power-on lands in m1n1, **not** macOS; get
macOS back with power-hold → picker → Macintosh HD (still Full Security).

## Stub firmware refresh (all cores)

The stage-2 firmware (iBoot/mBoot) that loads m1n1 comes from the Omarchy
stub's own Preboot restore bundle, which `prep-stub.sh` cloned from macOS at
install time. Updating macOS replaces LLB (`/chosen/system-firmware-version`)
but not that bundle (`/chosen/firmware-version`, m1n1's "OS FW version").
Apple's fix for "only a single core is available ... custom raw boot object"
on M5 Pro/Max/Ultra shipped in macOS 27.3 beta 1 (26C5035r), so the stub must
be rebuilt from 27.3 beta 1 or later:

1. Update macOS (the main volume) to 27.3 beta 1 or later. Back up first:
   firmware cannot be rolled back.
2. In macOS, from a checkout (only `scripts/` is needed):

   ```sh
   sudo scripts/refresh-stub-firmware.sh check
   sudo scripts/refresh-stub-firmware.sh recreate --yes
   ```

   `recreate` backs up the stub's restore bundle(s), boot folder and current
   `boot.bin` to `~/omarchy-stub-backup-<VGID>`, deletes only the stub's four
   APFS volumes, then reruns `prep-stub.sh` (resume mode: no resize, no new
   partitions) and `finish-install.sh` with the same m1n1. macOS, the EFI
   partition and the Linux root are untouched. Refreshing in place fails at
   `bless` with bootpolicy error 11 ("AP boot mode"), hence the recreate
   (found by rolotrealanis98/m5pro-linux).
3. Shut down, hold power until "Loading startup options", pick Omarchy.
   step2 runs `bputil -nc` and `kmutil`; expect the admin password prompt more
   than once. The new stub is blessed as the default startup disk.
4. On the host, m1n1's banner shows `OS FW version: ... (mBoot-20457.60.65.0.1)`
   or later, and `p.smp_start_secondaries()` prints `Started.` for all 14
   secondaries.

Verified on this J714s on 2026-11-06: before, `mBoot-18000.120.36` and 14/14
`Failed!`; after, 14/14 `Started.` with the unchanged installed m1n1
(v1.6.1-28-g4184923f). The tether bundle then boots Linux with
`idle=nop arm64.nowfxt` and no `maxcpus`.

After starting secondaries from the proxy (probes), reset the Mac
(`hv/wdt-arm.py 5`) before chainloading: a chainloaded m1n1 expects them off.
A watchdog reset lands on the default startup disk.

## Aura Mach-O diagnostic trial (J714s)

This is an alternative to the installed raw Stage 1, not an installer rerun.
It integrates Aura **v1.0.0b4**, commit
`8b15096337e97f934438e1e7f3e96182440351dc`, including
[the Mach-O boot object](https://github.com/aurora-silicon/aura/pull/29) and
[the all-chip monitor probe](https://github.com/aurora-silicon/aura/pull/62).
Upstream's documented Mach-O hardware result is T8140, not our J714s.
Neither M5 Pro SMP nor PMP/GPU operation is claimed by this integration.
SMP no longer depends on it (see [Stub firmware refresh](#stub-firmware-refresh-all-cores));
it remains an untested alternative Stage 1.

### Build without changing the working boot artifacts

From the configured host checkout, with the existing kernel build and a saved
copy of the **enrolled** raw Stage 1 at `build/m1n1-enrolled-stage1.bin`:

```sh
make aura-test
python3 scripts/prepare-aura-test.py --verify build/aura-test
```

For a different verified backup path, use
`make aura-test AURA_ROLLBACK=/path/to/known-good-stage1.bin`.
Preparing the bundle directly requires an explicit `--rollback` argument.
On this J714s, reading the active Preboot custom IMG4 payload established that
the enrolled raw image matches the Mac's installer resource, but differs from
our newer local `build/m1n1-stage1.bin`. The original local build is preserved;
the recovered enrolled payload is the rollback source. Do not infer enrollment
from an artifact's filename.

Use Python 3.11+ and the existing LLVM/Rust build dependencies. `vendor/aura`
is separate from `vendor/m1n1`; a different revision or tracked edits are
refused rather than overwritten. The kernel builds in a temporary copy of
`vendor/linux`, with the same DT/config except its local-version suffix and
`CONFIG_OMARCHY_FB_MARKERS` disabled. Fixed physical framebuffer addresses are
not carried across the boot-object change. Initial display output now depends
on the normal simplefb/simpledrm handoff, not the old colored markers.

Outputs are in `build/aura-test/`, also packaged as `build/aura-test.tar.gz`:

- `boot/aura-boot.macho`: the **enrollable** Mach-O boot object, not `aura.macho`.
- `boot/aura-stage1.bin`: its exact raw partner. The factory Stage 1 config is
  deliberately unfilled: no ESP target or automatic disk boot. `CHAINLOADING=1`
  enables Aura Stage 1 support; `RELEASE`, `ESP_STAGE2` and NV2 build flags are off.
- `boot/Image.gz`, `boot/t6050-j714s.dtb`, `kernel.config`: isolated kernel artifacts.
- `boot/initramfs.cpio.gz`: RAM-only diagnostics, console shell and explicit
  `smp-check`. It ignores `m5.root`, does not mount block filesystems, write
  `/dev/mem`, start USB gadgets or include provisioning helpers. Task affinity
  uses the pinned Alpine util-linux `taskset`, not a missing BusyBox applet.
- `rollback/m1n1-stage1.bin`: a copy of the saved local raw image. **Identify it
  as the known-good installed Stage 1 before relying on it for recovery.**
- `SHA256SUMS`, `manifest.json`, the matching Aura proxyclient and tether commands.

The verifier compares the complete deterministic upstream Mach-O encoding,
including the entry/vector addresses and zero padding, with the paired raw
image. It also refuses a filled Stage 1 config or unexpected build flags.
It does not replace Apple's native inspection.

### Native preflight, approval and rollback

Copy the bundle to existing storage accessible from the Mac's Recovery; keep
the rollback image there too. Do not format storage for this. In normal macOS,
from the unpacked bundle directory, run the read-only checks:

```sh
shasum -a 256 -c SHA256SUMS
kmutil inspect -B "$PWD/boot/aura-boot.macho" --show-mach-boot-properties
diskutil apfs list
```

Require **`kcbz : 0`**. Identify the actual **Omarchy System volume and its
volume-group UUID**, not a guessed disk number and never Macintosh HD. Record
the current firmware version and establish that the saved raw image is the
working fallback. Checksum equality alone does not establish that provenance.

Enter the target's paired one-true Recovery and verify it with
`bputil -d -v "$VGID"` (`: Paired` and `one true recoveryOS`). Set `TARGET` to
that verified mounted System volume and `BUNDLE` to the absolute bundle path
as visible in Recovery. If pairing or volume identity is unclear, stop.
**Obtain explicit approval for that exact target and image before enrolling.**

Only after those checks and approval:

```sh
kmutil configure-boot -c "$BUNDLE/boot/aura-boot.macho" -v "$TARGET"
```

There is **no `--raw` or entry-point argument** for this image. Do not run
`prep-stub.sh`, `finish-install.sh`, `bputil -nc`, partitioning, or a security
reset for this already-installed trial. Enrolling this Stage 1 is the persistent
change; the later Linux payload and diagnostic userspace are loaded into RAM.
Chainloading Aura behind the old raw Stage 1 does not test this iBoot path.

If the candidate hangs or loses USB, shut down and use the power-hold startup
picker to return to macOS/Recovery. From the **same verified paired Recovery
and target**, the approved rollback command is:

```sh
kmutil configure-boot -c "$BUNDLE/rollback/m1n1-stage1.bin" \
  --raw --entry-point 2048 --lowest-virtual-address 0 -v "$TARGET"
```

`finish-install.sh --undo` is not a boot-object rollback.

### Tethered test after a cold boot of the enrolled image

On the host, in `build/aura-test` (use the actual enumerated serial device):

```sh
python3 -m venv ../aura-client-venv
../aura-client-venv/bin/pip install -r requirements.txt
export PYTHON="$PWD/../aura-client-venv/bin/python"
export AURADEVICE=/dev/ttyACM0
set -o pipefail
./probe-smp.sh --start 2>&1 | tee aura-smp.log
```

The probe checks the J714s identity, reads only selected metadata and requests
secondary startup once. It does not scan MMIO or access PMP. Standard
`aura.setup` does reset the PMU panic counter. This machine has **15 CPUs**:
ADT IDs `0-4,6-10,12-16`; absent IDs 5, 11 and 17 are the binning, not failed CPUs.
The boot CPU is counted from ADT state because Aura's secondary liveness flag
does not represent it. If starts fail, preserve the log and stop the SMP trial.

First test Linux with:

```sh
./boot-linux.sh --single
```

`maxcpus=1` limits Linux, **not** Aura: upstream `linux.py` still attempts
secondary startup before preparing the DT. The command uses `idle=nop` and
`arm64.nowfxt` for our existing kernel; `idle=poll` is not its arm64 option.
No SSD root argument, TSO override or NV2 request is passed.

After a successful first boot, cold-boot Aura again for:

```sh
./boot-linux.sh --smp
```

On the Mac's diagnostic console run `smp-check`. Capture Aura's start results,
any monitor/heap-probe messages, Linux's `CPU: All CPU(s) started at EL1` or EL2
message, online CPU count, advancing uptime and each per-CPU PASS/FAIL result.
With no live secondary, the monitor probe cannot establish confinement and
does not select the EL1 path. That is a prerequisite to observe, not evidence
that the new Stage 1 has already solved secondary startup.

Host validation: the candidate builds; its embedded kernel config matches the
packaged config; original raw-loader/kernel artifacts remain byte-identical.
Corrupt/mismatched Mach-O pairs and non-factory Stage 1 config were rejected.
The diagnostic image booted under QEMU with a separate generic arm64 kernel;
its console and CPU checks passed with online sets `0-2` and `0,2`, and only
RAM/pseudo filesystems were mounted despite an `m5.root` argument. This validates
the diagnostic userspace, **not the M5 Pro boot path**.

Native preflight on this J714s (macOS 26.5 / 25F71, firmware 18000.120.36)
also passed: the transferred bundle's checksums match, and Apple's `kmutil
inspect` accepts the candidate and reports `kcbz : 0`. The rollback payload was
recovered from the active Preboot custom IMG4, not guessed from a local build.
Preboot was mounted read-only for that check and unmounted afterward. No boot
policy was changed. Enrollment and Linux boot through the candidate remain
pending; normal macOS inspection is not a hardware boot test.

## Dev loop

Two loops. The tethered one is the real one; the standalone one exists
because the target and the build host are the same laptop when no second
machine is around.

### Tethered - the normal loop (Arch ThinkPad over USB-C)

The M5 is the target, so the proxyclient has to live on the other
machine. `scripts/mktether.sh` packs everything it needs - proxyclient,
kernel, DT, initramfs, a chainloadable m1n1, the udev rule and runners:

```sh
make initramfs
CHAINLOADING=1 scripts/build-m1n1.sh && cp vendor/m1n1/build/m1n1.bin build/m1n1-chain.bin
CHAINLOADING=0 scripts/build-m1n1.sh     # restore the installed-image config
scripts/mktether.sh                      # -> build/tether-bundle.tar.gz
scp build/tether-bundle.tar.gz thinkpad:
```

On the host (once): `pacman -S python-pyserial python-construct`,
`cp 80-m1n1.rules /etc/udev/rules.d/`, `udevadm control --reload`,
`usermod -aG uucp $USER`. The rule matches the gadget (1209:316d) and
creates `/dev/m1n1` (proxy) and `/dev/m1n1-sec` (m1n1's own console).
Then:

```sh
./boot-linux.sh                                  # kernel + dt + initramfs
BOOTARGS="maxcpus=1 initcall_debug" ./boot-linux.sh
./chainload.sh                                   # iterate on m1n1 itself
```

Note the upstream tools take **positional** arguments
(`linux.py <Image.gz> <dtb> [initramfs] -b "<cmdline>"`); the runners in
the bundle wrap that. Iterations are memory-only - the installed boot
object is never rewritten, and a bad boot just needs a power-cycle.

With the stub on mBoot 20457.60 or later, every secondary prints `Started.`
and Linux brings up all 15 CPUs. On older stub firmware each prints `Failed!`
after 100 ms (about 1.4 s total, not fatal); boot with `maxcpus=1` then.

If the host cannot reach `10.55.0.2` over IPv4 (a Tailscale exit node on the
host routes `10.55.0.0/24` into its own table), the gadget's link-local
address works: `ssh bay@fe80::4d:35ff:fe00:2%<host gadget interface>`.

If proxyclient doesn't enumerate, try the other USB-C ports - the gadget
binds to one specific dwc3 port.

### Standalone (no second machine - one 1TR ceremony per image)

m1n1 parses everything appended after its own image as a payload chain
(`src/payload.c`), so the kernel, DT, initramfs and cmdline ship inside
the boot object itself:

```sh
make initramfs   # Alpine aarch64 busybox+musl, repacked as newc cpio (no root)
make payload     # m1n1 | chosen.bootargs=… | Image.gz | dtb | initramfs.cpio.gz
sudo scripts/finish-install.sh --m1n1 build/m1n1-payload.bin
# then repeat the power-hold → picker → "Omarchy" ceremony
```

`mkpayload.sh` re-walks the assembled file with the same magics m1n1 uses
and fails if the chain doesn't parse, so a bad `cat` never reaches the
ceremony. Use this for milestone boots; it costs a ceremony per kernel, so
it is not an iteration loop.

Kernel cmdline: `idle=nop arm64.nowfxt`. M5 secondaries lose state in WFI and
in WFIT/WFET; a kernel that ignores `arm64.nowfxt` (built without patch 0009)
panics in `__delay` on CPU1 with zeroed registers. Check with
`zcat Image.gz | grep -a arm64.nowfxt`. Add `maxcpus=1` only on old stub
firmware.

Console: `console=tty0` on m1n1's framebuffer handed over as simplefb is
the only console needing no cable. dockchannel-UART (m1n1 secondary
channel) and serial0 (0x505200000, Samsung UART) both need the debug cable.

## DT state (populated from the real J714s ADT)

`dt/t6050-pmgr.dtsi` is generated, not hand-written:

1. Extract the ADT: `devicetree.img4` lives in the booted OS's Preboot at
   `usr/standalone/firmware/devicetree.img4`. Strip the IM4P header and
   LZFSE-decompress the `bvx2` payload (macOS `libcompression` handles it).
2. `scripts/adt2pmgr.py adt.bin > dt/t6050-pmgr.dtsi` - a fixed fork of
   m1n1's `pmgr_adt2dt.py` (upstream crashes on T6050's die-level parent
   IDs 219/325/609, which have no device entry).

Verified on J714s (macOS 26.5): 405 power domains across 6 PMGR blocks;
real IRQs/npins for uart/i2c/spi/gpio/wdt/dockchannel; CPU topology
15 cores (5+5+5, binned - cpu5/cpu11/cpu17 disabled in the board DTS).
Remaining TODO(adt) markers: AIC event region, PMU FIQ affinities,
pinmux tables, which SPI bus carries keyboard/trackpad.

Note: ADT `reg` values sit 0x2_0000_0000 below the MMIO address on this
SoC (uart0 ADT 0x305200000 → MMIO 0x505200000, matching m1n1's
EARLY_UART_BASE). Apply the same offset when converting new nodes.

## Success metric

Reproducible boot to getty: single core, on-device display (simplefb) or
dockchannel console, NVMe rootfs optional for the first milestone.

## References

- `docs/PLAN.md` - phase plan
- `docs/research/kernel-boot-m5.md` - blockers (SMP, WFI, NVMe fwabi)
- `docs/research/dualboot-partitioning.md` - stub/1TR/kmutil mechanics
- qspqww/m1n1 `t6050-j716c-bringup` - real-hardware M5 Pro/Max notes
  (findings.md, bringup/t6050-j716c/LINUX_PC_BRINGUP_GUIDE.md)
- ImAtomiskk/asahim5 - t8142 (base M5) DT + ADT dump, closest public
  reference for what a hand-authored M5-gen DT looks like
