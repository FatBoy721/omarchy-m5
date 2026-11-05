#!/bin/sh
# VM (QEMU virt, NOT hardware): the real J714s Image + initramfs through m5boot, EL1 and EL2.
# The J714s Image writes a red marker to a hard-coded PA 0x10bd3110000 early in boot (see NOTES), so
# QEMU gets 1100 GiB of sparse RAM (reserve=off) to make that address exist. m5boot's /memory still
# limits Linux to the fake 1.75 GiB window. Uses QEMU's virt DTB (the J714s DTB describes Apple HW).
B=build; IMG=$1; INITRD=$2
MEM="-m 1100G -object memory-backend-ram,id=m,size=1100G,reserve=off"
python3 tests/mkfake.py $B/vm-ba.bin $B/vm-adt.bin
for el in el1 el2; do
	M=virt,highmem=on,memory-backend=m; [ $el = el2 ] && M=$M,virtualization=on
	qemu-system-aarch64 -M $M -cpu max $MEM -machine dumpdtb=$B/j-$el.dtb >/dev/null 2>&1
	python3 tools/mkpayload.py $B/m5boot-vm-code.bin $B/j-$el.dtb $IMG --initrd $INITRD -o $B/m5boot-j.bin
	timeout 90 qemu-system-aarch64 -M $M -cpu max $MEM -display none -monitor none -serial file:$B/j-$el.log \
		-device loader,file=$B/vm-ba.bin,addr=0x44000000,force-raw=on \
		-device loader,file=$B/vm-adt.bin,addr=0x44010000,force-raw=on \
		-device loader,file=$B/m5boot-j.bin,addr=0x40200000,force-raw=on \
		-device loader,addr=0xbef0001c,data=4,data-len=4 \
		-device loader,addr=0x40200800,cpu-num=0 >/dev/null 2>&1
	echo "== VM J714s $el: $(grep -c . $B/j-$el.log) lines"
done
