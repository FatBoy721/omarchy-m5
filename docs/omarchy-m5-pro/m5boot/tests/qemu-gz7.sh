#!/bin/sh
# VM (QEMU virt, NOT hardware), task 16: gz7 code with the main Image.gz (the slim kernel has no QEMU console).
# Fake WDT block 0xbef00000: WD0_CTRL (+0x0c) and WD2_CTRL (+0x2c) preloaded armed (4), WD1_CTRL (+0x1c) armed (4,
# cleared by the entry write); the 4 extra regs 0xbef00100.. preloaded 0x11/0x22/0x33/0x44 (must stay unchanged).
B=build; S=${1:?Image.gz}; I=${2:?initramfs}
python3 tests/mkfake.py $B/w-ba.bin $B/w-adt.bin
qemu-system-aarch64 -M virt -cpu max -m 2G -machine dumpdtb=$B/virt-el1.dtb >/dev/null 2>&1
python3 tools/mkpayload.py $B/m5boot-vmgz7-code.bin $B/virt-el1.dtb $S --initrd $I -o $B/m5boot-vmgz7.bin
printf 'xp /1wx 0xbef0000c\nxp /1wx 0xbef0001c\nxp /1wx 0xbef0002c\nxp /4wx 0xbef00100\nquit\n' | (sleep 25; cat) | \
timeout 60 qemu-system-aarch64 -M virt -cpu max -m 2G -display none -monitor stdio -serial file:$B/gz7.log \
	-device loader,file=$B/w-ba.bin,addr=0x44000000,force-raw=on -device loader,file=$B/w-adt.bin,addr=0x44010000,force-raw=on \
	-device loader,file=$B/m5boot-vmgz7.bin,addr=0x40200000,force-raw=on \
	-device loader,addr=0xbef0000c,data=4,data-len=4 -device loader,addr=0xbef0001c,data=4,data-len=4 \
	-device loader,addr=0xbef0002c,data=4,data-len=4 \
	-device loader,addr=0xbef00100,data=0x11,data-len=4 -device loader,addr=0xbef00104,data=0x22,data-len=4 \
	-device loader,addr=0xbef00108,data=0x33,data-len=4 -device loader,addr=0xbef0010c,data=0x44,data-len=4 \
	-device loader,addr=0x40200000,cpu-num=0 | grep -ao '^[0-9a-f]*: .*' | tr -d '\r'
echo "== serial:"
grep -aE 'WDT |Run /init|Not backgrounding' $B/gz7.log | cut -c1-200
