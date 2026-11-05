#!/bin/sh
# VM (QEMU virt, NOT hardware), task 11: reproduce "MMU on at entry, MMIO unmapped". The DRAM-only pre-stub
# (tests/mmu-prestub.S -DDRAM_ONLY) maps only [1G,2G) with M|C|I on, then enters m5boot at file offset 0.
# The fake WDT (0xbef00000, CTRL preloaded 4) and the fake FB (0xb8000000) are unmapped while the MMU is on.
# Usage: tests/qemu-mmufirst.sh BEACON.bin [PROBE.bin]
#   beacon: prints WD1 BITE/CTRL + FB pixel. Works = BITE 24e6*170 (code 15: MMU+D$ on, base==vram, geom).
#   probe:  prints the serial log lines (PL011 mirror, VM builds only).
B=build
python3 tests/mkfake.py $B/m-ba.bin $B/m-adt.bin
STUB="-device loader,file=$B/mmu-prestub-dram.bin,addr=0x43800000,force-raw=on -device loader,addr=0x43800000,cpu-num=0"
LOAD="-device loader,file=$B/m-ba.bin,addr=0x44000000,force-raw=on -device loader,file=$B/m-adt.bin,addr=0x44010000,force-raw=on -device loader,addr=0xbef0001c,data=4,data-len=4"
printf 'xp /1wx 0xbef00014\nxp /1wx 0xbef0001c\nxp /1wx 0xb8000000\nquit\n' | (sleep 2; cat) | \
	timeout 20 qemu-system-aarch64 -M virt -cpu max -m 2G -display none -monitor stdio -serial none $LOAD \
	-device loader,file=$1,addr=0x40200000,force-raw=on $STUB | grep -ao '^[0-9a-f]*: 0x[0-9a-f]*' | tr '\n' ' '
echo
if [ -n "$2" ]; then
	timeout 15 qemu-system-aarch64 -M virt -cpu max -m 2G -display none -monitor none -serial file:$B/mmufirst-probe.log $LOAD \
		-device loader,file=$2,addr=0x40200000,force-raw=on $STUB >/dev/null 2>&1
	grep -aE 'step 1:|PROBE' $B/mmufirst-probe.log | cut -c1-140
fi
