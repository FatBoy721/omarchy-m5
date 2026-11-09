#!/bin/sh
# VM (QEMU virt, NOT hardware), task 12: gz3 = gz code + beacon3. Usage: tests/qemu-gz3.sh IMAGE.gz INITRD
# (the main kernel: the slim one has no QEMU console). VM: observed vram = 0xb9000000 640x480 (green),
# boot_args FB 0xb8000000 640x480 (strict-sane in the VM) -> console + simple-framebuffer there.
B=build
python3 tests/mkfake.py $B/g-ba.bin $B/g-adt.bin
qemu-system-aarch64 -M virt -cpu max -m 2G -machine dumpdtb=$B/virt-el1.dtb >/dev/null 2>&1
python3 tools/mkpayload.py $B/m5boot-vmgz3-code.bin $B/virt-el1.dtb $1 --initrd $2 -o $B/m5boot-vmgz3.bin
LOAD="-device loader,file=$B/g-ba.bin,addr=0x44000000,force-raw=on -device loader,file=$B/g-adt.bin,addr=0x44010000,force-raw=on \
 -device loader,file=$B/m5boot-vmgz3.bin,addr=0x40200000,force-raw=on -device loader,addr=0xbef0001c,data=4,data-len=4 \
 -device loader,addr=0x40200000,cpu-num=0"
regs() {	# name, wait seconds, expected BITE seconds (or 0 = expect CTRL 0), mkfake flags, hook stage or -
	python3 tests/mkfake.py $B/g-ba.bin $B/g-adt.bin $4
	hook=""; [ "$5" != - ] && hook="-device loader,addr=0x44020000,data=$(($5 + 1)),data-len=4"
	got=$(printf 'xp /1wx 0xbef00014\nxp /1wx 0xbef0001c\nxp /1wx 0xb9000000\nxp /1wx 0xb912bffc\nxp /1wx 0xb912c000\nquit\n' | (sleep $2; cat) | \
		timeout 60 qemu-system-aarch64 -M virt -cpu max -m 2G -display none -monitor stdio -serial file:$B/gz3-$1.log $LOAD $hook | \
		grep -ao '^[0-9a-f]*: 0x[0-9a-f]*' | tr '\n' ' ')
	exp=$(printf '%08x' $((24000000 * $3))); ok=FAIL
	echo "$got" | grep -q "bef00014: 0x$exp bef0001c: 0x00000004 b9000000: 0x000ffc00 b912bffc: 0x000ffc00 b912c000: 0x00000000" && ok=ok
	echo "== gz3 $1: expect T $3 s (0x$exp): $got $ok"
}
regs hook-stage7 3 80 "" 7          # ADT/WDT-verify step
regs hook-stage11 4 120 "" 11       # inflate
regs hook-stage13 8 140 "" 13       # copy + FDT patch
regs panic-nomm 3 90 --no-memory-map -   # failed check (panic) in stage 8 -> beacons like an exception
# full run: Linux to the shell; WDT disabled before the jump (CTRL 0 at the end). Task 13: the fake ADT also has
# a carveout equal to the RAM window (native J714s region-id-24); it must be dropped, not block placement.
python3 tests/mkfake.py $B/g-ba.bin $B/g-adt.bin --ram-carveout
timeout 90 qemu-system-aarch64 -M virt -cpu max -m 2G -display none -monitor none -serial file:$B/gz3-full.log $LOAD || true
echo "== gz3 full:"
grep -aE 'console gz3|dropped|inflating|kernel [0-9a-f]+ \(entry|step 7:|simple-framebuffer|simplefb|Run /init|Not backgrounding|Attempted' $B/gz3-full.log | cut -c1-150
