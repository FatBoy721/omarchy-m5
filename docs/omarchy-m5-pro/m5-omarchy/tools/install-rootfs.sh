#!/bin/sh
# install-rootfs.sh — runs on the Mac inside the first-boot initramfs (busybox + sfdisk + e2fsprogs).
# Formats the ONE "Linux filesystem" GPT partition of ~120 GB on the Apple internal disk and unpacks the
# ALARM rootfs streamed on stdin as a plain (uncompressed) tar. From work:
#   ssh root@10.55.0.2 sh /bin/install-rootfs.sh --dry-run      # guards only
#   zstd -dc build/rootfs-alarm.tar.zst | ssh root@10.55.0.2 'sh /bin/install-rootfs.sh --yes'
# Guards: the disk must carry Apple's ISC + APFS + Recovery partitions; exactly one Linux-type partition
# of 119.5–120.5 GB must exist; it must not be APFS/EFI/ISC/Recovery; it must not hold a filesystem
# unless --force; nothing is mounted from it. Any guard failure exits non-zero before writing anything.
set -eu
LINUX=0FC63DAF-8483-4772-8E79-3D69D8477DE4
APFS=7C3457EF-0000-11AA-AA11-00306543ECAC
ISC=69646961-6700-11AA-AA11-00306543ECAC
REC=52637672-7900-11AA-AA11-00306543ECAC
EFI=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
MIN=119500000000 MAX=120500000000
YES=0 FORCE=0 DRY=0 DISK=/dev/nvme0n1
for a; do case $a in --yes) YES=1;; --force) FORCE=1;; --dry-run) DRY=1;; /dev/*) DISK=$a;; *) if [ "${M5_TEST_FILE:-0}" = 1 ]; then DISK=$a; else echo "bad arg $a"; exit 2; fi;; esac; done
die() { echo "install-rootfs: REFUSING: $*" >&2; exit 1; }

[ -b "$DISK" ] || [ "${M5_TEST_FILE:-0}" = 1 ] || die "$DISK is not a block device"
DUMP=$(sfdisk -d "$DISK") || die "sfdisk -d $DISK failed"
echo "$DUMP" | grep -q '^label: gpt' || die "$DISK is not GPT"
SS=$(echo "$DUMP" | sed -n 's/^sector-size: *//p'); SS=${SS:-512}
for t in $ISC $APFS $REC; do echo "$DUMP" | grep -qi "type=$t" || die "$DISK lacks Apple partition type $t (not the Mac's internal disk?)"; done

CAND=$(echo "$DUMP" | grep -i "type=$LINUX" || true)
[ "$(echo "$CAND" | grep -c .)" = 1 ] || die "need exactly one Linux-filesystem partition, found: $(echo "$CAND" | grep -c .)"
PART=$(echo "$CAND" | cut -d' ' -f1)
SIZE=$(( $(echo "$CAND" | sed -n 's/.*size= *\([0-9]*\).*/\1/p') * SS ))
PUUID=$(echo "$CAND" | sed -n 's/.*uuid=\([0-9A-Fa-f-]*\).*/\1/p' | tr A-F a-f)
TYPE=$(echo "$CAND" | sed -n 's/.*type=\([0-9A-Fa-f-]*\).*/\1/p' | tr a-f A-F)
[ "$TYPE" = "$LINUX" ] || die "type mismatch ($TYPE)"
for t in $APFS $ISC $REC $EFI; do [ "$TYPE" != "$t" ] || die "$PART has a protected type"; done
[ "$SIZE" -ge $MIN ] && [ "$SIZE" -le $MAX ] || die "$PART size $SIZE bytes is outside $MIN..$MAX"
[ -b "$PART" ] || [ "${M5_TEST_FILE:-0}" = 1 ] || die "$PART missing"
grep -q "^$PART " /proc/mounts && die "$PART is mounted"
FS=$(blkid "$PART" 2>/dev/null | sed -n 's/.* TYPE="\([^"]*\)".*/\1/p')   # busybox blkid syntax
[ -z "$FS" ] || [ $FORCE = 1 ] || die "$PART already has a filesystem ($FS); rerun with --force to overwrite"

echo "install-rootfs: target $PART  size $SIZE B  PARTUUID $PUUID  (sector size $SS)"
[ $DRY = 1 ] && { echo "install-rootfs: dry run, all guards passed, nothing written"; exit 0; }
[ $YES = 1 ] || { printf 'Format %s as ext4 and install? type YES: ' "$PART"; read -r ans; [ "$ans" = YES ] || die "not confirmed"; }

mkfs.ext4 -F -L m5root "$PART"
mkdir -p /mnt && mount -t ext4 "$PART" /mnt
tar -x -p -f - -C /mnt                                 # rootfs tar on stdin
[ -f /mnt/etc/os-release ] || { umount /mnt; die "unpack produced no /etc/os-release"; }
echo "PARTUUID=$PUUID  /  ext4  rw,relatime  0 1" > /mnt/etc/fstab
sed -i "s/@PARTUUID@/$PUUID/" /mnt/boot/cmdline
echo "install-rootfs: /etc/fstab and /boot/cmdline now use PARTUUID=$PUUID"; cat /mnt/boot/cmdline
sync; umount /mnt
echo "install-rootfs: done. Boot it with: m5-loader $PART   (or set m5.root=$PART)"
