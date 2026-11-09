#!/bin/sh
# VM (QEMU virt, NOT hardware): task 05 probe + spin. Fake WDT at 0xbef0001c (preloaded 4), fake FB 0xb8000000 inside fake ADT DRAM.
set -e
B=build
run() {	# name, mkfake flags, machine
	python3 tests/mkfake.py $B/p-ba.bin $B/p-adt.bin $2
	timeout 20 qemu-system-aarch64 -M $3 -cpu max -m 2G -display none -monitor none -serial file:$B/probe-$1.log \
		-device loader,file=$B/p-ba.bin,addr=0x44000000,force-raw=on \
		-device loader,file=$B/p-adt.bin,addr=0x44010000,force-raw=on \
		-device loader,file=$B/m5boot-vmprobe.bin,addr=0x40200000,force-raw=on \
		-device loader,addr=0xbef0001c,data=4,data-len=4 \
		-device loader,addr=${4:-0x40200800},cpu-num=0 || true
	echo "== VM probe $1:"; grep -E 'step 1:|PROBE|layout|WD1_CTRL now|step [2-7]:' $B/probe-$1.log | cut -c1-150
}
run el1 "" virt
run entry0 "" virt 0x40200000      # task 07 H-ENTRY: execution starts at file offset 0
run entry7fc "" virt 0x402007fc    # ... or at the last pad word
run el2 "" virt,virtualization=on
run badlayout --bad-layout virt
run fault --fault virt
run nomm --no-memory-map virt
run fboutside --fb-outside virt   # task 09: Video base outside /vram -> tier b
run tierc "--fb-outside --no-vram" virt   # no /vram node -> tier c (VM observed region)
# gz: probe instrumentation + real Image.gz inflated by m5boot + initramfs, 10 s pause, then Linux (virt DTB).
python3 tests/mkfake.py $B/p-ba.bin $B/p-adt.bin
qemu-system-aarch64 -M virt -cpu max -m 2G -machine dumpdtb=$B/virt-el1.dtb >/dev/null 2>&1
python3 tools/mkpayload.py $B/m5boot-vmgz-code.bin $B/virt-el1.dtb ${IMAGEGZ:?} --initrd ${INITRD:?} -o $B/m5boot-vmgz.bin
timeout 150 qemu-system-aarch64 -M virt -cpu max -m 2G -display none -monitor none -serial file:$B/probe-gz.log \
	-device loader,file=$B/p-ba.bin,addr=0x44000000,force-raw=on -device loader,file=$B/p-adt.bin,addr=0x44010000,force-raw=on \
	-device loader,file=$B/m5boot-vmgz.bin,addr=0x40200000,force-raw=on -device loader,addr=0xbef0001c,data=4,data-len=4 \
	-device loader,addr=0x40200800,cpu-num=0 || true
echo "== VM gz:"; grep -aE 'step [4-7]:|Image [0-9]|SUMMARY|in 1 s|Booting Linux|Run /init|Not backgrounding|Attempted' $B/probe-gz.log | cut -c1-150
# spin: check WD1_CTRL and the first/last FB pixel (640x480x4 at 0xb8000000) through the QEMU monitor
spin() {	# mkfake flags
	python3 tests/mkfake.py $B/s-ba.bin $B/s-adt.bin $1
	printf 'xp /1wx 0xbef0001c\nxp /1wx 0xb8000000\nxp /1wx 0xb812bffc\nxp /1wx 0xb812c000\nxp /1wx 0xb9000000\nxp /1wx 0xb912bffc\nxp /1wx 0xb912c000\nquit\n' | (sleep 2; cat) | \
	timeout 20 qemu-system-aarch64 -M virt -cpu max -m 2G -display none -monitor stdio -serial none \
	-device loader,file=$B/s-ba.bin,addr=0x44000000,force-raw=on -device loader,file=$B/s-adt.bin,addr=0x44010000,force-raw=on \
	-device loader,file=$B/m5boot-vmspin.bin,addr=0x40200000,force-raw=on \
	-device loader,addr=0xbef0001c,data=4,data-len=4 -device loader,addr=0x40200800,cpu-num=0 | grep -ao '^[0-9a-f]*: 0x[0-9a-f]*' | tr '\n' ' '
	echo
}
echo "== VM spin tier a (FB in /vram): expect bef0001c 0; b8000000/b812bffc 3ff003ff; b812c000 0; b9* 0"; spin ""
echo "== VM spin tier b (Video base outside /vram): expect same as tier a (painted at the /vram base)"; spin --fb-outside
echo "== VM spin tier c (no /vram, bad base): expect b8* 0; b9000000/b912bffc 3ff003ff; b912c000 0"; spin "--fb-outside --no-vram"
