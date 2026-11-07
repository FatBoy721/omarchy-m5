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
`arm64.nowfxt` and no `maxcpus` (`idle=nop` was needed until patch 0012).

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

### Aurora kernel with internal DCP (experimental)

This is a separate Linux kernel, not the Aura Mach-O Stage 1 trial. It
keeps the installed raw m1n1 and the SSD root filesystem. The default
`make kernel` still builds `vendor/linux`; `make kernel-aurora` builds
`build/linux-aurora` out of tree in `build/linux-aurora-out`.

The source is pinned to aurora-silicon/linux
`5b0f106acdd71de11400464adfeb8c87a83b20b0` (PR #1012), plus the ordered
series in `patches/linux-aurora/`. Configuration is
`configs/aurora-j714s.config`, merged after arm64 defconfig and
`asahi.config`. Preparation verifies the ordered patch identities, applies
only a missing suffix, and refuses conflicting tracked changes or history;
it never resets a source checkout.

From an already configured bring-up host:

```sh
scripts/apply-patches.sh
CHAINLOADING=1 scripts/build-m1n1.sh
cp vendor/m1n1/build/m1n1.bin build/m1n1-chain.bin
CHAINLOADING=0 scripts/build-m1n1.sh
make kernel-aurora
make initramfs
KERNEL_FLAVOR=aurora scripts/mktether.sh
# -> build/tether-aurora-bundle.tar.gz, containing tether-aurora/
```

The m1n1 rebuild includes patches 0007 (reserve live coprocessor log
buffers) and 0008 (internal DCP handoff). It is uploaded to RAM, **not**
enrolled with `kmutil`. The exact enrolled Stage 1 rollback image remains
untouched. To package another chain image explicitly, set
`M1N1_CHAIN=/path/to/chain.bin`.

Extract the Aurora bundle into its own directory on the tether host.
With the Mac in its resident m1n1 proxy:

```sh
cd tether-aurora
./chainload.sh
python3 hv/nvme-proxy-probe.py
python3 hv/wdt-arm.py 120
./boot-linux.sh
```

The NVMe preflight performs the existing cold-ANS preparation and reads
the GPT; it does not write the SSD. Linux subsequently mounts the existing
root read-write. USB serial loss at handoff is expected; use the panel
and USB-network SSH to check the result. See the IPv6 fallback above if
host routing prevents access to `10.55.0.2`.

**Display contract.** The tested stub is mBoot-20457.60.65.0.1
(macOS 27.3 beta 1, DCP firmware compatibility `27.2.98.1`). Method tags
and swap layouts differ between 27.x builds; never label a new build as
27.0 just to make the driver bind. m1n1 checks the running DCP, power
domains, locked DART tables and ADT/DT addresses before enabling the nodes.
It does not write those DCP, DART or PMGR registers. Unknown/invalid handoff
state leaves the nodes disabled; the driver rejects unknown method tables.

The 27.3 method map and request layout were derived from firmware dispatch,
size checks and field accesses, cross-checked with 27.0/27.2, then exercised
on this J714s. Patch 0013 handles the enlarged A458 swap request and shifted
method tags. Patch 0014 submits fbdev damage to the self-refreshing panel.
Patch 0015 uses ARGB and alpha-capable primary-plane formats: in a split
white-frame test only pixels with the fourth byte set to `0xff` were
visible, while `0x00` stayed black. Firmware binaries and runtime ADTs
are not included in the patch series.

**Observed on the Mac:** all 15 CPUs, SSD root, USB SSH, a readable
`appledrmfb` console, brightness changes through `apple-panel-bl`, and
display blank/unblank. The panel is 3024x1890 below the notch. Brightness
and display off/on were confirmed visually, not inferred from sysfs.
Awake SMC power averages at the console were 9.09 W at brightness setting 300 and
5.55 W blanked (15 samples each, keyboard light 200/255); this is not a
sleep-power measurement. A patched Hyprland desktop is now verified below;
lid suspend/resume still needs qualification on this kernel. There is no
GPU acceleration.

**Input configuration:** both `CONFIG_HID_MAGICMOUSE` and
`CONFIG_HID_APPLE_MTP_HAPTIC` must resolve to `y`. Aurora's optional haptic
dependency caps magicmouse at `m` when haptics is `m`; that silently left
the first DCP builds without a trackpad driver or firmware upload, even
though the fragment requested magicmouse `y`. This image does not ship
modules, so the build now checks the resolved input-driver configuration.
Do not add an AFE reset to work around a driver that has not bound.
The rebuilt tether bundle was boot-tested as Linux
`7.3.0-g96c096aaed23 #6`: magicmouse initialized MTP haptics, the
multi-touch interface became ready, and a physical swipe/click produced
222 position-axis events plus a left-button press and release. These were
read from the real trackpad event device; no synthetic input was injected.
The same packaged boot retained all 15 CPUs, SSD root and `appledrmfb`.

**Hyprland on the alpha-only DCP plane:** the packaged Hyprland 0.57.1
crashed with SIGABRT in `Render::IFramebuffer::alloc`, including in safe
mode. The Lua config passed `--verify-config` and was not the cause.
Initial mode tests assumed `XRGB8888`, but this primary plane advertises
`ARGB8888`/`ABGR8888`, not XRGB. GBM rejected every initial mode-test buffer,
leaving zero-sized monitor resources that hit the framebuffer assertion.
`start-hyprland` then repeatedly relaunched the same failing binary.

[`patches/hyprland/0001-output-support-alpha-only-scanout.patch`](../patches/hyprland/0001-output-support-alpha-only-scanout.patch)
targets upstream v0.57.1, commit
`acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9`. It chooses an advertised
eight-bit format before mode testing, retains the existing XRGB/XBGR
preference where supported, and adds ARGB/ABGR candidates to the eight-
and ten-bit format tests and diagnostic names. Do not restore false XRGB
advertising in the kernel or reinterpret XRGB buffers as ARGB.

The exercised Release build used Aquamarine 0.16.0, hyprutils 0.14.3,
hyprgraphics 0.6.0, hyprcursor 0.1.13 and hyprlang 0.6.8 from the Mac's
sysroot. It used hyprland-protocols 0.8.0 at
`cd1aba6bd78775825eb230b3a4274c48b6705eb7`, the pinned udis86 submodule,
and CMake's Glaze v7.2.0 dependency. CMake options were `Release`,
`NO_HYPRPM=ON`, `BUILD_TESTING=OFF`; the built target was `Hyprland`.
The cross-compiler was GCC 16.2.0, but its newer C++ headers introduced a
symbol absent from the Mac's libstdc++. The successful build used
`-nostdinc++` and the matching GCC 16.1.1 C++ headers, including the target
and `backward` include directories, from the cached package
`gcc-16.1.1+r12+g301eb08fa2c5-1-aarch64.pkg.tar.xz`.
Rebuild against the installed target dependency versions, not arbitrary
host headers or libraries.

The tested binary is installed at `/usr/local/bin/Hyprland`, with
`/usr/local/bin/hyprland` pointing to it. `/usr/bin/Hyprland`, installed
packages, and `~/.config/hypr/hyprland.lua` were not changed. Both command
names resolve to the local build, and the regular `start-hyprland`
launcher was exercised without a custom path. In an already-open shell,
clear any cached old executable path before the next launch:

```sh
hash -r
start-hyprland
```

This local override survives package upgrades, so rebuild or retire it
when the target libraries or upstream format handling change. To return
to the packaged binary, first exit Hyprland, remove only
`/usr/local/bin/hyprland` and `/usr/local/bin/Hyprland`, then run `hash -r`.
The unpatched 0.57.1 binary still needs the simpledrm/default-kernel
fallback; removing the override alone does not fix its DCP crash.

**Desktop proof:** on the same `7.3.0-g96c096aaed23 #6` boot, the patched
compositor started with the original config, reported `eDP-2` at
3024x1890 / 120 Hz / scale 2 with `currentFormat: ARGB8888`, and produced
no config errors. DRM reported an active primary-plane framebuffer at
that mode. Native Wayland Foot and Kitty windows rendered in captured
desktop images, and the user confirmed the desktop was visible on the
physical panel. The final installed build was then restarted through
the regular launcher and checked again with a native Kitty window.
Keyboard and MTP trackpad devices were enumerated by Hyprland.
This is basic desktop bring-up, not a performance, suspend or GPU test.
Aquamarine still logs failures to create its auxiliary GPU renderer on
this render-node-less device; those messages did not prevent software
composition and DCP scanout and were not hidden.

**Battery and charger telemetry:** the Aurora configuration now builds
`CONFIG_MACSMC_POWER=y`; the build rejects a modular result because this
boot path does not install kernel modules. `CONFIG_POWER_RESET_MACSMC`
remains modular and unloaded so watchdog-based remote reboot still works.
The default `vendor/linux` configuration still leaves battery support off.

Patch 0016 initializes the critical and debug work items once, before any
producer is published. Removal unregisters the SMC notifier, serializes the
debug parameter's device pointer, and synchronously drains the work before
device resources are freed. These are current-driver lifetime fixes, not
proof of the cause of the uncaptured 2026-10-02 battery-driver panic.
Firmware charging policy and critical-battery protection are unchanged.

On 2026-11-07, the patched driver was first tested as a module against the
exact running `7.3.0-g96c096aaed23 #6` kernel and configuration. It registered
`macsmc-battery` and `macsmc-ac`; the initial sample reported 81%, 12.825 V,
+3.178 A, 28.7 C, 5082/6345 mAh and 51 cycles. Both removal/reload checks
passed, including removal while the periodic debug work was active, with
no Oops, panic or warning trace. The pre-existing `b2bd_*` PMGR power-state
timeouts also appeared during module probes; this work does not fix them.

A real charger disconnect changed the battery to `Discharging` with
negative current/power, and reconnect restored `Charging` with positive
current. The kernel emitted battery status and AC online change events.
With the USB tether still attached, input fell to about 5 V rather than
zero: `macsmc-ac/online=1` does not mean the battery is charging. Read
`status` and signed `current_now`/`power_now` as well. Sysfs voltage/current/
power/charge values use micro-units; battery `temp` is tenths of a degree C.
No charge mode or charge threshold was written during these tests.

The packaged built-in image was then boot-tested as
`7.3.0-g1ad66d59b51b #7`: both power supplies registered automatically with
no modules loaded, and the running configuration matched the build exactly.
Battery telemetry survived the reboot alongside all 15 CPUs, SSD root,
USB SSH, `appledrmfb` and MTP keyboard/trackpad initialization, with no
Oops, panic or warning trace. The regular `start-hyprland` launcher restored
the unchanged desktop configuration at 3024x1890 / 120 Hz / ARGB8888;
a native Kitty capture showed the new kernel and battery state `Full`.
SMC hwmon is now `hwmon2` on this image, because battery and AC hwmon
registered first. Find it by `name=macsmc_hwmon`, not a hard-coded
`hwmon0` path.

For a battery-related boot regression, use the saved pre-battery Aurora
bundle or the default kernel through the same tether sequence. The local
pre-test archive is
`build/tether-aurora-7.3.0-g96c096aaed23-before-battery.tar.gz`.
`nomodeset` only disables the display driver, not the built-in battery driver.

**Fallback:** append `nomodeset` to the full cmdline from `boot-linux.sh`
using `BOOTARGS` to keep simpledrm on the Aurora kernel. To return to the
original kernel, reboot/power-cycle to m1n1 and use the default
`build/tether-bundle.tar.gz` instead. Its kernel/DTB are never replaced by
`make kernel-aurora`. The new m1n1 handoff was also boot-tested with the
default kernel: all 15 CPUs, SSD root, simpledrm and trackpad returned.
No boot-policy change is needed in either direction.

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

Kernel cmdline: `arm64.nowfxt kvm-arm.wfi_trap_policy=trap`. On this SoC WFI
loses x0-x30 and FP/SIMD on every core except the boot CPU; SP, PC and system
registers survive, and CYC_OVRD, which selects clock-gate-only WFI on M1-M3,
reads 0 on every core and is locked on M4 and later
([probe log](research/probe-logs/t6050-wfi-state-2026-11-07-j714s.log)).
Patch 0012 saves that state around WFI (dmesg: "Apple: preserving registers
across WFI") and patch 0013 registers cpuidle on T6050 with WFI in both
states, so `idle=nop` is no longer needed. WFIT/WFET bypass that save path:
keep `arm64.nowfxt` (patch 0009); a kernel that ignores it panics in
`__delay` on CPU1 with zeroed registers (check with
`zcat Image.gz | grep -a arm64.nowfxt`). `kvm-arm.wfi_trap_policy=trap`
keeps a KVM guest's WFI off the bare core. `tools/wfi-check.c` checks every
CPU (FP/SIMD and callee-saved registers across 1 ms sleeps;
`aarch64-linux-gnu-gcc -O2 -static -pthread`): on 2026-11-07 it passed
250,000 sleeps per CPU on all 15. Add `maxcpus=1` only on old stub firmware.

m1n1 reserves the coprocessors' `__OS_LOG` buffers that iBoot leaves inside
the RAM handed to Linux (DCP, DCPEXT0-3, MTP, AOP, AUSS; m1n1 patch 0007): the
firmware keeps writing its log there, and on one boot they sat in the CMA
area. They move between boots; `dmesg | grep oslog@` lists them.

Console: `console=tty0` on m1n1's framebuffer handed over as simplefb is
the only console needing no cable. dockchannel-UART (m1n1 secondary
channel) and serial0 (0x505200000, Samsung UART) both need the debug cable.

## Sleep (s2idle)

`systemctl suspend` (mem_sleep is `[s2idle]`) sleeps; opening the lid wakes
it. The wake path is the SMC: its mailbox interrupts are `IRQF_NO_SUSPEND`,
the RTKit worker is not freezable, and `macsmc-input` reports a hard wakeup
on lid open or on the power button (it drops `KEY_POWER` while waking, so
logind does not power off). Verified on this J714s on 2026-11-06: a 13-minute
sleep, lid closed then opened, back in about 1 s with all 15 CPUs, NVMe,
keyboard/trackpad and the USB gadget.

Cores idle in WFI since patch 0012: 5.6 W in total and 1.6 W for the SoC
("Heatpipe Power"), against 15.3 W and 9.7 W with `idle=nop` (SMC sensors,
same kernel, idle at the console with the panel and keyboard backlight on).
The default simpledrm kernel does not turn the panel off; the experimental
Aurora/DCP kernel can blank it, but has not yet been qualified for lid sleep.
Patch 0013 registers cpuidle, so s2idle freezes the tick and timekeeping:
on 2026-11-07, after a lid sleep of about 23 s,
`CLOCK_BOOTTIME - CLOCK_MONOTONIC` was 23.5 s (`suspend_stats` success 1,
fail 0; all 15 CPUs back). With `idle=nop`
timekeeping kept running and a long sleep tripped systemd's service watchdogs
(journald was restarted on wake).

Patch 0011 is required: the unused debug UART is runtime suspended with its
power domain (UART0) off, and its system-resume callback wrote the registers
anyway, an asynchronous SError. `pm_test=devices` hit it only from the second
cycle in a boot, after genpd had powered the idle UART down.

Testing without a real sleep: `echo devices > /sys/power/pm_test` (or
`platform`, which adds the late/noirq phases where genpd powers domains off),
then `echo freeze > /sys/power/state`; it resumes after 5 s. Set `pm_test`
back to `none` afterwards. `CONFIG_DPM_WATCHDOG` (5 s warning, 15 s panic)
names a resume callback that sleeps or loops; a callback that stalls the bus
shows nothing. To read the true last line of such a hang, rebuild with
`CONFIG_OMARCHY_FB_MARKERS=y` (base from m1n1's current `boot_args` video line)
and boot with `earlycon=efifb keep_bootcon console=ttynull`: the efifb
earlycon writes each line synchronously, while fbcon on simpledrm redraws from
a deferred worker and stops updating when the SoC hangs.

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
