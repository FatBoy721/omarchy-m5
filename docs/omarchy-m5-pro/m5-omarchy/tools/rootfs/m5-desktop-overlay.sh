#!/bin/sh
# m5-desktop-overlay.sh ROOT (task 27): turn the Omarchy rootfs into "boot straight into Hyprland" for the s5 image.
# Run inside `unshare --map-root-user --map-auto` (files keep their in-namespace owners). Idempotent.
set -eu
T=$1; F=$(cd "$(dirname "$0")" && pwd)/desktop
# 1. user: ALARM's alarm (uid 1000, wheel; password locked '!') gets Omarchy's /etc/skel, as useradd -m would
cp -an "$T"/etc/skel/. "$T"/home/alarm/
chown -R 1000:1000 "$T"/home/alarm
for g in video input seat; do grep -q "^$g:.*[:,]alarm" "$T"/etc/group || sed -i "s/^\($g:x:[0-9]*:\)\(.*\)$/\1\2,alarm/; s/^\($g:x:[0-9]*:\),alarm$/\1alarm/" "$T"/etc/group; done
# 2. SDDM autologin into the uwsm-managed Hyprland session (Omarchy's session); VT1
install -D -m644 /dev/stdin "$T"/etc/sddm.conf.d/20-m5-autologin.conf <<'C'
[Autologin]
User=alarm
Session=hyprland-uwsm
Relogin=false
C
# 3. software rendering: no GPU driver; simpledrm card0 + Mesa llvmpipe (kms_swrast)
install -D -m644 /dev/stdin "$T"/etc/environment.d/50-m5-swrender.conf <<'C'
LIBGL_ALWAYS_SOFTWARE=1
GALLIUM_DRIVER=llvmpipe
AQ_DRM_DEVICES=/dev/dri/card0
C
grep -q LIBGL_ALWAYS_SOFTWARE "$T"/etc/environment || cat "$T"/etc/environment.d/50-m5-swrender.conf >> "$T"/etc/environment
# 4. boot target: graphical (SDDM is already display-manager.service)
ln -sfn /usr/lib/systemd/system/graphical.target "$T"/etc/systemd/system/default.target
# 5. persistent journald
install -D -m644 /dev/stdin "$T"/etc/systemd/journald.conf.d/50-m5.conf <<'C'
[Journal]
Storage=persistent
C
mkdir -p "$T"/var/log/journal
# 6. ESP logger + first-boot resize
install -D -m755 "$F"/m5-esplog-rootfs "$T"/usr/local/bin/m5-esplog-rootfs
install -D -m755 "$F"/m5-resize-root "$T"/usr/local/bin/m5-resize-root
install -m644 "$F"/m5-esplog.service "$F"/m5-esplog.timer "$F"/m5-resize-root.service "$T"/etc/systemd/system/
mkdir -p "$T"/etc/systemd/system/sysinit.target.wants "$T"/etc/systemd/system/multi-user.target.wants "$T"/var/lib/m5
ln -sfn /etc/systemd/system/m5-esplog.timer "$T"/etc/systemd/system/sysinit.target.wants/m5-esplog.timer
ln -sfn /etc/systemd/system/m5-resize-root.service "$T"/etc/systemd/system/multi-user.target.wants/m5-resize-root.service
touch "$T"/var/lib/m5/resize-pending
# 7. root by label (the initramfs mounts it; systemd remounts per fstab)
grep -q '^LABEL=omarchy' "$T"/etc/fstab || { sed -i '/[[:space:]]\/[[:space:]]/d' "$T"/etc/fstab; echo 'LABEL=omarchy / ext4 rw,relatime 0 1' >> "$T"/etc/fstab; }
# 8. no USB on the Mac (ATC0 needs PMP): drop the gadget unit so boot doesn't wait on it
rm -f "$T"/etc/systemd/system/multi-user.target.wants/m5-gadget-net.service
# 9. MTP trackpad firmware (task 28), if extracted (build/firmware; Apple's, local use only)
FW=$(cd "$(dirname "$0")/../.." && pwd)/build/firmware/apple/tpmtfw-j714s.bin
[ -f "$FW" ] && install -D -m644 "$FW" "$T"/usr/lib/firmware/apple/tpmtfw-j714s.bin
echo "overlay done"
