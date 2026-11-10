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

### GPU trial (isolated J714s)

This local trial keeps the verified DCP/battery and default bundles intact.
Native rendering/compute and Vulkan-backed Zink now pass on this J714s in
the separate **simpledrm / Linux-DCP-off** profile. The two exercised boots
used `7.3.0-g929e67a1da3e`; the second also verified the corrected loader's
watchdog retention. Those headless checks are separate from the Zink desktop
checkpoint below; GPU+DCP, suspend and sustained-load qualification remain open.

Sources:

- Aurora Linux [PR #1173](https://github.com/aurora-silicon/linux/pull/1173),
  pinned at `34f2f5bb4d03bbe3acce237cb67af8dc9972aa4a`, followed by the
  existing sixteen Aurora patches and `patches/linux-aurora-gpu/`.
- The existing m1n1 base `4184923ffb2dff079b384d6a32cc02142aa14572`,
  reconstructed in `build/m1n1-gpu-simpledrm` with patches 0001–0004,
  0007–0009, plus `patches/m1n1-gpu/`. The GPU handoff is a licensed local
  adaptation of commit `2bebfe7708c7077377ecc0d80d29bfb458335c0d` from
  [m1n1 PR #37](https://github.com/aurora-silicon/m1n1/pull/37).
  It does not import the N1/USB-host bootloader stack or start PMP.
- Mesa [PR #194](https://github.com/aurora-silicon/mesa/pull/194),
  pinned at `043a4c58080c4951fea3797fe45fc6898ce77632`.
- The working
  [other-J714s report](https://github.com/TripleU613/Omarchy-M5-Pro/blob/13cc8196396ef2029ec0931f17fcb0ff9ad73c21/STATUS-2026-11-08.md)
  motivated the explicit DCP-off profile, not a claim that GPU+DCP works.
  The [draft J714s voltage PR](https://github.com/rolotrealanis98/linux/pull/1),
  reviewed at `77782baf9d4923e42b3bc20f2bb816789c5afba8`, was **not applied**:
  all 13 active main voltage rows differ from this Mac's data.
- Private Vulkan Loader `9e9518d2cf00054a220ae1a40f4406804b420ef5` and Headers
  `6802bb4733b63ed5efd3adb308a6c885ef180ea1` are pinned to v1.4.363, matching
  Mesa's bundled header revision.

The J714s voltage tables come from the private runtime ADT captured on
2026-11-06, SHA256
`e68662cd086179dd7fdebdd3046eec4fbf27aa287b266a7e0a550434a8ad2017`.
They describe this device, not every J714s. `boot-linux.sh` checks the live
model, both firmware-version properties and all four raw voltage-table
hashes before invoking Linux. Its `hv/gpu-preflight.py` reads only boot
arguments and ADT RAM; unlike `m1n1.setup`, it does not reset the PMU panic
counter or change the proxy heap. Raw ADT captures remain private.
Firmware-version metadata is not image attestation: the GPU driver must
also admit the actual loaded firmware through its exact-image checks.

| Device-specific value | This J714s | Reported peer J714s |
| --- | --- | --- |
| Top GPU frequency | 1620 MHz | 1620 MHz |
| Top-state core / SRAM voltage | 1055 / 1055 mV | 1025 / 1010 mV |
| Enabled-core masks, per cluster | `0x3bb`, `0x37b` | `0x3db`, `0x3db` |
| Enabled GPU cores | 16 | 16 |

Our masks were read through the live driver's GET_PARAMS ioctl, not inferred
from the SKU or the packed raw register debug value. The existing driver
already rejects out-of-geometry and aggregate-zero masks before starting
firmware; no additional mask workaround was needed.

The trial DT leaves the GPU, both native mailboxes and all six firmware/UAT
reservations disabled. The matching loader validates the current ADT
ranges, role addresses, IRQs and bindings before enabling the GPU. The
old loader leaves this GPU DT disabled, providing the control boot.
No firmware physical address is baked into the DT.
The `aurora-gpu-simpledrm` DT additionally marks DCP with
`apple,m1n1-simpledrm-only`. Its private loader disables the Linux DCP
bindings before DCP hardware checks, without shutting down native display
firmware or disabling the chosen simple-framebuffer. Marker-less DTs retain
the original DCP handoff. Both GPU display profiles share the
`build/linux-aurora-gpu` kernel source/output tree, but have separate DTs,
loader trees, loader binaries and tether archives.

**Build:** use a Rust compiler with matching `rust-src`, LLVM/Clang, and
the normal cross-build prerequisites. This host used Rust 1.99.0 for the
kernel and LLVM 23.1.3. Prepare the branch's corrected bindgen once; stock
bindgen failed the mandatory C/Rust alignment assertions. Never disable
those assertions or change scheduler configuration to mask that defect.

```sh
KERNEL_FLAVOR=aurora-gpu-simpledrm scripts/build-kernel-aurora.sh prepare
# Only if this private generator has not already been prepared:
python3 build/linux-aurora-gpu/tools/aurora-bindgen/build.py
RUSTC="$(rustup which --toolchain stable rustc)" make kernel-aurora-gpu-simpledrm
make m1n1-gpu-simpledrm
```

Mesa uses a private snapshot of the existing target SDK,
`build/hyprland-dcp-sysroot`; it does not update system Mesa or that SDK.
Its host shader tools need the matching LLVM development libraries.
The bootstrap steps are one-time local preparations, not global installs:

```sh
scripts/build-mesa-gpu.sh bootstrap
scripts/build-mesa-gpu.sh bootstrap-host
scripts/build-mesa-gpu.sh build
KERNEL_FLAVOR=aurora-gpu-simpledrm scripts/mktether.sh
tar -xzf build/tether-aurora-gpu-simpledrm-bundle.tar.gz -C build
```

The packer removes its staging directory after archiving, so extract the
bundle before using it. Mesa's separate archive is
`build/mesa-gpu/mesa-j714s-gpu-043a4c58080c.tar.gz`; all its contents are under
`/opt/mesa-j714s-gpu-043a4c58080c`. The wrapper scopes the experimental M5
enable flag, EGL/GLX/Vulkan selection and caches to one process tree.
It clears software forcing and shim/preload settings in that subprocess;
no software GPU driver or shim is packaged.

The initial target Zink attempt failed before rendering because
`libvulkan.so.1` was absent. A DT_NEEDED dependency audit cannot catch this
runtime-loaded dependency. The builder now includes the pinned Vulkan
loader, licenses and provenance; packaging rejects an absent/invalid loader.
For an already-built private Mesa stage, `scripts/build-mesa-gpu.sh runtime`
adds the loader and repackages without repeating Mesa or shader-tool setup.
It also emits a `*-vulkan-runtime.tar.gz` delta containing only the private
loader/runtime metadata. That delta was deployed to the existing `/opt`
prefix; all ten installed ELF payloads match the completed package's stage.
Neither `/usr` libraries nor the user's compositor configuration was changed.

**Offline evidence:** the real loader C handoff passed fourteen cases using
the compiled DTs and saved ADT: exact ranges/mailboxes, unchanged baseline
and marker-less DTs, malformed-resource rejection and explicit simpledrm
isolation. Twelve additional cases exercise the actual C boot-argument
layout and watchdog function against Python-serialized revisions 1–3,
including leading, embedded and end-of-capacity retention arguments and
nonzero trailing-field sentinels: **26 cases pass**. These host checks do not
exercise the target Rust ADT FFI or prove a physical watchdog reset.
The live calibration check accepted this Mac and rejected seven offline
identity/table mutations. The earlier nine-ELF QEMU dependency check was
userspace compatibility evidence, not GPU work; the later real Zink run
proved the added dynamic Vulkan-loader dependency.

Run the host handoff/ABI checks without connecting to the Mac:

```sh
python3 patches/m1n1-gpu/smoke-handoff.py \
  --adt build/adt-runtime-j714s-unattended-20261108T213635Z.bin \
  --dtb build/linux-aurora-gpu-out/arch/arm64/boot/dts/apple/t6050-j714s-gpu.dtb \
  --default-dtb build/linux-aurora-out/arch/arm64/boot/dts/apple/t6050-j714s.dtb \
  --simpledrm-dtb build/linux-aurora-gpu-out/arch/arm64/boot/dts/apple/t6050-j714s-gpu-simpledrm.dtb
```

Use the corresponding private saved runtime ADT if its local filename differs.

**2026-11-08 control checkpoint:** the known-good loader booted
`7.3.0-g13d170d6b6f4` with CPUs `0-14`, `/dev/nvme0n1p5` ext4 root
read-write, USB IPv6 SSH, `appledrmfb`, both SMC power supplies and enumerated
MTP keyboard/multi-touch devices. Battery reported Full/100% and 26.6 C.
The live GPU DT status was `disabled` and there were no render nodes.
At that earlier checkpoint, no GPU-enabled loader boot, target Mesa
installation, accelerated rendering or compositor test had been performed.
The installed boot object and both recovery bundles were unchanged.

This is not full qualification. The captured log contains `b2bd_*` power-state
warnings, PMGR deferred-probe timeouts, a multi-touch start timeout, and an
unclean FAT-volume warning for `nvme0n1p4`. Devices enumerating is not proof of
working gestures. No Oops, panic, SError or lockup was found in the captured
log; no filesystem repair was attempted. The offline comparison below
separates existing warnings from the touch failure. Local evidence is saved in
`build/gpu-control-2026-11-08.json` and
`build/gpu-control-2026-11-08-dmesg.log`.

**Offline follow-through (no target access):**

- The control's AFE firmware reports `Failed to attach to AFE (-6)`,
  `No HINT_L (-6)` and `AFE[0] bootload failed` at about 2.18 seconds,
  before the multi-touch timeout at 4.19 seconds. It never reports multi-touch
  READY in the saved log. In contrast, the complete battery, packaged-trackpad
  and DCP fallback logs all reach `Touch interface ready` without that timeout.
  The management-interface READY message and an enumerated input device are
  not substitutes for touch READY or working gestures.
- The complete DockChannel HID **source file** is byte-identical in the two
  build trees, and the fallback/trial archives contain byte-identical
  initramfs images. The compiled DT diff adds the disabled GPU handoff nodes
  and aliases, plus a consistently renumbered keyboard-backlight PWM phandle;
  it does not change MTP bindings. The saved November 6 and control-preflight
  ADTs also have identical MTP transport/interface properties; the reviewed
  MTP IOP nodes differ only in `segment-ranges`. These checks do not establish
  why the AFE failed, nor prove the two kernels behave identically. No timeout
  increase, speculative SMC reset sequence or driver patch is justified yet.
- The `b2bd_*` failures and the same six ATC0/1/2 CIO/PCIe deferred providers
  already occur in the battery baseline. Both compiled DTs resolve those
  providers to their respective `atc*_common` parents. The GPU and both native
  mailboxes are disabled and reference `gfx -> afr + gpx`, not those six ATC
  providers. `APPLE_PMGR_PWRSTATE`, `APPLE_PMP_REPORT` and `APPLE_PMC` are already
  enabled in both configs. This is a static dependency check, not proof that
  GPU power transitions work; it is not a reason to enable or poke PMP/PMC.
- `Malformed early option 'earlycon'` also predates this trial. These DT-only
  builds disable `CONFIG_OMARCHY_FB_MARKERS`, whose diagnostic initializer
  supplies the EFI `screen_info` used by `earlycon=efifb`. Normal display output
  instead starts through simpledrm/fbcon and later DCP. The packaging comments
  now state that limitation; boot arguments and framebuffer addresses were not
  changed merely to suppress the warning.
- The `nvme0n1p4` unclean FAT-volume warning is present in all three saved
  working baselines too. It is not new evidence of a GPU regression and does
  not by itself establish filesystem damage. Assessment/repair remains an
  attended task with the filesystem unmounted; none was attempted offline.
- Raw DT decompilation reports ten unit-name warnings for the two disabled
  zero-address mailbox placeholders and six disabled reserved-memory
  placeholders. Their live addresses are supplied by the guarded loader.
  These warnings are recorded, not hidden or treated as hardware qualification.

Local comparison artifacts are `build/gpu-control-offline-dtb.diff`,
`build/gpu-control-offline-power-graph.json`,
`build/gpu-control-offline-touch-metadata.json` and
`build/t6050-j714s-gpu-offline-dtc.log`. No runtime code or trial artifact was
changed by this offline review; no SSH, serial connection, MMIO, reboot or
target Mesa installation was performed.

**2026-11-08/09 accelerated simpledrm checkpoint:**

- Both GPU boots exposed `/dev/dri/renderD128` through the `aurora` driver,
  retained `simpledrmdrmfb`, disabled Linux DCP, brought up CPUs `0-14`,
  mounted `/dev/nvme0n1p5` read-write and restored USB IPv6 SSH.
- The kernel admitted exact GPU firmware **27.3 / 26C5035r**, acknowledged
  primary and secondary initdata, and retired the opening firmware records.
- Native renderer: `Apple M5 Pro (G17S B1)`. Zink renderer:
  `zink Vulkan 1.4(Apple M5 Pro (G17S B1) (AURORA_BOREALIS))`.
  Both use Mesa `26.3.0-devel (git-043a4c5808)`.
- On each boot, native and Zink each passed all thirteen printed
  `gl-native-smoke` scene variants, including pixel readback and compute,
  and all fourteen `gl-index-coverage` cases, each covering 4096/4096 pixels.
  All four commands exited zero; no new kernel messages appeared during
  either boot's test set. This is not a Vulkan conformance run.
- Both boots reached `Touch interface ready` and `Touch MT ready`; the
  earlier control's AFE failure did not recur. No physical gesture test
  was possible, and no MTP driver or SMC-reset change was made.
- Captured hwmon exposes battery, NAND, charge-regulator, Wi-Fi/BT and NVMe
  temperatures, **not a GPU temperature**. Do not infer GPU thermal safety
  from those sensors. No prolonged workload or thermal qualification ran.

The first GPU boot exposed a watchdog-retention bug: C's nested boot-argument
union inserted four bytes before the command line, so it saw `.wdt=keep`
instead of `m1n1.wdt=keep`. Python's flat serializer was correct.
`patches/m1n1/0009-xnuboot-preserve-flat-commandline-layout.patch` packs the
nested records and explicitly preserves their tail padding, keeping flags
and actual-memory-size fields at their original offsets. The actual-C
regression failed before and passed after the fix across all three revisions.
After a normal Linux reboot returned to the installed m1n1 proxy, the
corrected loader printed `Primary WDT left armed (m1n1.wdt=keep)`. A read-only
register check found control `0x4`, the 120-second alarm, and an advancing
counter before rearming for Linux. All four GPU checks then passed again.
This verifies retention, not an intentionally induced watchdog reset.

The proven pre-fix bundle remains at
`build/tether-aurora-gpu-simpledrm-7.3.0-g929e67a1da3e-before-bootargs-fix.tar.gz`
(SHA256 `cdc179c322b33275bbeb63f72b938a6a33f886efc3cf8c12158c42859e943147`).
It needs the post-chainload watchdog arm and must not be described as
preserving the pre-chainload timer. The corrected hardware-tested loader is
SHA256 `4931741f9e0ff149c51894695caedc30ec514e587ace72fd50018b0e348ea202`;
the complete private Mesa archive is
SHA256 `3fafb0e973c9ed44147c604e5ca6bc68c85fa48a7c6f4faae569dcd399d58f1b`.
Kernel/DT, bundle and preserved fallback hashes, commands, UTC timestamps
and log paths are recorded in `build/gpu-simpledrm-trial-20261108.json`.
The installed boot object and original recovery artifacts were not changed.

**Remaining qualification:** the Zink desktop checkpoint below adds visible
output and normal-client rendering, but owner confirmation of its physical
input responsiveness is still pending. Keep GPU+DCP, suspend/resume and longer
thermal/power behavior as separate experiments.
If touch AFE errors recur, capture the complete startup log and compare
against the fallback rather than extending timeouts or guessing SMC resets.

The exercised headless GPU handoff sequence is:

```sh
cd build/tether-aurora-gpu-simpledrm
export M1N1DEVICE=/dev/m1n1
export BOOTARGS="earlycon=efifb keep_bootcon console=tty0 loglevel=8 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0 arm64.nowfxt kvm-arm.wfi_trap_policy=trap m5.root=/dev/nvme0n1p5 systemd.unit=multi-user.target"
python3 hv/wdt-arm.py 120
./proxyclient/tools/chainload.py -r boot/m1n1-chain.bin m1n1.wdt=keep
python3 hv/nvme-proxy-probe.py
python3 hv/wdt-arm.py 120
./boot-linux.sh
```

Use the direct chainloader for the retention argument: `chainload.sh` accepts
an image path but does not forward extra boot arguments. Require the
`Primary WDT left armed` message when testing pre-chainload protection;
the preserved older fallback loaders do not contain the ABI correction.
For a GPU-disabled control, use the known-good loader with the matching
control DT; do not infer simpledrm isolation from an old loader ignoring the
new DCP opt-out marker.

These boots load RAM, not the installed boot object, but Linux mounts the
existing SSD root read-write. The watchdog protects early handoff; once
Linux's watchdog driver takes over it is fed, so not every later hang will
reset automatically. Keep physical power-cycle access and both original
bundles available. Serial loss at handoff is expected; discover the new USB
network interface before reconnecting, rather than reloading Linux.

After explicitly installing only the private Mesa archive, identify the
actual GPU render node and run numerical pixel/compute checks:

```sh
P=/opt/mesa-j714s-gpu-043a4c58080c
"$P/bin/mesa-j714s-gpu" native "$P/bin/gl-native-smoke" /dev/dri/renderDNNN
"$P/bin/mesa-j714s-gpu" zink "$P/bin/gl-native-smoke" /dev/dri/renderDNNN
"$P/bin/mesa-j714s-gpu" native "$P/bin/gl-index-coverage"
"$P/bin/mesa-j714s-gpu" zink "$P/bin/gl-index-coverage"
```

Replace `renderDNNN` with the discovered GPU node, not an assumed number.
Zink exercises Vulkan-backed rendering/compute, not Vulkan conformance.
Inspect kernel logs for rejected submissions, firmware mismatch, UAT/DART
faults, timeouts and resets; a renderer string alone is not a pass.
Only after these checks, install the private Aquamarine fix and use the Zink
desktop launcher below, ending any previous session normally first. Outside
that launcher the software desktop remains available with
`env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe start-hyprland`.
No DCP sleep, N1, audio or PMC/PMP activation is qualified by this trial.

#### Accelerated Hyprland: Zink on simpledrm

The 2026-11-09 desktop check used the same GPU kernel/firmware and the existing
patched Hyprland 0.57.1. The display remained `eDP-1`, 3024x1890 at 60 Hz,
with Linux DCP off. Native Gallium reached the wallpaper but the user reported
very slow interaction and incorrect rendering; the captured Kitty window had
black contents. A Zink-only Kitty client rendered text/colours correctly inside
that same native compositor. Moving the whole compositor to Zink then gave a
correct normal Kitty client and a short active-text sample near the panel's
60 Hz rate. These are functional/timing samples, not comparable benchmark runs
or a long desktop soak.

The running compositor mapped the private Mesa EGL, GBM, Gallium and
`libvulkan_asahi.so`, with `GALLIUM_DRIVER=zink` and the private Asahi ICD.
No software driver or shim was selected, and the kernel log was unchanged
across the Zink desktop check. A captured debug overlay was enabled only
temporarily and restored to its previous value. The native session, user's
Lua config and system graphics packages were preserved. The owner was
unavailable to confirm the final Zink session's physical input/latency.

The installed launcher was then exercised on a spare VT through the standard
`start-hyprland --path /usr/local/bin/Hyprland` session supervisor. A child
started by that compositor, without per-client driver overrides, passed all
13 rendering/compute scenes and all 14 indexed-draw cases (4096/4096 pixels
each). A separate normal Kitty child rendered its live text and colour check.
The temporary session was stopped, both earlier sessions remained intact,
and the active VT was restored. No new kernel messages appeared.

**Allocator failure:** Aquamarine found the GPU render node, but still reopened
the display-only KMS descriptor when creating its GBM allocators. On this
machine private GBM failed on `/dev/dri/card0` and succeeded on the Aurora
render node. The
[`Aquamarine patch`](../patches/aquamarine/0001-allocate-on-render-node.patch)
prefers the already-resolved render descriptor for those allocators, while
keeping KMS ownership, polling and leases on the display descriptor. It targets
Aquamarine v0.16.0, `b77d67648336223a6c8fb88844ae316e7b72b574`.
The patch also applied to a clean checkout of that pin and rebuilt successfully
with the tracked cross-toolchain; the original hardware-tested binary was not
overwritten by that second build.

Build against the same saved target SDK as Hyprland above, including the
target's `/usr/share/hwdata/pnp.ids` and matching GCC 16.1.1 C++ headers.
The tracked toolchain defaults to `build/hyprland-dcp-sysroot`; override
`M5_DESKTOP_SYSROOT` and `M5_DESKTOP_CXX_VERSION` only to match another target.
Start with a new source directory; never reset an existing modified tree:

```sh
git init build/aquamarine-gpu-source
git -C build/aquamarine-gpu-source remote add origin https://github.com/hyprwm/aquamarine.git
git -C build/aquamarine-gpu-source fetch --depth=1 origin b77d67648336223a6c8fb88844ae316e7b72b574
git -C build/aquamarine-gpu-source checkout --detach FETCH_HEAD
git -C build/aquamarine-gpu-source apply "$PWD/patches/aquamarine/0001-allocate-on-render-node.patch"
cmake -S build/aquamarine-gpu-source -B build/aquamarine-gpu-repro-out -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$PWD/scripts/aarch64-desktop-toolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
  -DCMAKE_INSTALL_PREFIX=/opt/aquamarine-j714s-gpu-b77d67648336 \
  -DCMAKE_INSTALL_LIBDIR=lib
cmake --build build/aquamarine-gpu-repro-out --target aquamarine --parallel
DESTDIR="$PWD/build/aquamarine-gpu-stage" cmake --install build/aquamarine-gpu-repro-out
```

This stages a private `/opt` tree; it does not install onto the target.
Include Aquamarine's `LICENSE` with any binary distribution. Transfer and
checksum the staged tree before installing it on the Mac. Never overwrite
libraries mapped by a running compositor: stop that session normally first,
or use a distinct prefix and matching launcher. Rebuild when target library
ABIs change; do not replace system Aquamarine or Mesa to force compatibility.

Once the private Mesa/Aquamarine trees and patched `/usr/local/bin/Hyprland`
are installed, install and run the explicit launcher on the Mac:

```sh
sudo install -Dm755 scripts/start-hyprland-gpu.sh /usr/local/bin/start-hyprland-gpu
# From a logged-in console, after ending any previous compositor normally:
start-hyprland-gpu
```

The launcher selects Zink/Borealis and applies the combined library path
**after** `mesa-j714s-gpu`, because the Mesa wrapper deliberately resets
`LD_LIBRARY_PATH`. Setting Aquamarine's path before that wrapper silently
selects the old system backend instead. It uses the standard `start-hyprland`
supervisor with an explicit path to the patched compositor and forwards
Hyprland arguments after `--`. No login manager, autologin, global driver
selection or boot policy is changed by this launcher.

The everyday commands need the same care. Plain `start-hyprland` or `hyprland`
on a GPU kernel uses the distro's Mesa, which has no driver for the `aurora`
render node: Aquamarine picks that node, EGL reports `DRI2: failed to create
screen` and `failed to load driver`, and Hyprland aborts in
`CHyprOpenGLImpl::initEGL` a few seconds after it starts. Six core dumps on
2026-11-09 had exactly that backtrace, all from the plain commands.
`scripts/start-hyprland.sh` is the default launcher for both names: with an
`aurora` DRM device it runs `start-hyprland-gpu`, otherwise the distro's
`/usr/bin/start-hyprland`.

```sh
sudo install -Dm755 scripts/start-hyprland.sh /usr/local/bin/start-hyprland
sudo ln -sfn start-hyprland /usr/local/bin/hyprland
```

On the N1 kernel (`7.3.0-gc1fabe3c06f9`) the private stack's Zink and native
smoke runs both pass with no kernel messages, and the distro stack fails on the
same node as described. The default launcher is installed on the Mac; a
session started through it has not been watched yet.

Native Gallium remains an experimental headless-test option, not the desktop
default. Its passing GLES scenes did not cover the failing client workload.
Published [native-client shader findings](https://github.com/rolotrealanis98/m5pro-linux/blob/c9dbba61122f2472f9c38d9d9f31144e5e77a2be/contrib/pending/gpu/gl-native/APP-REGRESSIONS.md)
describe separate offline fixes; those fixes are not deployed or claimed
hardware-validated here. This desktop check does not qualify GPU+DCP, suspend,
general application compatibility, sustained thermal behavior or Omarchy's
full system installation.

### N1 Wi-Fi and Bluetooth (isolated J714s)

The N1 (Wi-Fi and Bluetooth, on internal PCIe port 0) runs on this J714s in a
separate profile on top of the GPU/simpledrm one. On tethered boots of
`7.3.0-gc1fabe3c06f9` (2026-11-09) Linux powered and trained the N1's link
itself, loaded its firmware and registered `wlan0` and `hci0`. Wi-Fi joined a
WPA2/WPA3 network on both bands and carried real traffic, and came back by
itself after a reboot; Bluetooth answered classic and LE discovery. The same
kernel, tree and loader were then proven from RAM as a self-contained
[native image](#native-n1-image-proven-from-ram-boot-loops-when-enrolled),
which **boot-looped when it was enrolled**. This
is short functional coverage; the [limits](#n1-limits) are listed below. The
default, DCP and GPU bundles, their loaders and the installed boot object are
unchanged.

Sources:

- The GPU trial's kernel base and series, then `patches/linux-aurora-n1/`.
  0001 is TripleU613's merge of the installer kernel's N1 work onto this
  tree's layout (Centauri drivers and the kernel-owned PCIe train by
  rolotrealanis98; see [`installer-stones.md`](installer-stones.md)).
  0002–0006 are what that merge needed to run here (table below).
- This repo's GPU loader plus `patches/m1n1-gpu/0004`, built in
  `build/m1n1-gpu-n1`. Its N1 hand-off only edits the device tree: it copies
  the control function's identity and the six host and five port tunable lists
  from that boot's ADT, then enables the root port and its DART together. It
  does no PCIe MMIO and never trains a link. Anything missing or malformed
  leaves port and DART disabled, and Linux boots without the N1. The
  watchdog-retention fix, GPU hand-off and DCP opt-out are the GPU loader's.
- The firmware is Apple's, taken from the public restore image of the same
  macOS build as the stub (27.3, `26C5035r`) with the board's static manifest.
  `scripts/mk-n1-ftab.py` assembles it (method published by rolotrealanis98)
  and checks every image against `BuildManifest.plist`. Nothing is requested
  from Apple and no per-unit ticket is involved. The file stays private and
  is never committed.

What the merged tree needed before the N1 came up here. Each row cost one
boot; all three failures were clean (no hang, the N1 simply stayed absent):

| Symptom | Cause | Fix |
| --- | --- | --- |
| `pcie-apple` defers forever: `Port … probe fail` | PERST# is pin 80 of the AP pin controller, whose driver was only modular and never loaded | `CONFIG_PINCTRL_APPLE_GPIO=y`; 0004 reserves every AP pin but 80 (pin 112's register takes an SError when read) and leaves the unused NUB/AOP banks disabled |
| `invalid or missing MSI slice` | The T6050 MSI window check demanded the four-cell AIC specifier of the multi-die layout; this tree's AIC has three cells | 0005 accepts both forms of die 0's IRQ 1888 |
| `shared PHY: 0xf3c030d1, waiting for 0x4/0x4`, port setup `-110` | iBoot leaves the GP power closure targeted on but auto-gated, so the shared PHY never acknowledges its clock request | 0006: `APCIE_SYS_GP`, `APCIE_PHY_SW` and `APHY_GP_AUS5` always on with auto-PM off, `APCIE_GP` and `APHY_GP_AUS5_A` kept on, in the N1-enabled trees only (m1n1's `pcie_t6050` stage A; the installer kernel's board file) |
| (found by review) SMC battery, lid and RTC gone, cpufreq and NVMe on unverified bindings | The merge made the installer's FT21 SMC write gate and its NVMe/cpufreq compatibles the default | 0003 makes the gate opt-in (`macsmc.m5_smc_gate=1`) and restores this unit's verified compatibles |
| (found by review) loader would never enable the port | `apple,manual-availability` missing on the port's DART | 0002 |

**Build:**

```sh
RUSTC="$(rustup which --toolchain stable rustc)" make kernel-aurora-gpu-n1-simpledrm
make m1n1-gpu-n1
KERNEL_FLAVOR=aurora-gpu-n1-simpledrm scripts/mktether.sh
tar -xzf build/tether-aurora-gpu-n1-simpledrm-bundle.tar.gz -C build
```

The kernel tree is `build/linux-aurora-n1` (prepare its bindgen as for the GPU
trial). Only the two N1 modules are built, `apple_centauri.ko` and
`btcentauri.ko`; everything else Wi-Fi and Bluetooth userspace needs is built
in (`configs/aurora-j714s-n1.config`). `kernel-aurora-gpu-n1` is the same
kernel with the DCP tree; it has not been booted.

Host checks, without the Mac: the loader's actual C hand-off against the
compiled trees and a saved runtime ADT (27 cases: identity and all lists
copied, a disabled host left byte-identical, every missing precondition or
bad ADT record fail-closed, the power closure and pin guard present), and the
GPU/DCP/watchdog cases again with the N1 trees (26).

```sh
D=build/linux-aurora-n1-out/arch/arm64/boot/dts/apple
A=build/adt-runtime-j714s-unattended-20261108T213635Z.bin
python3 patches/m1n1-gpu/smoke-n1.py --adt $A \
  --n1-dtb $D/t6050-j714s-gpu-n1-simpledrm.dtb --inert-dtb $D/t6050-j714s-gpu-simpledrm.dtb
python3 patches/m1n1-gpu/smoke-handoff.py --source build/m1n1-gpu-n1 --adt $A \
  --dtb $D/t6050-j714s-gpu-n1.dtb --simpledrm-dtb $D/t6050-j714s-gpu-n1-simpledrm.dtb \
  --default-dtb build/linux-aurora-out/arch/arm64/boot/dts/apple/t6050-j714s.dtb
```

**Firmware** (once per macOS build; the three inputs are members of the
restore image):

```sh
scripts/mk-n1-ftab.py --build-manifest BuildManifest.plist --device-class j714sap \
  --ftab ftab.bin --im4m centauri.j714sap.im4m --out build/n1-fw/j714s-ftab.bin
```

**On the Mac** (booted with any working bundle), with `REL` the release of the
kernel being installed for and the files from its build tree:

```sh
sudo install -Dm600 j714s-ftab.bin /usr/lib/firmware/apple/centauri/j714s-ftab.bin
M=/usr/lib/modules/$REL
sudo install -Dm644 apple_centauri.ko $M/kernel/drivers/net/wireless/apple/centauri/apple_centauri.ko
sudo install -Dm644 btcentauri.ko $M/kernel/drivers/bluetooth/btcentauri.ko
sudo install -m644 modules.builtin modules.builtin.modinfo $M/
printf 'kernel/%s\n' drivers/net/wireless/apple/centauri/apple_centauri.ko \
  drivers/bluetooth/btcentauri.ko | sudo tee $M/modules.order >/dev/null
sudo depmod $REL
sudo pacman -S --needed networkmanager wpa_supplicant bluez bluez-utils wireless-regdb iw
sudo systemctl enable NetworkManager bluetooth
```

With the modules under `/usr/lib/modules` udev loads them when the N1's PCI
functions appear; nothing has to run `insmod`. They must be the ones built
with the booted `Image`: the release string does not change with the config,
and there are no symbol versions, so reinstall them with every kernel.
NetworkManager has to stay off the tether, which systemd-networkd owns. It
is also told to scan with the factory address: a precaution on this new
driver, randomised scanning was not tried.

```ini
# /etc/NetworkManager/conf.d/10-omarchy-m5-wifi-only.conf
[keyfile]
unmanaged-devices=*,except:type:wifi
[device]
wifi.scan-rand-mac-address=no
```

The tether's default route must rank below Wi-Fi, or everything off-link
leaves through the cable and is dropped by a host that forwards nothing
(local addresses still work, which makes it look like a router problem).
`scripts/mkrootfs-image.py` now writes the gadget links with a `[Route]`
section at `Metric=2048`; an existing root needs the same edit in
`/etc/systemd/network/10-usb-gadget-*.network`.

**Boot** exactly as the GPU trial, from `build/tether-aurora-gpu-n1-simpledrm`:
watchdog armed, `chainload.py -r boot/m1n1-chain.bin m1n1.wdt=keep`, the NVMe
probe, watchdog again, `./boot-linux.sh`. The bundle also carries the tree
with the N1 off as `boot/control-t6050-j714s-gpu-simpledrm.dtb`: the same
loader and kernel then leave the N1 alone, which is the first thing to boot
after any change here. Expect from the loader and then the kernel:

```
n1: control function: apple/centauri/j714s-ftab.bin, platform-id 0x00086050
n1: port 0: root port and DART okay (Linux powers and trains the link)
pcie-apple 1cb0000000.pcie: port 0: trained by Linux, the boot loader left it down
pcie-apple 1cb0000000.pcie: adopted port 0, endpoint 01:00
pci 0000:01:00.0: [106b:1900] type 00 class 0xff0000 PCIe Endpoint
```

udev then loads `apple_centauri` about 2.5 s into the boot. That boots the N1
from its ROM, resets the root port (`link retrained after a root-port reset`),
and the Wi-Fi and Bluetooth functions `106b:1902` and `106b:1903` appear;
`btcentauri` follows for `hci0`. The first network is joined once with
`sudo nmtui`; NetworkManager reconnects it on later boots. The modules load
once per boot: others report that a second load in the same boot does not
recover the chip.

**Result on this J714s:**

| Check | Result |
| --- | --- |
| Control boot, N1 off | N1 untouched, 0 PCI devices; CPUs, SSD, GPU, battery, SMC, input as before |
| PCIe | trained by Linux 0.9 s into boot; root port `106b:100c`, endpoint `106b:1900` |
| Firmware | accepted; channel list 13 on 2.4 GHz, 25 on 5 GHz, none on 6 GHz |
| Scan | 13 networks on both bands, strongest −37 dBm |
| Association | WPA2/WPA3 network from `nmtui` with the ordinary passphrase, on 2.4 GHz and on 5 GHz; supplicant state SAE, PMF on, CCMP |
| Traffic | DHCP lease, `ping 1.1.1.1` 4/4 at about 11 ms, DNS, HTTPS, 25 MB download at roughly 42 MB/s |
| After a reboot | modules loaded by udev, the saved network rejoined and the Internet reachable with nothing typed |
| Bluetooth | `hci0` up (Apple, HCI version 0x11); classic inquiry answered by three devices; with LE built in, 48 distinct LE devices in a 10 s discovery and `bluetoothd` running |
| Userspace interfaces | `/dev/uhid` present; as root all 17 AF_ALG algorithms BlueZ and iwd use bind (Linux 7.3 refuses most of them to unprivileged callers by default, `crypto.af_alg_restrict=1`) |
| Module temperature | 31.4 °C with the N1 off (control boot), about 33 °C associated and idle |
| Kernel log | no Oops, WARN or SError; GPU firmware admitted as in the GPU trial |

The known `CONNECT = -95` rejection of a passphrase did not occur with
NetworkManager 1.58.1 and wpa_supplicant 2.12: SAE was offloaded to the
firmware at the first attempt. The driver still refuses (`-95`) anything it
cannot offload: open networks, TKIP, or a supplicant that hands over no
credential. If a passphrase is rejected, store the 64-hex PSK instead
(`wpa_passphrase <SSID>`, passphrase on stdin).

<a id="n1-limits"></a>**Not qualified:** Bluetooth pairing, HID and audio
with a real device (discovery is all that was exercised, and the driver
implements neither SCO nor ISO); iwd, which was not started because
NetworkManager's wpa_supplicant owns `wlan0`; roaming, long transfers, suspend
with the N1 up, and the N1 under GPU or CPU load (a peer saw it warm up with
busy P-cores). The first working boot's kernel had LE off; LE, HIDP, uhid and
the AF_ALG interfaces are built in since the second. The DCP variant has not
been booted. The other J714s's `-tripleu` trees received the same fixes but
were not booted here.

### Standalone (no second machine - one 1TR ceremony per image)

> **Do not enroll the images of this section as they were built then.** Two
> objects were enrolled on 2026-11-09 and both boot-looped: this section's
> self-contained N1 image (24.6 MB) and a 1.2 MB loader with a `chainload=`
> line appended. Both had data appended and neither size was a multiple of
> 16 KiB; see the
> [alignment evidence](#raw-image-alignment-evidence-and-current-workaround).
> Size alone does not explain both failures. The plain, aligned replacement
> has now booted natively on this Mac through the
> [two-stage chain](#native-boot-in-two-stages) below. The rest of this section
> is the record of how the self-contained images were built and qualified.
> `mkpayload.sh` now pads them, but no padded one has been enrolled.

The current candidate is a **device-specific GPU/simpledrm image**, not an
enrolled boot object. It contains the native `CHAINLOADING=0` loader, the
already-tested `7.3.0-g929e67a1da3e` kernel, GPU/simpledrm DT, initramfs and
SSD-root command line. It does not introduce U-Boot, GRUB or Limine, change
partitions, or depend on another computer supplying those payloads.

Build after preparing the GPU kernel and initramfs described above:

```sh
make payload-gpu-simpledrm \
  GPU_ADT=build/adt-runtime-j714s-unattended-20261108T213635Z.bin
```

This reconstructs `build/m1n1-gpu-standalone` without changing the tether
loader or vendor checkout, and writes `build/m1n1-gpu-simpledrm-payload.bin`.
`mkpayload.sh --dtb PATH` selects the exact board profile and re-walks the
assembled payload chain. There is no `maxcpus=1` or forced systemd target in
this candidate; the existing SSD's default target selects console/desktop.

The standalone build applies `patches/m1n1-gpu/0003-*`. Its seven-property
native guard is generated from a private ADT **only after** the existing
Python model, firmware and four voltage-table hash checks accept it. At boot,
the loader compares the raw model, both firmware properties and all four
tables byte-for-byte before NVMe initialization, secondary startup or Linux
DT preparation. A mismatch refuses Linux and returns to the proxy path.
This is not a generic J714s voltage profile or GPU firmware-image attestation.

The loader also performs the tested native NVMe init/shutdown sequence:
no GPT probe or disk writes, and shutdown leaves ANS cold for Linux.
`kboot_boot()` already calls `usb_init()` to power the USB PHY chains; there
is no extra USB workaround. The generated calibration header stays private
under `build/`; it is not a second hand-maintained calibration table.

**Qualification on this Mac (2026-11-08 local / November 9 UTC):**

- The actual C handoff/boot-argument checks still pass all 26 cases. Selecting
  `--source build/m1n1-gpu-standalone` in the smoke command above adds 22
  native-guard cases: exact acceptance and changed, missing and wrong-length
  rejection for each of seven properties. **48 cases pass.**
- The small native loader was chainloaded with the verified watchdog retained.
  Its actual compiled parser processed the candidate's identical payload tail
  staged in ordinary RAM, then its actual `payload_run()` passed the live
  calibration gate, initialized/shut down NVMe itself and booted Linux. No host
  NVMe probe, C replacement, altered entry point or CTRR bypass was used.
- Linux reached the existing ext4 SSD root read-write with CPUs `0-14`,
  simpledrm and the Aurora render node. Native GL and Vulkan-backed Zink each
  passed the 13 scene variants and 14 indexed-rendering cases, with no new
  kernel messages during those checks. Systemd settled to `running`, no jobs
  and no failed units. The obsolete `serial-getty@ttyGS0` was disabled:
  this image exposes EEM networking, not an ACM serial port; `tty1` remains
  enabled. That removes its pointless 90-second missing-device wait.
- Local evidence: `build/native-payload-ram-20261108.log`,
  `build/native-payload-gpu-20261108.json` and
  `build/native-payload-health-20261108.json`.

The full candidate is 24,012,585 bytes, SHA256
`53ae65c9a689806efb5b58a5e7e392ceeb58a69dfce7e47bd29ac9942ef84fab`.
Its kernel, DT and initramfs are byte-identical to the exercised tether bundle.
The existing Stage-1 CTRR reservation cannot contain this whole image.
**Do not disable that guard:** the RAM test does not prove iBoot enrollment,
the monolithic placement, cold USB initialization or an unplugged cold boot.
Those still require the owner's attended native trial.

#### Native N1 image: proven from RAM, boot-loops when enrolled

The N1 profile has the same kind of image:

```sh
make payload-gpu-n1-simpledrm \
  GPU_ADT=build/adt-runtime-j714s-unattended-20261108T213635Z.bin
```

This builds the native loader with both the calibration guard (0003) and the
N1 hand-off (0004) in `build/m1n1-gpu-n1-standalone`, and writes
`build/m1n1-gpu-n1-simpledrm-payload.bin`: that loader, the SSD-root command
line, the N1 kernel, `t6050-j714s-gpu-n1-simpledrm.dtb` and the initramfs. The
three payload members are byte-identical to the tether bundle that booted with
the modules loading by themselves. With `--source build/m1n1-gpu-n1-standalone`
the 48 hand-off and guard cases and the 27 N1 cases pass on the host.

It was qualified from RAM with a probe that went away with this approach
(`scripts/probes/native-payload-ram.py` in the history). With the candidate's
stage 1 chainloaded and **no** host NVMe probe, it compared what ran with the
candidate's stage 1, copied the payload tail to ordinary RAM, had the loader's
compiled `load_one_payload()` parse that copy and its `payload_run()` take
over, and left the proxy, where the loader's `main()` continues as it does
after a native `payload_run()`.

**Result (2026-11-09):** calibration guard PASS, the loader's own NVMe
init/shutdown, 14 secondaries started, `n1: port 0: root port and DART okay`,
then Linux on the SSD root with CPUs `0-14`, `running`, no failed units. With
nothing typed on the Mac: the N1 link trained 0.85 s into the boot, both
modules loaded, Wi-Fi rejoined the saved network on 5 GHz, ping and HTTPS
worked, `bluetoothd` ran with LE, the GPU firmware was admitted, and the
kernel logged no Oops, WARN or SError.

The candidate is 24,643,107 bytes, SHA256
`47f7a522326c077f01a84660a0a8bdbe8ce0fd768a529879bd4fbf6c436af4d8`.
The RAM run wrote nothing to the Mac's disk. A recovery bundle with this
candidate and a re-verified rollback image was then staged
(`omarchy-n1-20261109`, below) and the candidate enrolled from the stub's
paired 1TR on 2026-11-09. **It did not boot:** the Mac restarted a few times
and returned to the startup options (see the note at the top of this
section). A RAM run cannot show that: iBoot's handling of the object is
exactly what it leaves out.

#### Raw-image alignment: evidence and current workaround

The booting raw objects compared below have sizes that are exact multiples of
16 KiB. Both unaligned objects enrolled here boot-looped:

| Object | Bytes | mod 16384 | Under iBoot |
|---|---|---|---|
| Enrolled proxy loader, a plain `m1n1.bin` | 1,114,112 | 0 | boots (this Mac) |
| TripleU613's `gz16` image with a kernel inside | 7,061,504 | 0 | boots (his J714s, [journey](omarchy-m5-pro/JOURNEY.md)) |
| Self-contained N1 image: loader, command line, kernel, DT, initramfs | 24,643,107 | 1571 | loops (this Mac) |
| Stage 1 with `chainload=…` appended, the upstream way to configure one | 1,179,709 | 61 | loops (this Mac) |
| Plain stage 1 with its chainload target compiled in | 1,179,648 | 0 | boots natively (this Mac, owner enrollment followed by live SSH verification) |

Neither loop put anything of ours on the cable. In the second, recoveryOS was
back 37 s after the `reboot`, with neither loader nor Linux having enumerated
on USB. This does not identify the failing component: neither stage brings USB
up on the normal boot path. An iBoot rejection and a loader failure before USB
initialisation are both possible; chainloading does not test native placement.
TripleU613's older-firmware J714s notes report unpadded raw images of 192 KB,
18.9 MB and 49 MB panicking iBoot after the load, while images with a branch
at offset 0 and 16 KiB padding ran
([raw-image contract](omarchy-m5-pro/m5-omarchy/reports/21-raw-image-contract.md)).
Aurora's installer does not append to its stage 1 either: it fills a
configuration block in place so that the image "keeps its length and STACKBOT
tail".

The first diagnosis here was size, because a sibling J716s loops just above
4.8 MiB ([issue #1](https://github.com/betizzel/omarchy-m5/issues/1)). A
1.2 MB object looping and a reported 7 MB one booting mean size alone does not
explain the J714s failures. The plain, aligned replacement now boots natively
on this Mac, establishing a working fix for this chain. The exact constraint
has not been isolated: the successful image both restores alignment and removes
the appended configuration tail.

Consequences in this repo:

- Stage 1 is a plain `m1n1.bin` with its chainload target compiled in
  (`patches/m1n1-stage1/0001`). `make m1n1-stage1` fails if the result is not
  a 16 KiB multiple ending in `STACKBOT`.
- `enroll.sh` refuses a candidate whose size is not a multiple of 16384.
- `mkpayload.sh` zero-pads self-contained objects; m1n1's payload scan stops
  at the zeros. No padded object has been enrolled.

**Native success, 2026-11-09:** the owner enrolled the plain stage 1 and reported
a successful boot. A read-only check over USB SSH found stage 1
`cd30868-dirty`, stage 2 `7646495-dirty`, Linux `7.3.0-gc1fabe3c06f9`, all 15 CPUs
and the ext4 SSD root. The staged candidate still matched the hash below.
This is a native boot, not another host-chainloaded trial.

#### Native boot in two stages

The current candidate keeps the enrolled object plain (above), and a kernel
inside it would cost a Recovery ceremony per kernel. Instead, enrolled m1n1
reads a second loader from the EFI partition, and that loader reads the kernel
from a file:

| Stage | Where | What |
|---|---|---|
| 1 | enrolled boot object, `build/m1n1-stage1-esp.bin` | baseline m1n1 (`patches/m1n1`, `CHAINLOADING=1`) with its target `<EFI PARTUUID>;m1n1/boot.bin` compiled in (`patches/m1n1-stage1/0001`); nothing appended |
| 2 | EFI partition, `m1n1/boot.bin` | the GPU and N1 loader with its calibration guard, `payload=<EFI PARTUUID>;m1n1/payload.bin` appended (stage 1 reads this file, not iBoot) |
| payload | EFI partition, `m1n1/payload.bin` | command line, `Image.gz`, device tree and initramfs, as `mkpayload.sh` used to append them to the loader |

`patches/m1n1-gpu/0005` adds the `payload=` variable. With no kernel behind
its image, the loader checks the GPU calibration first, initialises NVMe once,
reads the file through m1n1's FAT reader and parses it with the same
`load_one_payload()` as an appended payload. Stage 2 is small enough to land at
stage 1's base, below the secondary-only CTRR range (`patches/m1n1/0004`
refuses anything that is not), so it needs neither the relocation nor the RVBAR
trampoline that larger second stages do.

```sh
make m1n1-stage1 esp-gpu-n1-simpledrm \
  GPU_ADT=build/adt-runtime-j714s-unattended-20261108T213635Z.bin
# build/m1n1-stage1-esp.bin, build/esp-gpu-n1/m1n1/boot.bin and payload.bin
```

`ESP_PARTUUID` defaults to this Mac's EFI partition. The two files go to
`m1n1/` on it (`/boot/m1n1/` from Linux), with a checksum read-back:

| File | Bytes | SHA-256 |
|---|---|---|
| `m1n1-stage1-esp.bin` | 1,179,648 | `ec29ead17a2e545312142b605c58ee0fd1cf593bf36e92d4cc9ff143a39debeb` |
| `m1n1/boot.bin` | 1,212,478 | `e7567a5fa08f767abe1ff12ba9c2a9f2c5764d1e7ca3986afcd784545b7f3a9b` |
| `m1n1/payload.bin` | 23,479,843 | `09f88f9bb541db04df8e0ea0a1c90a8bbf504ca28738afb53409e86f672af6d7` |

The payload's kernel, device tree and initramfs are those of the tether bundle.

**Run from the cable with nothing enrolled (2026-11-09).** Both files in place,
the Mac reset into its enrolled proxy loader, the watchdog armed and kept:

| Run | Result |
|---|---|
| Stage 2 alone from its proxy, `native-chain-probe.py --payload` | It read `payload.bin` itself and prepared the hand-off; Linux on the SSD root, 15 CPUs. The probe's first version gave up after the proxy client's 3 s reply timeout and lost the loader's output; the loader had finished |
| The whole chain: stage 1 chainloaded, no host NVMe probe, nothing else sent | Linux came up by itself: 15 CPUs, `running`, both N1 modules, Wi-Fi connected, no kernel complaints |
| `m1n1/boot.bin` renamed away | Stage 1: `Chainload failed: FATError(NotFound)`, then its USB proxy. The usual tether flow booted Linux from that proxy |
| `m1n1/payload.bin` renamed away | Stage 2, started by stage 1: `GPU profile PASS`, `FATError(NotFound)`, then its USB proxy. The tether flow booted Linux from there too |
| The whole chain again, with the plain stage 1 | Linux by itself as before; `/chosen/asahi,m1n1-stage1-version` in its device tree names this stage 1 |
| `m1n1/boot.bin` renamed away, plain stage 1 | `Built-in chainload target: …`, `FATError(NotFound)`, then its USB proxy; the tether flow booted Linux |

The first four runs used stage 1 with its variable appended (1,179,709 bytes).
That object was then enrolled and boot-looped. The last two are the plain image
in the table above, which the owner subsequently enrolled and booted successfully.

The whole chain is simply the object to enroll, chainloaded:

```sh
cd build/tether-aurora-gpu-n1-simpledrm           # Mac in the m1n1 proxy
python3 hv/wdt-arm.py 170
./proxyclient/tools/chainload.py -r ../m1n1-stage1-esp.bin m1n1.wdt=keep
```

`chainload.py` then times out waiting for a proxy: stage 1 goes straight on,
and the next thing on the cable is Linux. Neither stage brings USB up before it
is done, so a working chain prints nothing to the host. A stage that falls back
to its proxy replays what it printed. `scripts/probes/native-chain-probe.py`
(`hv/` in the bundle) runs one stage's own code from its proxy instead, after
comparing what runs with the given loader: `--payload SPEC` for stage 2 (run
above), `--chainload SPEC` for stage 1 (not run on the Mac yet), `--identify`
to tell which loader answers after a fallback.

**First enrolled boot:** iBoot started the plain stage 1, which read stage 2
and the kernel payload from storage without host assistance. USB SSH verified
the two loader versions, 15 CPUs and the SSD root. The boot-acknowledgement
service succeeded; the selected BUG/WARNING/SError/Call-trace patterns had no
matches in the kernel log. No Hyprland process was running during this check.

**Native radio limitation:** Linux trained the N1 link at 0.842 s, but
`apple_centauri` reported `IPC bootstrap failed: -16 (Control stage=0x1)`
and `N1 automatic startup failed in phase2: -16`. Both radio modules had
autoloaded; NetworkManager was active, but no Wi-Fi interface appeared and
Bluetooth was inactive. The earlier tethered Wi-Fi/Bluetooth success is not
yet reproduced through this native startup. No driver reload, reset or reboot
was attempted during this inspection.

An unplugged cold boot remains owner-attended and unconfirmed.

Living with it:

- A new kernel, device tree, initramfs or stage 2 is a file copy to `m1n1/`,
  with no Recovery step. The two N1 modules under `/usr/lib/modules` have to
  be the ones built with the kernel in `payload.bin`.
- `sudo mv /boot/m1n1/boot.bin /boot/m1n1/boot.off` turns the Mac back into
  one that waits for the cable.
- Neither loader checks the file it reads beyond its format. If `boot.bin` is
  ever damaged, delete it from macOS (`diskutil mount disk0s4`).
- `poweroff` is not expected to cut power, because `macsmc-reboot` is not
  loaded (not tried). Hold the power button once the system has stopped.

#### iBoot's boot counter

iBoot keeps a boot stage and counts boot errors and panics in the PMU's legacy
scratchpad (`info-leg_scrpad` 0xf800: the stage at +1, the two counts as the
nibbles of +2, the stage of the last error at +3).
`scripts/probes/pmu-boot-counters.py` reads them from the proxy without the
reset the other proxy tools perform. After each watchdog restart of a running
Linux it read `20 30 01 30`, one boot error at stage 0x30, four times out of
four.

With the cable that never adds up, because everything that imports
`m1n1.setup` zeroes the count as it connects. Without the cable nothing did:
`macsmc-reboot` is the driver that would, and it is not loaded here
(`CONFIG_POWER_RESET_MACSMC=m`, kept out so that restart stays with the
watchdog). J716s reports that iBoot ends in "needs to be reinstalled" after a
few such restarts
([issue #1](https://github.com/betizzel/omarchy-m5/issues/1)).

The root image therefore carries `omarchy-m5-boot-ok.service`
(`scripts/mkrootfs-image.py`), which zeroes that byte through the PMU's nvmem
device once the system is up. On the Mac a staged `01` was cleared and logged,
and the unit ran on the following boots. How many errors iBoot tolerates was
not measured.

#### Enroll only after current-volume and rollback checks

One bundle with an `enroll.sh` is on the existing EFI partition, visible from
Linux under `/boot`: `omarchy-stage1`, with the plain stage 1 of the chain
above and the rollback image. Earlier bundles with a helper were removed after
the wrong one was run in Recovery once (it stopped, as designed).
`omarchy-native-gpu-20261108` remains for its rollback image and tether
fallbacks; its self-contained candidate has been deleted. Copying a bundle
there does **not** enroll anything or change the startup disk. The partition's
stale dirty flag was cleared with `fsck.fat` first, and the files were read
back after a remount.

The rollback image was saved before the stub refresh, so it was checked again
against what is enrolled now (2026-11-09). With the Mac reset into its
enrolled loader, that loader's code, constants and relocation table in RAM
(447,088 bytes) equal the saved file once the loader's own relocations are
applied, and the volume group it booted from (`/chosen` `boot-uuid`) is the one
the bundle records. The mutable data section cannot be compared this way.
**Repeat both checks before replacing a boot object with any later bundle.**
After each of the two rollbacks of 2026-11-09 the same comparison found no
differing byte.

`scripts/enroll-native.sh`, staged as `enroll.sh` next to an `enroll.conf`
naming the stub, its volume group and the two images, does the Recovery side.
It refuses a candidate whose size is not a multiple of 16 KiB or exceeds its
conservative 4 MiB cap (not a measured J714s limit), checks size and SHA-256, finds
the stub's System volume by volume group and name (it or the EFI partition may
be the one mounted with a ` 1` suffix), requires `bputil` to report `Paired`
and `one true recoveryOS`, keeps a best-effort copy of the current custom
object, and only after a typed confirmation runs the `kmutil` command below.
`enroll.sh rollback` enrolls the saved Stage 1 the same way. It is plain POSIX
sh with the tools the installation's step 2 used. Its control flow is dry-run
on the host against stand-in tools (wrong confirmation, unpaired, another
volume group, an oversized image, an image with a line appended). Both paths
have run in recoveryOS (2026-11-09): three enrollments, with the third (the
plain, aligned loader) booting successfully, and two rollbacks that put the
saved proxy object back after the earlier failures.

After the boot object had failed to start, holding power and choosing Options
opened a recoveryOS that `bputil` did not report as paired with the stub. The
helper stops there and prints the remedy, which worked here:

```sh
bless --setBoot --mount "/Volumes/Omarchy"     # the path the helper prints as "target:"
shutdown -h now
```

Then wait 15 s, hold power until "Loading startup options" and choose
**Options**, not the stub's name: choosing the stub starts its boot object.

In the stub's recoveryOS (shut down, wait 15 s, hold power until "Loading
startup options", Options, then Utilities → Terminal):

```sh
sh /Volumes/*/omarchy-stage1/enroll.sh             # add "rollback" for the way back
diskutil mount disk0s4                             # first, if that path does not exist
```

What follows is the same procedure by hand.

From macOS/Recovery, identify the current Omarchy **System** volume and its
volume-group UUID afresh. Never reuse the pre-refresh UUID or guess a disk
number. Find the FAT partition by its GPT UUID
`79e793a2-ba60-4560-bf05-a8e268faddd9`; its `OMARCHY` label can collide with the
APFS `Omarchy` name, so use its actual mount path rather than assuming
`/Volumes/OMARCHY`. Set `BUNDLE` and `TARGET` to the verified absolute paths,
then check `shasum -a 256 -c "$BUNDLE/SHA256SUMS"` **from inside `$BUNDLE`**.

Use the target's paired 1TR and check `bputil -d -v "$VGID"` for `: Paired`
and `one true recoveryOS`. If pairing is wrong, stop and use the existing
Finish Installation recovery-routing instructions, not a security-policy
reset. This follows the upstream
[Stage-1 replacement procedure](https://asahilinux.org/docs/sw/m1n1-user-guide/#stage-1-as-fuos).
The owner must approve the exact target and candidate and enter any required
credentials interactively. Only then:

```sh
kmutil configure-boot -c "$BUNDLE/boot/m1n1-stage1-esp.bin" \
  --raw --entry-point 2048 --lowest-virtual-address 0 -v "$TARGET"
```

For this already-installed stub, do not recreate partitions, run the firmware
refresh again, rewrite `Finish Installation.app`, or lower security again.
If the candidate fails, return through the power-hold picker to the same
verified Recovery/target and, after approving rollback, enroll the verified
saved raw Stage 1 with the same raw/entry/virtual-address options:

```sh
kmutil configure-boot -c "$BUNDLE/rollback/m1n1-stage1-saved.bin" \
  --raw --entry-point 2048 --lowest-virtual-address 0 -v "$TARGET"
```

`finish-install.sh --undo` does not restore an enrolled boot object. A fresh
boot with the tether disconnected, working display/input and SSD root is the
acceptance check; keep the tether and Recovery fallback available until it
passes. With the two-stage chain, kernel, device-tree, initramfs and stage-2
changes are file copies to the EFI partition; only a change to stage 1 itself
needs another enrollment.

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

### Omarchy installation preflight (not installed)

The official aarch64 `omarchy` and `omarchy-settings` **4.5.0-3** archives
were downloaded and their detached signatures verified against the pinned
Omarchy channel key. This was an isolated host-side audit: neither package
was installed on the Mac, and no target keyring or repository was changed.
GPU Hyprland working does not mean the full Omarchy installation is complete.

The actual package scripts expose several blockers to an unattended stock
installation on this existing root:

- `/` is ext4, whereas `omarchy-apply-system` unconditionally runs the Snapper
  root setup and enables the Limine/Snapper integration. There is no ext4
  exemption in that setup path.
- The Mac's working USB/SSH connection uses enabled, active
  `systemd-networkd`; NetworkManager is not installed. The hardware setup
  disables networkd in favour of NetworkManager, so the tether must be
  deliberately migrated and verified before adopting it.
- Firewall setup enables UFW for the next boot with incoming traffic denied
  and no SSH allowance. It must not silently remove the recovery connection.
- `omarchy-settings` replaces system policy defaults, and platform lifecycle
  setup also dispatches boot integration. The current device-specific
  m1n1/GPU boot and rollback artifacts must not be replaced by stock boot roles.

The official [Mac installer checkpoint](https://github.com/omacom/omarchy-mac-installer/tree/c07e54c2134a8ec1415e7e2b917589ae1d3d7dc9)
does not include J714s/T6050 in its hardware catalog. Do not bypass that check
or install another model's boot image. Choose an explicitly adapted desktop
on the preserved ext4/custom-boot installation, with its feature limitations
stated, or a backed-up migration to the stock disk/boot model before proceeding.
That decision and the owner-attended native boot enrollment above are still
pending; no repartitioning, stock system-apply or boot-role installation was run.

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
