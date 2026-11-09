#!/bin/sh
# VM (QEMU virt, NOT hardware), task 19: gz10 code + main Image.gz + v4log initramfs. Fake WDT block 0xbef00000,
# extra regs 0xbef00100..0c preloaded 0x11/0x22/0x33/0x44; the VM "secondary WDT" = reg[2] = 0xbef00104.
# Case wdtv3: wdt-version 3 -> 0xbef00104 cleared, others untouched, cmdline m5.wdt2=0x22,0x0.
# Case wdtv1: no wdt-version -> nothing written, m5.wdt2=none.
B=build; S=${1:?Image.gz}; I=${2:?initramfs}
qemu-system-aarch64 -M virt -cpu max -m 2G -machine dumpdtb=$B/virt-el1.dtb >/dev/null 2>&1
python3 tools/mkpayload.py $B/m5boot-vmgz10-code.bin $B/virt-el1.dtb $S --initrd $I -o $B/m5boot-vmgz10.bin
run() {	# name, mkfake flags
	python3 tests/mkfake.py $B/x-ba.bin $B/x-adt.bin --ram-carveout $2
	printf 'xp /4wx 0xbef00100\nquit\n' | (sleep 30; cat) | \
	timeout 60 qemu-system-aarch64 -M virt -cpu max -m 2G -display none -monitor stdio -serial file:$B/gz10-$1.log \
		-device loader,file=$B/x-ba.bin,addr=0x44000000,force-raw=on -device loader,file=$B/x-adt.bin,addr=0x44010000,force-raw=on \
		-device loader,file=$B/m5boot-vmgz10.bin,addr=0x40200000,force-raw=on -device loader,addr=0xbef0001c,data=4,data-len=4 \
		-device loader,addr=0xbef00100,data=0x11,data-len=4 -device loader,addr=0xbef00104,data=0x22,data-len=4 \
		-device loader,addr=0xbef00108,data=0x33,data-len=4 -device loader,addr=0xbef0010c,data=0x44,data-len=4 \
		-device loader,addr=0x40200000,cpu-num=0 2>/dev/null | grep -ao 'bef00100: .*' | tr -d '\r'
	echo "== $1:"; grep -aE 'extra regs|SECWDT|Kernel command line' $B/gz10-$1.log | sed 's/^\[[^]]*\] //' | cut -c1-200
}
run wdtv3 ""
run wdtv1 --wdt-version1
