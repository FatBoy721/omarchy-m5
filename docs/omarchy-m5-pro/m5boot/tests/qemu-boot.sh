#!/bin/sh
# VM (QEMU virt, NOT hardware): fake boot_args/ADT -> m5boot -> real arm64 Linux Image -> earlycon on PL011.
# Usage: tests/qemu-boot.sh IMAGE [INITRD]   (runs at EL1, then EL2)
set -e
B=build; IMG=$1; INITRD=$2
python3 tests/mkfake.py $B/vm-ba.bin $B/vm-adt.bin
for run in el1 el2 el1-mmuon el2-mmuon; do
	el=${run%-mmuon}
	M=virt; [ $el = el2 ] && M=virt,virtualization=on
	# -mmuon: a pre-stub turns on an identity MMU + caches first (tests/mmu-prestub.S)
	ENTRY="-device loader,addr=0x40200800,cpu-num=0"
	[ $run != $el ] && ENTRY="-device loader,file=$B/mmu-prestub.bin,addr=0x43800000,force-raw=on -device loader,addr=0x43800000,cpu-num=0"
	# per-machine DTB: PSCI conduit differs (hvc at EL1, smc with EL2)
	qemu-system-aarch64 -M $M -cpu max -m 2G -machine dumpdtb=$B/virt-$el.dtb >/dev/null 2>&1
	python3 tools/mkpayload.py $B/m5boot-vm-code.bin $B/virt-$el.dtb $IMG ${INITRD:+--initrd $INITRD} -o $B/m5boot-vm.bin
	timeout 60 qemu-system-aarch64 -M $M -cpu max -m 2G -display none -monitor none -serial file:$B/vm-$run.log \
		-device loader,file=$B/vm-ba.bin,addr=0x44000000,force-raw=on \
		-device loader,file=$B/vm-adt.bin,addr=0x44010000,force-raw=on \
		-device loader,file=$B/m5boot-vm.bin,addr=0x40200000,force-raw=on \
		-device loader,addr=0xbef0001c,data=4,data-len=4 \
		$ENTRY || true
	echo "== VM $run: $(grep -c . $B/vm-$run.log) lines"
	grep -m1 'step 1:' $B/vm-$run.log
	grep -m2 'WD1_CTRL' $B/vm-$run.log
	grep -m1 'step 7:' $B/vm-$run.log
	grep -m1 'Booting Linux' $B/vm-$run.log
	grep -m1 'Machine model' $B/vm-$run.log
	grep -m1 'Kernel command line' $B/vm-$run.log
	grep -m1 'CPU: All CPU(s) started at EL' $B/vm-$run.log || true
	grep -m1 'simplefb registered' $B/vm-$run.log
	grep -m1 'Run /init' $B/vm-$run.log
done

# Early panic after the WDT step: no /chosen/memory-map. Expect PANIC + "watchdog: disabled" + halt.
python3 tests/mkfake.py $B/vm-ba-nomm.bin $B/vm-adt-nomm.bin --no-memory-map
timeout 15 qemu-system-aarch64 -M virt -cpu max -m 2G -display none -monitor none -serial file:$B/vm-panic.log \
	-device loader,file=$B/vm-ba-nomm.bin,addr=0x44000000,force-raw=on \
	-device loader,file=$B/vm-adt-nomm.bin,addr=0x44010000,force-raw=on \
	-device loader,file=$B/m5boot-vm.bin,addr=0x40200000,force-raw=on \
	-device loader,addr=0xbef0001c,data=4,data-len=4 \
	-device loader,addr=0x40200800,cpu-num=0 || true
echo "== VM panic:"
grep -A2 PANIC $B/vm-panic.log
