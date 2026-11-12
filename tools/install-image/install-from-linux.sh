#!/bin/bash
# Install the J714s developer image from Linux running on the same Mac.
#
# This is how the image was installed on TripleU613's J714s on 2026-11-10: the
# three partitions of installer_data.json (EFI 500 MB FAT, Boot 2 GiB, Root
# >= 32 GiB) go into free space on the internal disk, the image's ESP tree,
# boot.img and root.img are written, and Apple's vendor firmware is packed onto
# the new ESP the way the installer does (vendorfw/). Nothing existing is
# resized, moved or deleted: make the free space first (see the README).
#
# usage: install-from-linux.sh IMAGE.zip FIRMWARE_DIR
#   FIRMWARE_DIR holds apple/centauri/j714s-ftab.bin and apple/tpmtfw-j714s.bin, and optionally
#   the camera setfiles apple/isp_*.dat
#   (on an existing J714s Linux: /usr/lib/firmware). It prints the m1n1 line
#   that boots the image; it does not change how the Mac boots.
set -euo pipefail

ZIP=${1:?usage: $0 IMAGE.zip FIRMWARE_DIR}
FW=${2:?usage: $0 IMAGE.zip FIRMWARE_DIR}
DISK=/dev/nvme0n1
ESP_SECTORS=128000     # 524288000 B in 4 KiB sectors
BOOT_SECTORS=524288    # 2 GiB
ROOT_MIN_SECTORS=8388608  # 32 GiB

die() { echo "install-from-linux: $*" >&2; exit 1; }
[[ $EUID == 0 ]] || die "run as root"
grep -q 'apple,j714s' /proc/device-tree/compatible 2>/dev/null || die "not a J714s (MacBook Pro 14-inch, M5 Pro)"
for t in sgdisk mkfs.fat unzip partx python3 tar; do command -v $t >/dev/null || die "missing $t"; done
[[ -f $FW/apple/centauri/j714s-ftab.bin && -f $FW/apple/tpmtfw-j714s.bin ]] || die "firmware not found in $FW"
[[ $(blockdev --getss $DISK) == 4096 ]] || die "expected 4 KiB sectors on $DISK"
unzip -l "$ZIP" | grep -q ' root.img$' || die "$ZIP is not the J714s image zip"
blkid -t UUID=4F4D-5801 >/dev/null 2>&1 && die "a partition with the image's ESP UUID already exists; install once"

# The largest free region, 1 MiB aligned.
read -r START END < <(sgdisk -F $DISK >/dev/null; python3 - "$DISK" <<'E'
import subprocess, sys
out = subprocess.run(["sgdisk", "-p", sys.argv[1]], capture_output=True, text=True, check=True).stdout
parts = sorted((int(l.split()[1]), int(l.split()[2])) for l in out.splitlines()
               if l.strip()[:1].isdigit())
last = int([l for l in out.splitlines() if "last usable sector" in l.lower()][0].split()[-1])
best, prev = (0, 0), 5
for s, e in parts + [(last + 1, last + 1)]:
    a, b = (prev + 1 + 255) // 256 * 256, (s // 256) * 256 - 1
    if b - a > best[1] - best[0]:
        best = (a, b)
    prev = max(prev, e)
print(*best)
E
)
NEED=$((ESP_SECTORS + BOOT_SECTORS + ROOT_MIN_SECTORS + 512))
(( END - START + 1 >= NEED )) || die "largest free region is $(( (END-START+1)*4096/1073741824 )) GiB; need about 35 GiB free"

E7=$((START + ESP_SECTORS - 1)); S8=$(( (E7 + 1 + 255) / 256 * 256 )); E8=$((S8 + BOOT_SECTORS - 1))
S9=$(( (E8 + 1 + 255) / 256 * 256 ))
echo "partitions: EFI $START-$E7, Boot $S8-$E8, Root $S9-$END ($(( (END-S9+1)*4096/1073741824 )) GiB)"
read -r -p "write them to $DISK? [y/N] " ok; [[ $ok == y ]] || die "aborted"

n() { sgdisk -F $DISK >/dev/null; sgdisk -p $DISK | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1}' | sort -n | awk 'BEGIN{i=1} $1==i{i++} END{print i}'; }
P7=$(n); sgdisk -n $P7:$START:$E7 -t $P7:ef00 -c $P7:"EFI - OMARC" $DISK >/dev/null
P8=$(n); sgdisk -n $P8:$S8:$E8 -t $P8:8300 -c $P8:"Omarchy Boot" $DISK >/dev/null
P9=$(n); sgdisk -n $P9:$S9:$END -t $P9:8300 -c $P9:"Omarchy Root" $DISK >/dev/null
partx -a $DISK 2>/dev/null || partx -u $DISK
udevadm settle

WORK=$(mktemp -d); trap 'umount "$WORK/esp" 2>/dev/null || true; rm -rf "$WORK"' EXIT
mkfs.fat -F 32 -i 4f4d5801 ${DISK}p$P7 >/dev/null
mkdir "$WORK/esp" "$WORK/x" && mount ${DISK}p$P7 "$WORK/esp"
unzip -o -q "$ZIP" 'esp/*' -d "$WORK/x" && cp -r "$WORK/x/esp/." "$WORK/esp/"
mkdir -p "$WORK/esp/vendorfw" "$WORK/esp/asahi"
# vendorfw the way the installer packs it (firmware.tar is what the image installs)
FILES=(apple/centauri/j714s-ftab.bin apple/tpmtfw-j714s.bin)
# Front camera tuning (IMX958 setfiles, extracted from macOS by omacom/omarchy-mac-installer#208's
# code); optional: without them the camera still streams, badly.
for f in "$FW"/apple/isp_*.dat; do [[ -f $f ]] && FILES+=("apple/${f##*/}"); done
tar -C "$FW" -cf "$WORK/esp/vendorfw/firmware.tar" "${FILES[@]}"
(cd "$FW" && sha256sum "${FILES[@]}" | awk '{print "FILE "$2" SHA256 "$1}') > "$WORK/esp/vendorfw/manifest.txt"
echo "vendor firmware packed: ${FILES[*]}"
sync; umount "$WORK/esp"

for img in boot.img:$P8 root.img:$P9; do
  echo "writing ${img%%:*}..."
  unzip -p "$ZIP" "${img%%:*}" | dd of=${DISK}p${img##*:} bs=4M conv=fsync status=none
done
sync
blkid ${DISK}p$P8 ${DISK}p$P9 | grep -q 4f4d5801-524f-4f54-8000-000000000001 || die "root filesystem UUID not found after writing"

ESP_UUID=$(blkid -s PARTUUID -o value ${DISK}p$P7)
cat <<EOF

Installed. To boot it, have your stage-1 m1n1 chainload the image's stage 2
with the new ESP named:

  m1n1 stage 2: the new ESP's m1n1/boot.bin
  plus the line: chosen.asahi,efi-system-partition=$ESP_UUID

(From a Linux host over the m1n1 USB proxy: append that line to a copy of
m1n1/boot.bin and run tools/m5-remote/bmboot.sh on it. To make it the default,
point your stage 1's chainload target at it; keep the old target as rollback.)
EOF
