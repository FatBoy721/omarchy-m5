#!/bin/sh
# SPDX-License-Identifier: MIT
#
# enroll-native.sh - replace the Omarchy stub's custom boot object from its
# paired recoveryOS (1TR), or put the saved one back. It is staged on the EFI
# partition next to the images, as "enroll.sh":
#
#   <bundle>/enroll.sh        this script
#   <bundle>/enroll.conf      STUB_NAME, VGID, CANDIDATE, ROLLBACK and their sizes
#   <bundle>/SHA256SUMS       of the two images
#   <bundle>/boot/...         the loader to enroll: a small m1n1 that chainloads
#                             m1n1/boot.bin from this partition (make m1n1-stage1)
#   <bundle>/rollback/...     the boot object that was enrolled before
#
# In recoveryOS: Utilities -> Terminal, then
#
#   sh /Volumes/*/<bundle>/enroll.sh             # enroll the loader
#   sh /Volumes/*/<bundle>/enroll.sh rollback    # enroll the saved object again
#
# Nothing is changed until every check has passed and the confirmation word
# has been typed: the image has its recorded size and SHA-256, the stub's
# System volume is here and belongs to the recorded volume group, and bputil
# reports this recoveryOS as Paired with it and in 1TR. Then it runs the same
# kmutil command the installation used (scripts/finish-install.sh, step2).
# Partitions, the security policy and the startup disk are not touched, and
# macOS is not involved.
#
# Plain POSIX sh and only tools the installation already relied on in
# recoveryOS (diskutil, bputil, kmutil, awk, grep): there is no python there.
# ENROLL_VOLUMES points the volume search away from /Volumes for dry runs
# against stand-in tools; it has no other use.

say() { printf '%s\n' "$*"; }
die() {
    say
    say "STOP: $*"
    say "Nothing was changed."
    exit 1
}
field() { awk -F': *' -v key="$1" '$0 ~ key {print $2; exit}'; }
group_of() { diskutil info "$1" 2>/dev/null | field 'APFS Volume Group'; }
name_of() { diskutil info "$1" 2>/dev/null | field 'Volume Name'; }
mount_of() { diskutil info "$1" 2>/dev/null | field 'Mount Point'; }

case "$0" in
    */*) cd "${0%/*}" || exit 1 ;;
esac
BUNDLE=$(pwd)
[ -f enroll.conf ] || die "enroll.conf is missing next to this script"
. ./enroll.conf

case "${1:-enroll}" in
    enroll)
        IMAGE=$CANDIDATE BYTES=$CANDIDATE_BYTES WORD=ENROLL
        WHAT="the new boot loader"
        AFTER="The Mac now starts Linux by itself when it powers on."
        # iBoot on these Macs only starts a small raw object: a 24 MiB image
        # with the kernel inside boot-looped here, and a sibling M5 Pro stops
        # just above 4.8 MiB. The kernel belongs in a file on this partition.
        [ "$BYTES" -le 4194304 ] ||
            die "$IMAGE is $BYTES bytes: too large for iBoot to start (4 MiB limit here)"
        ;;
    rollback)
        IMAGE=$ROLLBACK BYTES=$ROLLBACK_BYTES WORD=ROLLBACK
        WHAT="the boot object that was enrolled before"
        AFTER="The Mac waits for the cable again when it powers on."
        ;;
    *) die "usage: enroll.sh [rollback]" ;;
esac

for tool in diskutil bputil kmutil; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is not here: run this in recoveryOS"
done

# 1. The image is the one that was staged.
[ -f "$IMAGE" ] || die "$IMAGE is missing from $BUNDLE"
size=$(wc -c < "$IMAGE" | tr -d ' ')
[ "$size" = "$BYTES" ] || die "$IMAGE has $size bytes, $BYTES were staged"
want=$(awk -v file="$IMAGE" '$2 == file {print $1}' SHA256SUMS 2>/dev/null)
[ -n "$want" ] || die "SHA256SUMS has no entry for $IMAGE"
if command -v shasum >/dev/null 2>&1; then
    got=$(shasum -a 256 "$IMAGE" | awk '{print $1}')
elif command -v openssl >/dev/null 2>&1; then
    got=$(openssl dgst -sha256 "$IMAGE" | awk '{print $NF}')
else
    got=
fi
if [ -n "$got" ]; then
    [ "$got" = "$want" ] || die "$IMAGE does not have its recorded SHA-256"
    say "image:   $IMAGE, $size bytes, SHA-256 verified"
else
    say "image:   $IMAGE, $size bytes (no SHA-256 tool here; it was verified when staged)"
fi

# 2. The stub's System volume, found by its volume group and name. The EFI
#    partition's label differs from the stub's name only in case, so either
#    of the two can be the one mounted with a " 1" suffix.
SYSTEM=
VOLUMES=${ENROLL_VOLUMES:-/Volumes}
for volume in "$VOLUMES/$STUB_NAME" "$VOLUMES"/*; do
    [ -d "$volume" ] || continue
    [ "$(group_of "$volume")" = "$VGID" ] || continue
    [ "$(name_of "$volume")" = "$STUB_NAME" ] || continue
    SYSTEM=$volume
    break
done
if [ -z "$SYSTEM" ]; then
    # Not mounted: look the System-role volumes up and mount the right one.
    for device in $(diskutil apfs list 2>/dev/null |
                    awk '/APFS Volume Disk \(Role\):/ && /\(System\)/ {print $(NF-1)}'); do
        [ "$(group_of "$device")" = "$VGID" ] || continue
        diskutil mount "$device" >/dev/null 2>&1
        SYSTEM=$(mount_of "$device")
        break
    done
fi
[ -n "$SYSTEM" ] && [ -d "$SYSTEM" ] ||
    die "no $STUB_NAME System volume of volume group $VGID is visible here.
      (diskutil apfs list shows the volumes; the stub may have been recreated
      since this bundle was staged, which changes its volume group.)"
[ "$(group_of "$SYSTEM")" = "$VGID" ] || die "$SYSTEM is not in volume group $VGID"
say "target:  $STUB_NAME at $SYSTEM"
say "group:   $VGID"

# 3. This recoveryOS is the stub's own, and it is 1TR.
bputil -d -v "$VGID" > /tmp/enroll-bputil.txt 2>&1
if ! grep -q ': Paired' /tmp/enroll-bputil.txt; then
    cat /tmp/enroll-bputil.txt
    # The power button leads to the recoveryOS of the startup disk. After a
    # boot object failed to start, that was macOS again on this Mac.
    die "this recoveryOS is not the one paired with $STUB_NAME: it belongs to
      the current startup disk. Make $STUB_NAME the startup disk and come back:

          bless --setBoot --mount \"$SYSTEM\"
          shutdown -h now

      Wait 15 seconds, press and HOLD power until \"Loading startup options\",
      choose Options (not $STUB_NAME), open Terminal and run this script again."
fi
if ! grep -q 'one true recoveryOS' /tmp/enroll-bputil.txt; then
    die "this is not 1TR. Shut down fully, wait 15 seconds, then press and
      HOLD the power button in one go until \"Loading startup options\".
      Tapping it twice reaches the picker, but not 1TR."
fi
say "policy:  Paired, one true recoveryOS"

# 4. Keep a copy of what is enrolled now. Best effort, read-only on the Mac's
#    volumes: the rollback image is the way back, this copy is only evidence.
if [ "$WORD" = ENROLL ]; then
    for preboot in /System/Volumes/Preboot "$VOLUMES"/Preboot*; do
        [ -d "$preboot/$VGID/boot" ] || continue
        current=$(find "$preboot/$VGID/boot" -type f -name '*custom*' 2>/dev/null)
        [ -n "$current" ] || continue
        keep="enrolled-before-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$keep" 2>/dev/null || break
        printf '%s\n' "$current" | while IFS= read -r object; do
            cp "$object" "$keep/" 2>/dev/null && say "saved:   $keep/${object##*/}"
        done
        break
    done
fi

say
say "This makes $WHAT what the Mac starts"
say "from $STUB_NAME. macOS and its own security settings are not touched."
say "kmutil will ask for your macOS user name and password."
say
printf 'Type %s and press return to go ahead; anything else stops here: ' "$WORD"
read -r answer
[ "$answer" = "$WORD" ] || die "not confirmed"

say
if kmutil configure-boot -c "$BUNDLE/$IMAGE" --raw \
    --entry-point 2048 --lowest-virtual-address 0 -v "$SYSTEM"; then
    say
    say "DONE. $AFTER"
    say "Restart with:  reboot"
else
    say
    say "kmutil reported an error (above). If it was the password, run this"
    say "script again. Unless kmutil said it installed the new object, the"
    say "previous one is still in place."
    exit 1
fi
