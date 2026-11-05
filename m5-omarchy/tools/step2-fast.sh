#!/bin/sh
# SPDX-License-Identifier: MIT
# step2-fast.sh: fast re-arm of the Omarchy stub for a new boot object, run in the stub's paired 1TR.
# Derived from the step2.sh embedded in betizzel/omarchy-m5 scripts/finish-install.sh @15cd70c1 (MIT),
# which itself mirrors asahi-installer's step2 (MIT). Changes for fast test cycles:
#   1. bputil -nc only when the stub's LocalPolicy is not already Permissive;
#   2. kmutil configure-boot exactly as step2 does;
#   0. not paired: re-bless the stub as default and shut down, exactly as step2 (1TR follows the default);
#   3. after kmutil: restore the default to Macintosh HD, then bless the stub --nextonly (see report 18);
#   4. the install-media marker is disabled exactly as step2 does, then reboot.
# Placeholders ##DISTRO## ##VGID## ##PREBOOT## are filled in by the macOS-side deploy (see reports/18-fast-cycle.md).

DISTRO="##DISTRO##"
VGID="##VGID##"
PREBOOT="##PREBOOT##"

self="$0"
case "$self" in
    */*) cd "${self%/*}" || exit 1 ;;
esac
resources="$(pwd)"
system_dir="$(cd ../../../ && pwd)"
os_name="${system_dir##*/}"

printf '\033[2J\033[H'
echo "$DISTRO fast re-arm (step2-fast)"
echo
echo "VGID:          $VGID"
echo "System volume: $system_dir"
echo "Boot object:   $resources/boot.bin ($(ls -l "$resources/boot.bin" 2>/dev/null | awk '{print $5}') bytes)"
echo

fail_shell() {
    echo
    echo "$1"
    echo "Dropping to a shell. Fix it, then re-run: $resources/step2-fast.sh"
    exec sh
}

retry() {   # retry <description> <cmd...>
    desc="$1"; shift
    while ! "$@"; do
        echo
        echo "$desc failed. Did you mistype your password?"
        echo "Press enter to retry, or type 's' + enter for a shell."
        read ans
        [ "$ans" = s ] && exec sh
    done
}

bputil -d -v "$VGID" > /tmp/bp.txt 2>&1 || true

if ! grep -q ': Paired' /tmp/bp.txt; then
    # As step2: 1TR is the recoveryOS paired with the DEFAULT startup volume. With Macintosh HD
    # as default, holding power reaches macOS's 1TR, not the stub's, and kmutil can't run here.
    # Make the stub the default (as step2 does), shut down, and the next power-hold reaches the stub's 1TR.
    echo "This is not the recoveryOS paired with $os_name. Making $os_name the default startup"
    echo "volume (as step2 does); admin credentials may be asked."
    bless --setBoot --mount "$system_dir" || fail_shell "bless --setBoot failed"
    echo
    echo "Press enter to shut down. Then press and HOLD power, pick '$os_name', Continue again."
    read _
    shutdown -h now
    exit 1
fi

if ! grep -q 'one true recoveryOS' /tmp/bp.txt; then
    echo
    echo "Not in One True RecoveryOS (1TR) mode - press and HOLD the power button"
    echo "in one continuous motion from a full power-off. Tapping twice reaches the"
    echo "picker but NOT 1TR."
    echo "Press enter to shut down and retry."
    read _
    shutdown -h now
    exit 1
fi

# 1. Permissive already? (bputil -d prints the policy's security mode)
if grep -qi 'permissive' /tmp/bp.txt; then
    echo "Stub LocalPolicy is already Permissive: skipping bputil -nc."
else
    echo "Lowering the security level of the $DISTRO stub only (macOS keeps its own)."
    echo "You will be asked for your macOS admin credentials twice. Press enter to continue."
    read _
    retry "bputil" bputil -nc -v "$VGID"
fi

if [ -e "/System/Volumes/iSCPreboot/$VGID/boot" ]; then
    # external volume: kmutil looks for AdminUserRecoveryInfo.plist in the wrong place; mirror it (as step2).
    diskutil mount "$PREBOOT" || true
    preboot="$(diskutil info "$PREBOOT" | sed -n 's, *Mount Point: *,,p')"
    [ -n "$preboot" ] && cp -R "$preboot/$VGID/var" "/System/Volumes/iSCPreboot/$VGID/"
fi

# 2. install the boot object, exactly as step2
echo
echo "Installing the boot object with kmutil (admin credentials)."
retry "kmutil" kmutil configure-boot -c "$resources/boot.bin" --raw \
    --entry-point 2048 --lowest-virtual-address 0 -v "$system_dir"

# 4. switch the stub off the install-media path (exactly as step2), so the next boot runs the boot object
mount -u -w "$system_dir" || fail_shell "could not remount $system_dir read-write"
cs="$system_dir/System/Library/CoreServices"
if [ -e "$system_dir/.IAPhysicalMedia" ]; then
    mv "$system_dir/.IAPhysicalMedia" "$system_dir/IAPhysicalMedia-disabled.plist"
fi
if [ -e "$cs/SystemVersion-disabled.plist" ]; then
    mv -f "$cs/SystemVersion-disabled.plist" "$cs/SystemVersion.plist"
fi

# 3. the default goes back to macOS, then the next boot ONLY goes to the stub.
# [HYPOTHESIS] both bless calls work from the stub's 1TR; untested. If restoring the default fails, the
# stub stays the default: a failing object then loops up to 5x until PanicMedic sends the Mac to Recovery
# (seen before, recoverable). Afterwards set Startup Disk -> Macintosh HD from macOS.
MAC="${M5_MACOS_VOL:-/Volumes/Macintosh HD}"
echo
if [ -d "$MAC/System/Library/CoreServices" ] && bless --mount "$MAC" --setBoot; then
    echo "Default startup volume restored to $MAC."
    restored=1
else
    echo "WARNING: could not restore the default to $MAC (not mounted, or bless refused)."
    echo "The stub stays the default. Afterwards: macOS -> System Settings -> Startup Disk -> Macintosh HD."
    restored=0
fi
if [ "$restored" = 1 ]; then
    bless --mount "$system_dir" --setBoot --nextonly \
        || echo "bless --nextonly failed: on the next power-on hold power -> $os_name -> Continue."
fi
echo
echo "Press enter to reboot."
read _
reboot
