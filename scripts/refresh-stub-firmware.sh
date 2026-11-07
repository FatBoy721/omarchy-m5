#!/bin/bash
# SPDX-License-Identifier: MIT
#
# refresh-stub-firmware.sh - bring the Omarchy stub's OS loader (stage-2
# iBoot/mBoot, m1n1's "OS FW version" = /chosen/firmware-version) up to the
# macOS that is now installed. Run ON THE MAC, booted into macOS.
#
# Why: iBoot boots m1n1 with the stage-2 mBoot from the stub's own Preboot
# restore bundle, which prep-stub.sh cloned from macOS at install time. A
# macOS update replaces LLB (/chosen/system-firmware-version) but not that
# bundle, so a firmware fix (macOS 27.3 beta 1 / 26C5035r: "only a single
# core is available ... custom raw boot object on M5 Pro/Max/Ultra") never
# reaches an old stub. An in-place refresh fails at bless with bootpolicy
# error 11 ("AP boot mode"): an existing Permissive LocalPolicy can only be
# rewritten from 1TR. So the stub volume group is recreated instead.
#
# Adapted from rolotrealanis98/m5pro-linux host/macos/refresh-stub-firmware.sh
# (MIT).
#
#   sudo scripts/refresh-stub-firmware.sh check
#       versions only; changes nothing
#   sudo scripts/refresh-stub-firmware.sh recreate --yes [--m1n1 FILE]
#       back up the stub's restore bundle(s), boot dir and boot.bin to
#       ~/omarchy-stub-backup-<VGID>, delete the stub's four volumes, rerun
#       prep-stub.sh (resume mode: no resize, no new partitions) and
#       finish-install.sh. The container, the EFI partition, the Linux root
#       and macOS are not touched. Then do the power-hold -> Omarchy -> step2
#       ceremony (docs/bringup.md).
#
# --m1n1 defaults to the boot.bin already on the stub (the enrolled stage-1).

set -euo pipefail
cd "$(dirname "$0")/.."

STUB_NAME="Omarchy"
MACOS_PART=disk0s2
FIX_BUILD="26C5035r"   # first build whose mBoot fixes T6050/T6051 SMP

die() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run with sudo"

vol_by_role() {   # vol_by_role <Role>: volume with that role in the stub's group
    diskutil apfs list -plist | python3 -c '
import plistlib, sys
name, role = sys.argv[1], sys.argv[2]
d = plistlib.loads(sys.stdin.buffer.read())
for c in d["Containers"]:
    vols = c.get("Volumes", [])
    if not any("System" in v.get("Roles", []) and v.get("Name") == name for v in vols):
        continue
    for v in vols:
        if role in v.get("Roles", []): print(v["DeviceIdentifier"])
' "$STUB_NAME" "$1"
}
mnt() {
    local m
    m=$(diskutil info "$1" | awk -F': *' '/Mount Point/{print $2}')
    if [ -z "$m" ] || [ "$m" = "Not mounted" ]; then
        diskutil mount "$1" >/dev/null
        m=$(diskutil info "$1" | awk -F': *' '/Mount Point/{print $2}')
    fi
    echo "$m"
}
build_of() { plutil -extract ProductBuildVersion raw -o - "$1" 2>/dev/null || echo "?"; }

SYS_VOL=$(vol_by_role System)
[ -n "$SYS_VOL" ] || die "no stub System volume named $STUB_NAME"
PB_VOL=$(vol_by_role Preboot)
VGID=$(diskutil info "$SYS_VOL" | awk -F': *' '/APFS Volume Group/{print $2}')
MACOS_SYS=$(diskutil info / | awk -F': *' '/Device Identifier/{print $2}')
MACOS_VGID=$(diskutil info "$MACOS_SYS" | awk -F': *' '/APFS Volume Group/{print $2}')
MAC_RESTORE=/System/Volumes/Preboot/$MACOS_VGID/restore
PB_MNT=$(mnt "$PB_VOL")
SYS_MNT=$(mnt "$SYS_VOL")
STUB_RESTORE=$PB_MNT/$VGID/restore
BOOTBIN="$SYS_MNT/Finish Installation.app/Contents/Resources/boot.bin"
MAC_BUILD=$(build_of "$MAC_RESTORE/BuildManifest.plist")
STUB_BUILD=$(build_of "$STUB_RESTORE/BuildManifest.plist")

echo "macOS:              $(sw_vers -productVersion) $(sw_vers -buildVersion)"
echo "macOS restore:      $MAC_RESTORE -> $MAC_BUILD"
echo "stub VGID:          $VGID ($SYS_VOL, Preboot $PB_VOL at $PB_MNT)"
echo "stub restore:       $STUB_RESTORE -> $STUB_BUILD"
system_profiler SPHardwareDataType 2>/dev/null \
    | grep -E 'System Firmware Version|OS Loader Version' | sed 's/^ */host /'
if [ -f "$BOOTBIN" ]; then
    echo "stub boot.bin:      $(stat -f %z "$BOOTBIN") bytes, sha256 $(shasum -a 256 "$BOOTBIN" | cut -d' ' -f1)"
else
    echo "stub boot.bin:      not present"
fi
echo "SMP fix needs the stub restore built from $FIX_BUILD or later."

case ${1:-check} in
check) exit 0 ;;
recreate) shift ;;
*) die "usage: $0 check | recreate --yes [--m1n1 FILE]" ;;
esac

M1N1=""; YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        --m1n1) M1N1=$2; shift 2 ;;
        --yes) YES=1; shift ;;
        *) die "unknown arg $1" ;;
    esac
done

[ "$MAC_BUILD" != "$STUB_BUILD" ] || die "stub restore already matches macOS ($MAC_BUILD); nothing to do"

STUB_CT=$(diskutil info "$SYS_VOL" | awk -F': *' '/Part of Whole/{print $2}')
STUB_PART=$(diskutil apfs list "$STUB_CT" -plist | python3 -c '
import plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
print(d["Containers"][0]["PhysicalStores"][0]["DeviceIdentifier"])')
STUB_BYTES=$(diskutil info -plist "$STUB_PART" | plutil -extract TotalSize raw -o - -)
STUB_TYPE=$(diskutil info "$STUB_PART" | awk -F': *' '/Partition Type/{print $2}')
REC_VOL=$(vol_by_role Recovery)
DATA_VOL=$(vol_by_role Data)
VOLS=$(diskutil apfs list "$STUB_CT" -plist | python3 -c '
import plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
print(" ".join(v["DeviceIdentifier"] + "=" + str(v.get("Name")).replace(" ", "_")
               for v in d["Containers"][0]["Volumes"]))')

echo
echo "stub container:     $STUB_CT on $STUB_PART ($STUB_BYTES bytes, $STUB_TYPE)"
echo "volumes to delete:  $VOLS"
[ "$STUB_PART" != "$MACOS_PART" ] || die "refusing: $STUB_PART is the macOS container"
[ "$STUB_TYPE" = Apple_APFS ] || die "refusing: $STUB_PART is not Apple_APFS (iSC/Recovery?)"
[ "$STUB_BYTES" -lt 8000000000 ] || die "refusing: $STUB_PART is larger than the 6 GB stub"
[ -n "$PB_VOL" ] && [ -n "$REC_VOL" ] && [ -n "$DATA_VOL" ] \
    || die "stub volume set incomplete (Data=$DATA_VOL Preboot=$PB_VOL Recovery=$REC_VOL)"

if [ -z "$M1N1" ]; then
    [ -f "$BOOTBIN" ] || die "no boot.bin on the stub; pass --m1n1 FILE"
    M1N1=$(mktemp /tmp/m1n1-stage1.XXXXXX)
    cp "$BOOTBIN" "$M1N1"
fi
[ -s "$M1N1" ] || die "stage-1 image $M1N1 is empty or missing"
echo "stage-1 to enroll:  $M1N1, sha256 $(shasum -a 256 "$M1N1" | cut -d' ' -f1)"

[ "$YES" = 1 ] || die "add --yes to back up and delete the volumes above and rebuild the stub"

HOME_DIR=$(eval echo "~${SUDO_USER:-root}")
BK="$HOME_DIR/omarchy-stub-backup-$VGID"
mkdir -p "$BK"
for r in "$PB_MNT/$VGID"/restore*; do
    echo "==> backing up $r -> $BK/$(basename "$r")-$(build_of "$r/BuildManifest.plist")"
    ditto "$r" "$BK/$(basename "$r")-$(build_of "$r/BuildManifest.plist")"
done
[ -d "$PB_MNT/$VGID/boot" ] && ditto "$PB_MNT/$VGID/boot" "$BK/boot"
cp "$M1N1" "$BK/boot.bin"
chown -R "${SUDO_USER:-root}" "$BK" 2>/dev/null || true

echo "==> deleting the stub volume group (error -69495 about a Preboot directory is harmless)"
diskutil apfs deleteVolumeGroup "$VGID" || true
for v in $(diskutil apfs list "$STUB_CT" -plist | python3 -c '
import plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
print(" ".join(v["DeviceIdentifier"] for v in d["Containers"][0]["Volumes"]))'); do
    echo "==> deleting leftover volume $v"
    diskutil apfs deleteVolume "$v" || die "could not delete $v"
done

echo "==> seeding a fresh Data volume (prep-stub finds the container by a $STUB_NAME* volume)"
diskutil apfs addVolume "$STUB_CT" apfs "$STUB_NAME - Data" -role D

echo "==> prep-stub.sh (resume: creates System/Preboot/Recovery, populates from this macOS)"
scripts/prep-stub.sh --yes

echo "==> finish-install.sh --m1n1 $M1N1"
scripts/finish-install.sh --m1n1 "$M1N1"

NEW_SYS=$(vol_by_role System)
NEW_PB=$(vol_by_role Preboot)
NEW_VGID=$(diskutil info "$NEW_SYS" | awk -F': *' '/APFS Volume Group/{print $2}')
echo
echo "new stub VGID:      $NEW_VGID"
echo "new stub restore:   $(build_of "$(mnt "$NEW_PB")/$NEW_VGID/restore/BuildManifest.plist")"
echo "backup:             $BK"
echo
echo "Next: shut down; hold power until 'Loading startup options'; pick Omarchy;"
echo "step2 runs bputil -nc + kmutil (admin password twice). Then from the host,"
echo "m1n1 should report an OS FW version of mBoot-20457.60.x or later."
