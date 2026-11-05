#!/bin/sh
# VM (QEMU virt, NOT hardware), task 18: the v4 logger on a J714s-like disk (tests/mkdisk-j714s.sh: 4096-byte logical
# blocks, exact s4/s5 sizes/types). The main kernel has virtio_blk but no NVMe-PCI driver, so the disk is a
# virtio-blk device with 4096-byte logical blocks and m5.logdisk=vda (the native default is nvme0n1).
# Usage: tests/qemu-v4log.sh KERNEL INITRAMFS
B=build; K=$1; I=$2
L4=$((213629696 * 4096)); E4=$((213507584 * 4096))	# s5 / s4 byte offsets (from mkdisk-j714s.sh's layout)
boot() {	# name disk
	timeout 40 qemu-system-aarch64 -M virt -cpu max -m 2G -display none -monitor none -serial file:$B/v4log-$1.log \
		-kernel $K -initrd $I -append "console=ttyAMA0 m5.esplog=1 m5.logdisk=vda" \
		-drive file=$2,if=none,id=d0,format=raw \
		-device virtio-blk-device,drive=d0,logical_block_size=4096,physical_block_size=4096 >/dev/null 2>&1
	echo "== $1: logger (kmsg):"; grep -a 'm5log:' $B/v4log-$1.log | sed 's/^\[[^]]*\] //' | cut -c1-150
	echo "   raw s5 head: $(dd if=$2 bs=4096 skip=$((L4 / 4096)) count=1 2>/dev/null | head -n1 | tr -d '\0' | cut -c1-80)"
	dd if=$2 bs=4096 skip=$((E4 / 4096)) count=122070 of=$B/esp.img 2>/dev/null
	echo "   ESP files: $(fsck.fat -n -l $B/esp.img 2>/dev/null | grep -i m5log | tr '\n' ' ')"
}
sh tests/mkdisk-j714s.sh $B/v4disk.img >/dev/null
boot fresh $B/v4disk.img
boot second $B/v4disk.img
sh tests/mkdisk-j714s.sh $B/v4junk.img >/dev/null
printf 'NOT-OURS' | dd of=$B/v4junk.img bs=4096 seek=$((L4 / 4096 + 100)) conv=notrunc 2>/dev/null	# junk inside s5's first 4 MiB
boot junk $B/v4junk.img
# Addendum 18: ESP not mountable (FAT boot sector wiped) -> mount failure logged on kmsg AND in the raw s5 log,
# and nothing written under the initramfs /mnt pretending to be the ESP.
sh tests/mkdisk-j714s.sh $B/v4badesp.img >/dev/null
dd if=/dev/zero of=$B/v4badesp.img bs=4096 seek=$((E4 / 4096)) count=256 conv=notrunc 2>/dev/null
boot badesp $B/v4badesp.img
echo "   raw log has the mount failure: $(dd if=$B/v4badesp.img bs=4096 skip=$((L4 / 4096)) count=1024 2>/dev/null | tr -d '\0' | grep -c 'esp mount .* FAILED') line(s)"
echo "   junk s5 head still: $(dd if=$B/v4junk.img bs=4096 skip=$((L4 / 4096)) count=1 2>/dev/null | tr -d '\0' | head -c 20)(empty = untouched)"
