# aurora-sep (upstream, read-only by default)

aurora-silicon's Secure Enclave and Touch ID userspace, `tools/aurora-sep` of
[aurora-silicon/linux](https://github.com/aurora-silicon/linux) at
`8679514f4dff` (identical to the image kernel's `2b4523cb` for these files, the
UAPI header and `sep.rs`), packaged for the experimental J714s upstream image.
GPL-2.0-only. With [`../libfprint-aurora`](../libfprint-aurora) it lets an
owner opt in to Touch ID. The image itself never writes Secure Enclave or xART
state.

Citations are `file:line` at `8679514f4dff`. Paths under `tools/aurora-sep/`
are given without that prefix, and `XART-SAFETY.md` is shipped as
`/usr/share/doc/aurora-sep/XART-SAFETY.md`.

## What the image does by default

- **Nothing loads the driver.** `apple_sep` has no module alias, so udev never
  loads it (`drivers/soc/apple/sep.rs:3368-3371`). `aurora-sep.service`,
  `aurora-sep.timer`, `aurora-sep-ready.service` and
  `aurora-touchid-setup.service` are shipped, but none is enabled. There is no
  preset; the image builder only applies `80-omarchy-mac*`/`80-omarchy-apple`
  presets. omarchy-mac's own Touch ID flow reports `unsupported:board` on the
  T6050 (omarchy-mac `lib/touchid-eligibility:53-56` at `ea0097a5`), so it
  never loads the driver either.
- **Any load is read-only.** The driver defaults to `xart_writes=1` and
  `provision_keybag=1` (`drivers/soc/apple/sep.rs:3538-3549`). Loaded with those
  defaults, it creates Linux's identity keybag at first boot by writing the
  xART store that macOS shares (`README.md:56-66`, `XART-SAFETY.md:5-11`).
  `/usr/lib/modprobe.d/aurora-sep-xart.conf` sets
  `options apple_sep xart_writes=0 provision_keybag=0`. This is the mode that was
  RAM-tested on 27.3: attach, 12 endpoints, key store open, the sensor binds
  when `/dev/sep-bio` is opened, and Touch ID stops at "no persisted identity
  keybag". With writes off the driver refuses Touch ID enrol and verify
  (`drivers/soc/apple/Kconfig:227-229`).
- **The loader no longer forces writes.** Upstream's `load-driver:54` runs
  `modprobe apple_sep xart_writes=1 provision_keybag=1`. modprobe adds
  command-line options after modprobe.d's, so those would win.
  `aurora-sep-load-read-only.patch` makes it a bare `modprobe apple_sep`. The
  driver fixes `diag/xart` (`enabled` or `disabled`) at probe, before the
  attach (`drivers/soc/apple/sep.rs:1053`, `:3420-3436`;
  `Documentation/ABI/testing/sysfs-driver-apple-sep:95-109`). When it is not
  `enabled`, the loader also stops before the trusted-key probe
  (`load-driver:99-125`) and the keybag check (`load-driver:141-144`):
  - modprobe.d says `xart_writes=0`: exit 0 with a "read-only" line.
  - modprobe.d asks for writes but xART is `disabled`: exit 1.
  - A kernel without the attribute and writes asked for: upstream's flow.

  `check()` runs `test-read-only-loader.sh` over these cases. The branch is
  this package's own code and has not run on a Mac.
- **fprintd does not pull the loader in.** Upstream's fprintd drop-in has
  `Requires=aurora-sep.service` (`fprintd-aurora.conf:2-3`): "Installing
  aurora-sep lets fprintd load the driver with xART writes on"
  (`README.md:225-226`). This package's drop-in (`fprintd-aurora-sep.conf`)
  only orders fprintd after the loader. It drops upstream's `sensor-present`
  ExecCondition too, which would keep fprintd from starting without the
  driver.

These are left out on purpose:
- the GNOME greeter units and `powerdevilrc` (Omarchy has neither GDM nor
  KDE);
- `fprintd-no-timeout.conf.in`;
- `install-aurora-sep.sh`;
- `aurora-touchid/` (another loader that runs a bare modprobe, plus a bash
  script also named `aurora-touchid-setup`).

`logind-aurora-sep.conf` (a short press on the Touch ID/power button suspends
instead of powering off, `logind-aurora-sep.conf:1-11`) changes the power key
for everyone. It is installed only as an example, in `/usr/share/aurora-sep/`.

## Owner procedure: opting in to Touch ID

Nothing below has been tried on macOS 27.3 or on any J714s. On 27.3 only the
read-only attach was observed. The writes are permanent: the enclave's
anti-replay state only moves forward, and an old copy of the store written
back is "evidence and a last resort, not an undo" (`XART-SAFETY.md:245-247`).

### 1. Read `XART-SAFETY.md` first

    less /usr/share/doc/aurora-sep/XART-SAFETY.md

What it says for this Mac:
- **The guard is on.** The T6050 profile is T6040's with another sensor bus
  (`drivers/soc/apple/profile.rs:464-477`). T6040 sets `xart_guard: 1`
  (`profile.rs:443-453`; test at `profile.rs:771`). So Linux may rewrite only
  the xART session records it created itself (`XART-SAFETY.md:13-23`). The
  platform table at `XART-SAFETY.md:25-32` does not list T6040 or T6050.
- **Creating the keybag rewrites a record macOS also has.** On a first opt-in,
  the enclave rewrites one pre-existing kind-4 session record, which the
  driver lets through once, in the keybag creation window. It saves the
  previous value first, in `/var/lib/aurora-sep-xart-policy-previous.bin`
  (`XART-SAFETY.md:249-273`). Warm-attach M2 Pro did this; the T6040/T6050 row
  is not in the table (`XART-SAFETY.md:81-90`).
- **Matching may stay "UNVERIFIED".** Restoring fingerprints at boot only reads
  xART (`XART-SAFETY.md:49-55`). A match writes it (`XART-SAFETY.md:57-73`).
  Under the guard, `aurora-sep-ready` reports "matching UNVERIFIED" until the
  guard refuses something (`XART-SAFETY.md:290-304`). A refusal fails closed
  (`XART-SAFETY.md:92-117`).
- **Boot policy changes.** A new Stage 1, another boot object or a boot mode
  change makes the enclave rewrite one record on the first unlock
  (`XART-SAFETY.md:120-247`). Re-running this image's installer changes
  Stage 1.
- **Writes have conditions.** They are accepted only for a single,
  unsnapshotted, uncloned `.gl` extent; anything else fails closed
  (`README.md:56-62`, `XART-SAFETY.md:399-413`).

omarchy-mac's own consent text describes the worst case. A bad write can
leave macOS with FileVault unable to unlock its disk, which needs a DFU restore
that erases the Mac. Without FileVault, macOS resets its keychain and Touch ID
(omarchy-mac `entrypoints/enable-fingerprint:82-94` at `ea0097a5`).

### 2. Check read-only, then reboot

Nothing below writes enclave or xART state.

    sudo modprobe apple_sep        # options from /usr/lib/modprobe.d/aurora-sep-xart.conf
    sudo aurora-sep status         # reads only, never opens /dev/sep-bio (README.md:201-219)
    sudo python3 /usr/lib/aurora-sep/apfs-xart-inspect.py /dev/disk/by-partlabel/iBootSystemContainer
    sudo aurora-touchid-setup --check   # report only, write nothing (aurora-touchid-setup:5, 1105)

Expect `aurora-sep status` to show `xart disabled` and keybag `unknown` or
`missing`. `apfs-xart-inspect.py` must resolve one `.gl` extent; it reads
metadata only (`apfs-xart-inspect.py:1-8`, `README.md:73-80`). `--check`
should name `apple/mesacal-j714s.bin` and `apple/msrk-j714s.bin`, the sensor
node's `firmware-name` (`arch/arm64/boot/dts/apple/t6050-j714s.dts:522`), and say
it can build them.

The driver attaches once per boot and keeps the options it was loaded with,
so reboot before going on (`README.md:276-277`).

### 3. Back up

- Back up everything on macOS that you still need (step 1).
- Image the iBoot System Container read-only, as upstream did before its
  first writes (`XART-SAFETY.md:415-432`). Then copy the image off the Mac.
  This is evidence, not an undo (`XART-SAFETY.md:245-247`).

      sudo install -d -m 0700 /var/lib/aurora-rollback
      sudo sh -c 'zstd -19 -T0 </dev/disk/by-partlabel/iBootSystemContainer >/var/lib/aurora-rollback/iboot-system-container-$(date +%F).img.zst'
      sudo sha256sum /dev/disk/by-partlabel/iBootSystemContainer
      sudo sh -c 'zstd -dc /var/lib/aurora-rollback/iboot-system-container-*.img.zst | sha256sum'   # must match

### 4. Opt in

A file of the same name in `/etc/modprobe.d` replaces the image's read-only
default:

    printf '%s\n' '# Owner opt-in: let apple_sep write xART and create the Linux identity keybag.' \
      'options apple_sep xart_writes=1 provision_keybag=1' |
      sudo tee /etc/modprobe.d/aurora-sep-xart.conf
    modprobe -c | grep -E '^options apple[_-]sep '   # the last xart_writes= must be 1

Build this Mac's Touch ID calibration and sensor root key from its own factory
data:

    sudo aurora-touchid-setup

It reads the iBoot System Container and writes only
`/usr/lib/firmware/apple/*.bin` (mode 0600) and `/var/lib/aurora-sep/`, with
rollback copies (`aurora-touchid-setup:1-46`). The boot unit runs it anyway
when files are missing (`aurora-sep.service:18`,
`aurora-touchid-setup.service:11-15`).

Enable the loader and reboot:

    sudo systemctl enable aurora-sep.service
    sudo reboot

### 5. Check the first boot with writes

    journalctl -b -u aurora-sep.service -u aurora-sep-ready.service -u aurora-touchid-setup.service
    journalctl -k -b -g 'apple_sep|xART guard|keybag'
    sudo aurora-sep status

What to look for:
- `aurora-sep-load: trusted keys work after N s` (`load-driver:126`);
- keybag `present`;
- possibly "allowed one rewrite of kind-4 record ... while Linux's identity
  keybag was created" (`XART-SAFETY.md:269-271`);
- `aurora-sep-ready`'s verdict (`aurora-sep-ready:78-108`, `:153-164`).

The loader exits 1 when the driver refused writes; read its line.

### 6. Enrol and verify

    sudo fprintd-enroll -f right-index-finger "$USER"   # aurora-touchid-setup:983
    sudo fprintd-verify "$USER"
    sudo reboot
    sudo fprintd-verify "$USER"   # after the reboot, without re-enrolling

Matching right after enrolment and matching after a reboot are different paths
(`install-aurora-sep.sh:6533-6539`). If a verify fails with "xART guard:
refused", follow `XART-SAFETY.md:92-117`. Do not set `xart_guard=0` without
reading it.

**Do not use Omarchy's Setup > Security > Fingerprint.** It runs
`pacman -S --ask 4 libfprint-git` (omarchy `bin/omarchy-setup-security-fingerprint:153-155`
at `a948d8a6`), and that libfprint-git accepts only sep-bio interface 4
(omacom/omarchy-pkgs `pkgbuilds/libfprint-git/PKGBUILD`). This kernel speaks
interface 5 (`include/uapi/linux/apple-sep.h:17`). `aurora-sep` depends on
`libfprint-aurora`, so that transaction fails instead of replacing it.

Using a finger for sudo or the lock screen needs `pam_fprintd` added by hand.
On Omarchy, run `omarchy-apply-lock` after enrolment (`README.md:196-199`).

### Before changing Stage 1

Before re-running the installer or changing Stage 1 any other way, arm the one
allowed rewrite:

    sudo aurora-sep-policy-change --expect

It backs up the gigalocker extent, the host files and `/var/lib/fprint` first
(`XART-SAFETY.md:178-222`).

## Going back to read-only

    sudo fprintd-delete "$USER"      # while writes are still on
    sudo systemctl disable aurora-sep.service
    sudo rm /etc/modprobe.d/aurora-sep-xart.conf
    sudo reboot

After the reboot nothing loads the driver. A manual `sudo modprobe apple_sep`
attaches read-only again, and `aurora-sep status` shows `xart disabled`.

The Linux identity keybag stays in the enclave's records, and so do its
anti-replay state and the record rewritten when the keybag was created. The
Linux host files stay too; delete them only if you never want this keybag
back:
- `/var/lib/aurora-sep-keybag.bin`
- `/var/lib/aurora-sep-refkey.bin`
- `/var/lib/aurora-sep-host-state.bin` (`HOST-STATE.md:3-6`)
- `/var/lib/aurora-sep-xart-owned.bin` (`XART-SAFETY.md:314-340`)

Opting in again with the files gone creates a new keybag
(`XART-SAFETY.md:333-336`).

## Build

`arch=any`, nothing compiled. It depends on `libfprint-aurora` (aarch64, built
from [`../libfprint-aurora`](../libfprint-aurora)), and on `fprintd`,
`keyutils`, `kmod` and `python` from Arch Linux ARM.

    PKGEXT=.pkg.tar.zst makepkg
