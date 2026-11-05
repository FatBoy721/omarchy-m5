#!/bin/sh
# VM (QEMU virt, NOT hardware): beacon3 (task 11 addendum). Fake WDT at 0xbef00000 (CTRL preloaded 4).
# Exception/failed check at stage s -> BITE = 24e6 * (10 + 10s); success -> 24e6 * 175.
# Test hook (VM builds only): the u32 at 0x44020000 = s+1 makes STAGE(s) execute brk.
B=build
make -s build/mmu-prestub-dram.bin >/dev/null
case_() {	# name, mkfake flags, expected seconds, hook stage (or -), entry args
	python3 tests/mkfake.py $B/b-ba.bin $B/b-adt.bin $2
	exp=$(printf '%08x' $((24000000 * $3)))
	hook=""; [ "$4" != - ] && hook="-device loader,addr=0x44020000,data=$(($4 + 1)),data-len=4"
	entry=${5:--device loader,addr=0x40200000,cpu-num=0}
	got=$(printf 'xp /1wx 0xbef00014\nxp /1wx 0xbef0001c\nxp /1wx 0xb9000000\nxp /1wx 0xb912bffc\nxp /1wx 0xb912c000\nxp /1wx 0xb8000000\nquit\n' | (sleep 2; cat) | \
	timeout 20 qemu-system-aarch64 -M virt -cpu max -m 2G -display none -monitor stdio -serial none \
	-device loader,file=$B/b-ba.bin,addr=0x44000000,force-raw=on -device loader,file=$B/b-adt.bin,addr=0x44010000,force-raw=on \
	-device loader,file=$B/m5boot-vmbeacon.bin,addr=0x40200000,force-raw=on $hook \
	-device loader,addr=0xbef0001c,data=4,data-len=4 $entry | \
	grep -ao '^[0-9a-f]*: 0x[0-9a-f]*' | tr '\n' ' ')
	ok=FAIL; echo "$got" | grep -q "bef00014: 0x$exp bef0001c: 0x00000004" && ok=ok
	echo "== beacon3 $1: T $3 s, BITE expect 0x$exp: $got $ok"
}
# Pixels: b9000000..b912bffc = observed-vram GREEN 0x000ffc00 (stage 5; b912c000 must stay 0), b8000000 = boot_args FB magenta.
case_ success "" 175 -
case_ fault-stage5 "" 60 5            # fault before the green paint: nothing painted
case_ fault-stage6 "" 70 6            # green done
case_ fault-stage10 "" 110 10         # green done, magenta not started
case_ fault-stage14 "" 150 14         # green + magenta done
case_ novram --no-vram 160 -          # failed check at stage 15 (no /vram)
case_ dram-only-mmu "" 175 - "-device loader,file=$B/mmu-prestub-dram.bin,addr=0x43800000,force-raw=on -device loader,addr=0x43800000,cpu-num=0"
