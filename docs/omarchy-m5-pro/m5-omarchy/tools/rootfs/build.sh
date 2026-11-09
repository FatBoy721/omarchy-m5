#!/bin/bash
# build.sh — build build/rootfs-alarm.tar.zst: verified ALARM aarch64 base + our kernel/modules/DTB,
# root ssh for work.pub, CDC-EEM gadget unit, probe module, kexec-tools (installed by pacman on first boot).
# All file ownership is kept in one fakeroot state file, so no real root is needed on the build host.
set -euo pipefail
R=$(cd "$(dirname "$0")/../.." && pwd); T=$R/tools/rootfs; A=$R/build/dl/alarm
S=$R/build/rootfs-stage; FR="fakeroot -i $R/build/rootfs.fakeroot -s $R/build/rootfs.fakeroot"
KREL=$(cat "$R/build/linux/include/config/kernel.release")
rm -rf "$S" "$R/build/rootfs.fakeroot"; mkdir -p "$S"; touch "$R/build/rootfs.fakeroot"
$FR bsdtar -xpf "$A/ArchLinuxARM-aarch64-latest.tar.gz" -C "$S"
$FR make -s -C "$R/src/linux-asahi-wip72" ARCH=arm64 LLVM=1 O="$R/build/linux" INSTALL_MOD_PATH="$S/usr" INSTALL_MOD_STRIP=1 modules_install
$FR sh -euc '
S=$1; R=$2; T=$3; A=$4
B=$R/build/linux/arch/arm64/boot
install -m644 $B/Image.gz $S/boot/Image.gz; install -m644 $B/Image $S/boot/Image
install -m644 $B/dts/apple/t6050-j714s.dtb $S/boot/m5.dtb
echo "maxcpus=1 keep_bootcon console=tty0 loglevel=7 pd_ignore_unused clk_ignore_unused nvme_apple.flush_interval=0 root=PARTUUID=@PARTUUID@ rw rootwait" > $S/boot/cmdline
install -d -m700 $S/root/.ssh; install -m600 $R/build/work.pub $S/root/.ssh/authorized_keys
install -m755 $T/files/m5-gadget-net $S/usr/local/bin/m5-gadget-net
install -m644 $T/files/m5-gadget-net.service $T/files/m5-firstboot.service $S/etc/systemd/system/
ln -sf /etc/systemd/system/m5-gadget-net.service $S/etc/systemd/system/multi-user.target.wants/m5-gadget-net.service
ln -sf /etc/systemd/system/m5-firstboot.service $S/etc/systemd/system/multi-user.target.wants/m5-firstboot.service
install -d $S/etc/systemd/system/getty@tty1.service.d; install -m644 $T/files/getty/autologin.conf $S/etc/systemd/system/getty@tty1.service.d/
install -d $S/usr/local/lib/m5; install -m644 $R/tools/t6050-probe/t6050_probe.ko $S/usr/local/lib/m5/
install -d $S/root/pkgs $S/var/lib/m5; install -m644 $A/kexec-tools-2.0.32-1-aarch64.pkg.tar.xz $S/root/pkgs/; touch $S/var/lib/m5/firstboot-pending
echo m5-j714s > $S/etc/hostname
# our kernel replaces the ALARM linux-aarch64 files in /boot: stop pacman from overwriting them
sed -i -E "s/^#?IgnorePkg *=.*/IgnorePkg = linux-aarch64 linux-aarch64-headers/" $S/etc/pacman.conf
grep -q "^IgnorePkg = linux-aarch64" $S/etc/pacman.conf
# remove ALARM default credentials (root:root, alarm:alarm): lock both passwords; access = work.pub ssh + tty1 autologin
sed -i -E "s/^(root|alarm):[^:]*:/\1:!:/" $S/etc/shadow
chown -R 0:0 $S/root $S/boot $S/usr/local $S/etc/systemd/system $S/var/lib/m5
' _ "$S" "$R" "$T" "$A"
$FR bsdtar --zstd --options zstd:compression-level=10,zstd:threads=0 --numeric-owner -cpf "$R/build/rootfs-alarm.tar.zst" -C "$S" .
cd "$R/build" && sha256sum rootfs-alarm.tar.zst | tee rootfs-alarm.tar.zst.sha256
echo "kernel.release: $KREL"
