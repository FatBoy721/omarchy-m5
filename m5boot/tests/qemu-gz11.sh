#!/bin/sh
# VM (QEMU virt, NOT hardware), task 20: gz11 code + main Image.gz (the desktop kernel has no virtio drivers) +
# the task-27 initramfs-slim. The J714s-like disk (tests/mkdisk-j714s.sh) gets, on s5, a SMALL stub ext4 (label
# "omarchy", /sbin/init = a busybox script that announces itself) instead of the 19 GB Omarchy image, so the
# m5.root=s5 -> m5-root -> switch_root path runs end to end. Disk = virtio-blk 4096-byte blocks, m5.logdisk=vda
# (via the fake iBoot cmdline). Usage: tests/qemu-gz11.sh IMAGE.gz INITRAMFS
set -e
B=build; S=$1; I=$2
L4=$((213629696 * 4096))	# s5 byte offset (mkdisk-j714s.sh layout)
R=$(mktemp -d); mkdir -p $R/bin $R/sbin $R/proc $R/dev $R/sys
(cd $R && zcat "$OLDPWD/$I" 2>/dev/null | cpio -i --quiet bin/busybox 2>/dev/null) || true
[ -x $R/bin/busybox ] || { zcat $I | (cd $R && cpio -i --quiet bin/busybox); }
ln -sf busybox $R/bin/sh
cat > $R/sbin/init <<'EOF'
#!/bin/sh
/bin/busybox mount -t devtmpfs dev /dev 2>/dev/null
/bin/busybox mount -t proc proc /proc 2>/dev/null
echo "M5ROOTFS-STUB: switch_root reached /sbin/init on $(/bin/busybox awk '$2=="/"{print $1}' /proc/mounts)" | /bin/busybox tee /dev/kmsg
exec /bin/busybox sleep 100000
EOF
chmod 755 $R/sbin/init
sh tests/mkdisk-j714s.sh $B/v11disk.img >/dev/null 2>&1
# -b 4096: a small fs would default to 1 KiB blocks, which can't mount on a 4096-byte-logical-block device
# (EXT4-fs: bad block size 1024). The real rootfs-omarchy.ext4 uses 4096 (dumpe2fs).
mkfs.ext4 -q -F -b 4096 -L omarchy -E offset=$L4 -d $R $B/v11disk.img 16384 >/dev/null
rm -rf $R
python3 tests/mkfake.py $B/y-ba.bin $B/y-adt.bin --ram-carveout --logdisk
qemu-system-aarch64 -M virt -cpu max -m 2G -machine dumpdtb=$B/virt-el1.dtb >/dev/null 2>&1
python3 tools/mkpayload.py ${CODE:-$B/m5boot-vmgz11-code.bin} $B/virt-el1.dtb $S --initrd $I -o $B/m5boot-vmgz11.bin	# CODE= for gz13 etc.
timeout 70 qemu-system-aarch64 -M virt -cpu max -m 2G -display none -monitor none -serial file:$B/gz11.log \
	-device loader,file=$B/y-ba.bin,addr=0x44000000,force-raw=on -device loader,file=$B/y-adt.bin,addr=0x44010000,force-raw=on \
	-device loader,file=$B/m5boot-vmgz11.bin,addr=0x40200000,force-raw=on -device loader,addr=0xbef0001c,data=4,data-len=4 \
	-device loader,addr=0xbef00104,data=0x22,data-len=4 \
	-drive file=$B/v11disk.img,if=none,id=d0,format=raw \
	-device virtio-blk-device,drive=d0,logical_block_size=4096,physical_block_size=4096 \
	-device loader,addr=0x40200000,cpu-num=0 >/dev/null 2>&1 || true
grep -aE 'SECWDT step|Kernel command line|m5root:|m5log: (v4|esp|m5.root|raw)|switch_root|M5ROOTFS-STUB|Attempted to kill' $B/gz11.log | sed 's/^\[[^]]*\] //' | cut -c1-220
