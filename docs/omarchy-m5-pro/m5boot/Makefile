CC := clang
LD := ld.lld
OBJCOPY := llvm-objcopy
CFLAGS := --target=aarch64-none-elf -ffreestanding -fno-builtin -nostdinc -isystem $(shell $(CC) -print-resource-dir)/include \
	-Isrc/include -Isrc -Isrc/libfdt -O2 -Wall -Wextra -mgeneral-regs-only -mstrict-align -fno-pic -mcmodel=tiny \
	-fno-stack-protector -ffunction-sections -fdata-sections
SRCS := $(filter-out src/spin.c src/beacon.c,$(wildcard src/*.c src/*.S src/libfdt/*.c))
OBJS := $(patsubst src/%,build/hw/%.o,$(basename $(SRCS)))
VMOBJS := $(patsubst build/hw/%,build/vm/%,$(OBJS))
# VM: fake boot_args at 0x43000000, fake WDT inside RAM (see tests/mkfake.py)
VMDEFS := -DVM -DVM_BOOTARGS=0x44000000 -DWDT_EXPECT=0xbef00000ULL -DWDT_PA=0xbef00000 \
	-DVRAM_OBS_PA=0xb9000000ULL -DVRAM_OBS_SIZE=0x200000ULL -DVRAM_OBS_W=640 -DVRAM_OBS_H=480 \
	-DDRAM_OBS_BASE=0x40000000ULL -DDRAM_OBS_SIZE=0x80000000ULL \
	'-DDEFAULT_BOOTARGS="earlycon=pl011,0x9000000 console=ttyAMA0"'
HOSTSRC := src/fmt.c src/bootargs.c src/adt.c src/fdtpatch.c src/place.c src/payload.c $(wildcard src/libfdt/*.c)

all: build/m5boot-code.bin build/m5boot-vm-code.bin

# Task 05 variants. probe: halts before the jump, stub Image (no kernel). gz: probe instrumentation + Image.gz, jumps.
PDEFS := -DPROBE -DFB_SCALE=2
D_probe := $(PDEFS) -DPROBE_HALT
D_vmprobe := $(D_probe) $(VMDEFS)
D_gz := $(PDEFS)
D_vmgz := $(PDEFS) $(VMDEFS)
define VARIANT
build/$(1)/%.o: src/%.c $(wildcard src/*.h) Makefile ; @mkdir -p $$(dir $$@); $$(CC) $$(CFLAGS) $$(D_$(1)) -c $$< -o $$@
build/$(1)/%.o: src/%.S src/early.inc Makefile ; @mkdir -p $$(dir $$@); $$(CC) $$(CFLAGS) $$(D_$(1)) -c $$< -o $$@
build/m5boot-$(1).elf: src/link.ld ; $$(LINK)
build/m5boot-$(1)-code.bin: build/m5boot-$(1).elf ; $$(OBJCOPY) -O binary $$< $$@
endef
$(foreach v,probe vmprobe gz vmgz,$(eval $(call VARIANT,$(v))))
$(foreach v,probe vmprobe gz vmgz,$(eval build/m5boot-$(v).elf: $(patsubst build/hw/%,build/$(v)/%,$(OBJS))))
IMAGEGZ ?= $(IN)/linux/arch/arm64/boot/Image.gz
build/stub-image.bin: ; @mkdir -p build; python3 -c "b=bytearray(64); b[0x38:0x3c]=b'ARM\x64'; open('$@','wb').write(b)"
build/m5boot-probe.bin: build/m5boot-probe-code.bin build/stub-image.bin
	sh tools/check-inputs.sh $(DTB) && python3 tools/mkpayload.py $< $(DTB) build/stub-image.bin -o $@
build/m5boot-vmprobe.bin: build/m5boot-vmprobe-code.bin build/stub-image.bin
	python3 tools/mkpayload.py $< $(DTB) build/stub-image.bin -o $@
# Task 09: probe3 = the probe build with the vram tier a/b/c FB selection.
build/m5boot-probe3.bin: build/m5boot-probe.bin ; cp $< $@ && python3 tests/test_header.py $@ && sha256sum $@
# Task 08: same gz code, slim Image.gz + slim initramfs (paths from spec/inputs.md "slim" section; pass on the command line).
# Task 12: gz3 = gz code + beacon3 robustness (-DGZ3 -DBEACON: stage word, green paint, stage-coded beacon), slim inputs.
D_gz3 := $(PDEFS) -DBEACON -DGZ3
D_vmgz3 := $(D_gz3) $(VMDEFS)
$(foreach v,gz3 vmgz3,$(eval $(call VARIANT,$(v))))
$(foreach v,gz3 vmgz3,$(eval build/m5boot-$(v).elf: $(patsubst build/hw/%,build/$(v)/%,$(OBJS)) build/$(v)/beacon.o))
build/m5boot-gz3.bin: build/m5boot-gz3-code.bin
	test -n "$(IMAGEGZ2)" -a -n "$(INITRD2)" || { echo "set IMAGEGZ2= INITRD2= (spec/inputs.md slim section)" >&2; exit 1; }
	sh tools/check-inputs.sh $(DTB) $(IMAGEGZ2) $(INITRD2) && python3 tools/mkpayload.py $< $(DTB) $(IMAGEGZ2) --initrd $(INITRD2) -o $@
	python3 tests/test_header.py $@ && sha256sum $@
# Task 14: gz5 = gz4 code + m5boot-built cmdline (earlycon=m5fb,... panic=0 initcall_debug ignore_loglevel),
# with the task-23 slim kernel (pass IMAGEGZ5= INITRD5= from spec/inputs.md once listed; check-inputs verifies them).
D_gz5 := $(D_gz3) -DEARLYCON_M5FB
D_vmgz5 := $(D_gz5) $(VMDEFS)
$(foreach v,gz5 vmgz5,$(eval $(call VARIANT,$(v))))
$(foreach v,gz5 vmgz5,$(eval build/m5boot-$(v).elf: $(patsubst build/hw/%,build/$(v)/%,$(OBJS)) build/$(v)/beacon.o))
build/m5boot-gz5.bin: build/m5boot-gz5-code.bin
	test -n "$(IMAGEGZ5)" -a -n "$(INITRD5)" || { echo "set IMAGEGZ5= INITRD5= (spec/inputs.md, task 23 kernel)" >&2; exit 1; }
	sh tools/check-inputs.sh $(DTB) $(IMAGEGZ5) $(INITRD5) && python3 tools/mkpayload.py $< $(DTB) $(IMAGEGZ5) --initrd $(INITRD5) -o $@
	python3 tests/test_header.py $@ && sha256sum $@
# Task 22: gz13 = gz12 (gz11 code) + DTB U1 + m5_pmgr_allow=<ATC0 labels> (spec/inputs.md § Input v1, U1 cmdline).
D_gz13 := $(D_gz5) -DWDT_ALL -DPMGR_PS -DEARLYCON_XOFF=1 -DSECWDT \
	'-DCMDLINE_EXTRA="m5_pmgr_ro m5.esplog=1 m5.root=s5 m5_pmgr_allow=atc0_common,atc0_usb_aon,atc0_usb,atc0_phymxwrap"'
D_vmgz13 := $(D_gz13) $(VMDEFS) '-DWDT_EXTRA_PAS={0xbef00100ULL,0xbef00104ULL,0xbef00108ULL,0xbef0010cULL}' \
	-DPMGR_ATC_BLK=0xbef10000ULL -DPMGR_FAB_BLK=0xbef20000ULL -DSECWDT_PA=0xbef00104ULL
$(foreach v,gz13 vmgz13,$(eval $(call VARIANT,$(v))))
$(foreach v,gz13 vmgz13,$(eval build/m5boot-$(v).elf: $(patsubst build/hw/%,build/$(v)/%,$(OBJS)) build/$(v)/beacon.o))
# Task 20: gz11 = gz10 + m5.root=s5, desktop-v1 kernel + DTB C + task-27 initramfs-slim (DTB11= IMAGEGZ11= INITRD11=).
D_gz11 := $(D_gz5) -DWDT_ALL -DPMGR_PS -DEARLYCON_XOFF=1 '-DCMDLINE_EXTRA="m5_pmgr_ro m5.esplog=1 m5.root=s5"' -DSECWDT
D_vmgz11 := $(D_gz11) $(VMDEFS) '-DWDT_EXTRA_PAS={0xbef00100ULL,0xbef00104ULL,0xbef00108ULL,0xbef0010cULL}' \
	-DPMGR_ATC_BLK=0xbef10000ULL -DPMGR_FAB_BLK=0xbef20000ULL -DSECWDT_PA=0xbef00104ULL
$(foreach v,gz11 vmgz11,$(eval $(call VARIANT,$(v))))
$(foreach v,gz11 vmgz11,$(eval build/m5boot-$(v).elf: $(patsubst build/hw/%,build/$(v)/%,$(OBJS)) build/$(v)/beacon.o))
build/m5boot-gz11.bin: build/m5boot-gz11-code.bin
	test -n "$(DTB11)" -a -n "$(IMAGEGZ11)" -a -n "$(INITRD11)" || { echo "set DTB11= IMAGEGZ11= INITRD11=" >&2; exit 1; }
	sh tools/check-inputs.sh $(DTB11) $(IMAGEGZ11) $(INITRD11) && python3 tools/mkpayload.py $< $(DTB11) $(IMAGEGZ11) --initrd $(INITRD11) -o $@
	python3 tests/test_header.py $@ && sha256sum $@
# Task 19: gz10 = gz9 + the secondary-WDT clear (-DSECWDT), exact same inputs/cmdline (+ m5.wdt2=...).
D_gz10 := $(D_gz5) -DWDT_ALL -DPMGR_PS -DEARLYCON_XOFF=1 '-DCMDLINE_EXTRA="m5_pmgr_ro m5.esplog=1"' -DSECWDT
D_vmgz10 := $(D_gz10) $(VMDEFS) '-DWDT_EXTRA_PAS={0xbef00100ULL,0xbef00104ULL,0xbef00108ULL,0xbef0010cULL}' \
	-DPMGR_ATC_BLK=0xbef10000ULL -DPMGR_FAB_BLK=0xbef20000ULL -DSECWDT_PA=0xbef00104ULL
$(foreach v,gz10 vmgz10,$(eval $(call VARIANT,$(v))))
$(foreach v,gz10 vmgz10,$(eval build/m5boot-$(v).elf: $(patsubst build/hw/%,build/$(v)/%,$(OBJS)) build/$(v)/beacon.o))
build/m5boot-gz10.bin: build/m5boot-gz10-code.bin
	test -n "$(DTB9)" -a -n "$(IMAGEGZ9)" -a -n "$(INITRD9)" || { echo "set DTB9= IMAGEGZ9= INITRD9=" >&2; exit 1; }
	sh tools/check-inputs.sh $(DTB9) $(IMAGEGZ9) $(INITRD9) && python3 tools/mkpayload.py $< $(DTB9) $(IMAGEGZ9) --initrd $(INITRD9) -o $@
	python3 tests/test_header.py $@ && sha256sum $@
# Task 18b: gz9 = gz8 code with the task-26 "A+C" cmdline extra (m5_pmgr_ro) + slim-v4 kernel + DTB C + v4log
# initramfs (DTB9= IMAGEGZ9= INITRD9= from spec/inputs.md "Slim v4" / "Slim v4-log").
D_gz9 := $(D_gz5) -DWDT_ALL -DPMGR_PS -DEARLYCON_XOFF=1 '-DCMDLINE_EXTRA="m5_pmgr_ro m5.esplog=1"'
D_vmgz9 := $(D_gz9) $(VMDEFS) '-DWDT_EXTRA_PAS={0xbef00100ULL,0xbef00104ULL,0xbef00108ULL,0xbef0010cULL}' \
	-DPMGR_ATC_BLK=0xbef10000ULL -DPMGR_FAB_BLK=0xbef20000ULL
$(foreach v,gz9 vmgz9,$(eval $(call VARIANT,$(v))))
$(foreach v,gz9 vmgz9,$(eval build/m5boot-$(v).elf: $(patsubst build/hw/%,build/$(v)/%,$(OBJS)) build/$(v)/beacon.o))
build/m5boot-gz9.bin: build/m5boot-gz9-code.bin
	test -n "$(DTB9)" -a -n "$(IMAGEGZ9)" -a -n "$(INITRD9)" || { echo "set DTB9= IMAGEGZ9= INITRD9=" >&2; exit 1; }
	sh tools/check-inputs.sh $(DTB9) $(IMAGEGZ9) $(INITRD9) && python3 tools/mkpayload.py $< $(DTB9) $(IMAGEGZ9) --initrd $(INITRD9) -o $@
	python3 tests/test_header.py $@ && sha256sum $@
# Task 17: gz8 = gz7 + earlycon x offset (w/2) + m5.esplog=1 + read-only PMGR PS prints; slim v3 inputs:
# DTB8= (slim-v3 gz6+fb DTB), IMAGEGZ8=, INITRD8= from spec/inputs.md "Slim v3".
D_gz8 := $(D_gz5) -DWDT_ALL -DPMGR_PS -DEARLYCON_XOFF=1 '-DCMDLINE_EXTRA="m5.esplog=1"'
D_vmgz8 := $(D_gz8) $(VMDEFS) '-DWDT_EXTRA_PAS={0xbef00100ULL,0xbef00104ULL,0xbef00108ULL,0xbef0010cULL}' \
	-DPMGR_ATC_BLK=0xbef10000ULL -DPMGR_FAB_BLK=0xbef20000ULL
$(foreach v,gz8 vmgz8,$(eval $(call VARIANT,$(v))))
$(foreach v,gz8 vmgz8,$(eval build/m5boot-$(v).elf: $(patsubst build/hw/%,build/$(v)/%,$(OBJS)) build/$(v)/beacon.o))
build/m5boot-gz8.bin: build/m5boot-gz8-code.bin
	test -n "$(DTB8)" -a -n "$(IMAGEGZ8)" -a -n "$(INITRD8)" || { echo "set DTB8= IMAGEGZ8= INITRD8=" >&2; exit 1; }
	sh tools/check-inputs.sh $(DTB8) $(IMAGEGZ8) $(INITRD8) && python3 tools/mkpayload.py $< $(DTB8) $(IMAGEGZ8) --initrd $(INITRD8) -o $@
	python3 tests/test_header.py $@ && sha256sum $@
# Task 16: gz7 = gz6 + all-watchdog dump/disable (-DWDT_ALL), same inputs as gz6.
D_gz7 := $(D_gz5) -DWDT_ALL
D_vmgz7 := $(D_gz7) $(VMDEFS) '-DWDT_EXTRA_PAS={0xbef00100ULL,0xbef00104ULL,0xbef00108ULL,0xbef0010cULL}'
$(foreach v,gz7 vmgz7,$(eval $(call VARIANT,$(v))))
$(foreach v,gz7 vmgz7,$(eval build/m5boot-$(v).elf: $(patsubst build/hw/%,build/$(v)/%,$(OBJS)) build/$(v)/beacon.o))
build/m5boot-gz7.bin: build/m5boot-gz7-code.bin
	test -n "$(DTB6)" -a -n "$(IMAGEGZ5)" -a -n "$(INITRD5)" || { echo "set DTB6= IMAGEGZ5= INITRD5=" >&2; exit 1; }
	sh tools/check-inputs.sh $(DTB6) $(IMAGEGZ5) $(INITRD5) && python3 tools/mkpayload.py $< $(DTB6) $(IMAGEGZ5) --initrd $(INITRD5) -o $@
	python3 tests/test_header.py $@ && sha256sum $@
# Task 15: gz6 = gz5 code + slim kernel v2 + the task-24 DTB (DTB6=, from spec/inputs.md; check-inputs verifies it).
build/m5boot-gz6.bin: build/m5boot-gz5-code.bin
	test -n "$(DTB6)" -a -n "$(IMAGEGZ5)" -a -n "$(INITRD5)" || { echo "set DTB6= IMAGEGZ5= INITRD5=" >&2; exit 1; }
	sh tools/check-inputs.sh $(DTB6) $(IMAGEGZ5) $(INITRD5) && python3 tools/mkpayload.py $< $(DTB6) $(IMAGEGZ5) --initrd $(INITRD5) -o $@
	python3 tests/test_header.py $@ && sha256sum $@
# Task 13: gz4 = gz3 code + the RAM-window carveout fix, same slim inputs.
build/m5boot-gz4.bin: build/m5boot-gz3-code.bin
	test -n "$(IMAGEGZ2)" -a -n "$(INITRD2)" || { echo "set IMAGEGZ2= INITRD2= (spec/inputs.md slim section)" >&2; exit 1; }
	sh tools/check-inputs.sh $(DTB) $(IMAGEGZ2) $(INITRD2) && python3 tools/mkpayload.py $< $(DTB) $(IMAGEGZ2) --initrd $(INITRD2) -o $@
	python3 tests/test_header.py $@ && sha256sum $@
build/m5boot-gz2.bin: build/m5boot-gz-code.bin
	test -n "$(IMAGEGZ2)" -a -n "$(INITRD2)" || { echo "set IMAGEGZ2= INITRD2= (spec/inputs.md slim section)" >&2; exit 1; }
	sh tools/check-inputs.sh $(DTB) $(IMAGEGZ2) $(INITRD2) && python3 tools/mkpayload.py $< $(DTB) $(IMAGEGZ2) --initrd $(INITRD2) -o $@
	python3 tests/test_header.py $@ && sha256sum $@
build/m5boot-gz.bin: build/m5boot-gz-code.bin
	sh tools/check-inputs.sh $(DTB) $(IMAGEGZ) $(INITRD) && python3 tools/mkpayload.py $< $(DTB) $(IMAGEGZ) --initrd $(INITRD) -o $@
	@test $$(stat -c %s $@) -lt 25165824 || { echo "m5boot-gz.bin >= 24 MiB" >&2; rm $@; exit 1; }
# Task 05/06 spin: start.S entry + src/spin.c (validated FB fill only), code only, no payload.
D_spin := -DPROBE
D_vmspin := -DPROBE $(VMDEFS)
SPINSRC := start spin bootargs adt probefb lib
$(foreach v,spin vmspin,$(eval $(call VARIANT,$(v))))
build/m5boot-spin.elf: $(SPINSRC:%=build/spin/%.o)
build/m5boot-vmspin.elf: $(SPINSRC:%=build/vmspin/%.o)
# Task 10 beacon: start.S entry + src/beacon.c (result code -> WDT bite after 20+10*code s), code only.
D_beacon := -DPROBE -DBEACON
D_vmbeacon := -DPROBE -DBEACON $(VMDEFS)
build/m5boot-beacon3.bin: build/m5boot-beacon.bin ; cp $< $@ && sha256sum $@
BEACONSRC := start beacon bootargs adt probefb lib
$(foreach v,beacon vmbeacon,$(eval $(call VARIANT,$(v))))
build/m5boot-beacon.elf: $(BEACONSRC:%=build/beacon/%.o)
build/m5boot-vmbeacon.elf: $(BEACONSRC:%=build/vmbeacon/%.o)
build/m5boot-beacon.bin: build/m5boot-beacon-code.bin ; cp $< $@ && truncate -s %16384 $@ && python3 tests/test_header.py $@ && sha256sum $@
build/m5boot-vmbeacon.bin: build/m5boot-vmbeacon-code.bin ; cp $< $@ && truncate -s %16384 $@
build/m5boot-spin.bin: build/m5boot-spin-code.bin ; cp $< $@ && truncate -s %16384 $@
build/m5boot-vmspin.bin: build/m5boot-vmspin-code.bin ; cp $< $@ && truncate -s %16384 $@
probe: build/m5boot-probe.bin build/m5boot-spin.bin build/m5boot-gz.bin
	python3 tests/test_header.py $^
	sha256sum $^

build/hw/%.o: src/%.c $(wildcard src/*.h) Makefile ; @mkdir -p $(dir $@); $(CC) $(CFLAGS) -c $< -o $@
build/hw/%.o: src/%.S Makefile ; @mkdir -p $(dir $@); $(CC) $(CFLAGS) -c $< -o $@
build/vm/%.o: src/%.c $(wildcard src/*.h) Makefile ; @mkdir -p $(dir $@); $(CC) $(CFLAGS) $(VMDEFS) -c $< -o $@
build/vm/%.o: src/%.S Makefile ; @mkdir -p $(dir $@); $(CC) $(CFLAGS) $(VMDEFS) -c $< -o $@

# Position independence check: no absolute relocations in any input object.
LINK = $(LD) -T src/link.ld --gc-sections --no-rosegment -z max-page-size=4096 -o $@ $(filter %.o,$^) && \
	! llvm-readelf -r $(filter %.o,$^) | grep -E 'R_AARCH64_ABS(64|32)'

build/m5boot.elf: $(OBJS) src/link.ld ; $(LINK)
build/m5boot-vm.elf: $(VMOBJS) src/link.ld ; $(LINK)
build/m5boot-code.bin: build/m5boot.elf ; $(OBJCOPY) -O binary $< $@
build/m5boot-vm-code.bin: build/m5boot-vm.elf ; $(OBJCOPY) -O binary $< $@

# Real inputs: spec/inputs.md (hashes verified by tools/check-inputs.sh). Override on the command line.
IN := ~/m5-omarchy/build
DTB ?= $(IN)/linux/arch/arm64/boot/dts/apple/t6050-j714s.dtb
IMAGE ?= $(IN)/linux/arch/arm64/boot/Image
INITRD ?= $(IN)/initramfs.cpio.gz
# Final object: make build/m5boot.bin
build/m5boot.bin: build/m5boot-code.bin ; sh tools/check-inputs.sh $(DTB) $(IMAGE) $(INITRD) && python3 tools/mkpayload.py $< $(DTB) $(IMAGE) $(if $(INITRD),--initrd $(INITRD)) -o $@

test:
	@mkdir -p build
	cc -O1 -g -Wall -Isrc -o build/test_host tests/test_host.c src/fb.c src/font8x16.c && build/test_host
	cc -O1 -g -Wall -fsanitize=address,undefined -Isrc -Isrc/libfdt -o build/test_core tests/test_core.c $(HOSTSRC)
	cc -O2 -g -fsanitize=address,undefined -Isrc -o build/test_inflate tests/test_inflate.c src/inflate.c
	python3 tests/gen-inflate.py && build/test_inflate build/t0.gz build/t.raw build/t1.gz build/t.raw build/t9.gz build/t.raw
	for s in 1 2; do cc -O1 -g -fsanitize=address,undefined -DFB_SCALE=$$s -Isrc -o build/test_fbsafe tests/test_fbsafe.c src/probefb.c src/bootargs.c src/adt.c src/fb.c src/font8x16.c && build/test_fbsafe || exit 1; done
	cc -O1 -g -fsanitize=address,undefined -DHOST -Isrc -o build/test_beacon tests/test_beacon.c src/beacon.c src/probefb.c src/bootargs.c src/adt.c && build/test_beacon
	cc -O1 -g -fsanitize=address,undefined -Isrc -o build/test_native13 tests/test_native13.c src/place.c && build/test_native13
	cc -O1 -g -fsanitize=address,undefined -Isrc -o build/test_cmdline tests/test_cmdline.c src/cmdline.c src/fmt.c && build/test_cmdline
	cc -O1 -g -fsanitize=address,undefined -DHOST -Isrc -o build/test_wdt tests/test_wdt.c src/wdt.c && build/test_wdt
	python3 tests/test_payload.py
	build/test_core build/test_payload.bin $(DTB)

build/mmu-prestub.bin: tests/mmu-prestub.S
	@mkdir -p build
	$(CC) --target=aarch64-none-elf -c $< -o build/mmu-prestub.o
	$(LD) -Ttext=0x43800000 -o build/mmu-prestub.elf build/mmu-prestub.o
	$(OBJCOPY) -O binary build/mmu-prestub.elf $@

build/mmu-prestub-dram.bin: tests/mmu-prestub.S
	@mkdir -p build
	$(CC) --target=aarch64-none-elf -DDRAM_ONLY -c $< -o build/mmu-prestub-dram.o
	$(LD) -Ttext=0x43800000 -o build/mmu-prestub-dram.elf build/mmu-prestub-dram.o
	$(OBJCOPY) -O binary build/mmu-prestub-dram.elf $@

QIMAGE ?= ref/testkernel/Image
qemu: build/m5boot-vm-code.bin build/mmu-prestub.bin
	sh tests/qemu-boot.sh $(QIMAGE) $(INITRD)

clean: ; rm -rf build
.PHONY: all test qemu clean probe
