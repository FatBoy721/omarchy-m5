# omarchy-m5 dev harness
.PHONY: setup fetch m1n1 m1n1-gpu m1n1-gpu-simpledrm m1n1-gpu-n1 m1n1-gpu-standalone m1n1-gpu-n1-standalone m1n1-stage1 esp-gpu-n1-simpledrm payload-gpu-simpledrm payload-gpu-n1-simpledrm aura aura-kernel aura-test kernel kernel-aurora kernel-aurora-gpu kernel-aurora-gpu-simpledrm kernel-aurora-gpu-n1 kernel-aurora-gpu-n1-simpledrm kernel-aurora-n1 kernel-aurora-n1-simpledrm kernel-aurora-installer m1n1-installer dtbs initramfs payload tether clean-vendor m1n1-installer-stage2
AURA_ROLLBACK ?= build/m1n1-enrolled-stage1.bin
GPU_ADT ?= build/adt-runtime-j714s.bin
# GPT partition UUID of the Mac's EFI (FAT) partition, where the loader and kernel live for a native boot
ESP_PARTUUID ?= 79e793a2-ba60-4560-bf05-a8e268faddd9

setup:          ## install host deps (brew llvm, rust target, ...)
	scripts/setup.sh

fetch:          ## clone/update vendor/m1n1 + vendor/linux
	scripts/fetch-sources.sh

m1n1:           ## build chainloadable m1n1 (CHAINLOADING=0 for install image)
	scripts/build-m1n1.sh

m1n1-gpu:       ## build the isolated chainloadable GPU handoff; do not enroll it
	python3 scripts/prepare-m1n1-gpu.py
	M1N1=build/m1n1-gpu CHAINLOADING=1 scripts/build-m1n1.sh
	cp build/m1n1-gpu/build/m1n1.bin build/m1n1-chain-gpu.bin

m1n1-gpu-simpledrm: ## build the separate GPU loader supporting explicit Linux DCP opt-out
	python3 scripts/prepare-m1n1-gpu.py --simpledrm
	M1N1=build/m1n1-gpu-simpledrm CHAINLOADING=1 scripts/build-m1n1.sh
	cp build/m1n1-gpu-simpledrm/build/m1n1.bin build/m1n1-chain-gpu-simpledrm.bin

m1n1-gpu-n1:    ## GPU loader plus the DT-only N1 hand-off (Linux trains the link); do not enroll it
	python3 scripts/prepare-m1n1-gpu.py --simpledrm --n1
	M1N1=build/m1n1-gpu-n1 CHAINLOADING=1 scripts/build-m1n1.sh
	cp build/m1n1-gpu-n1/build/m1n1.bin build/m1n1-chain-gpu-n1.bin

m1n1-gpu-standalone: ## build a separate calibrated native loader; no enrollment
	python3 scripts/prepare-m1n1-gpu.py --simpledrm --standalone --adt "$(GPU_ADT)"
	M1N1=build/m1n1-gpu-standalone CHAINLOADING=0 scripts/build-m1n1.sh
	cp build/m1n1-gpu-standalone/build/m1n1.bin build/m1n1-stage1-gpu-simpledrm.bin

payload-gpu-simpledrm: m1n1-gpu-standalone ## package the verified GPU kernel/DT for native boot
	scripts/mkpayload.sh --m1n1 build/m1n1-stage1-gpu-simpledrm.bin \
		--kernel build/linux-aurora-gpu-out/arch/arm64/boot/Image.gz \
		--dtb build/linux-aurora-gpu-out/arch/arm64/boot/dts/apple/t6050-j714s-gpu-simpledrm.dtb \
		--out build/m1n1-gpu-simpledrm-payload.bin

m1n1-gpu-n1-standalone: ## the calibrated native loader with the N1 hand-off; no enrollment
	python3 scripts/prepare-m1n1-gpu.py --simpledrm --n1 --standalone --adt "$(GPU_ADT)"
	M1N1=build/m1n1-gpu-n1-standalone CHAINLOADING=0 scripts/build-m1n1.sh
	cp build/m1n1-gpu-n1-standalone/build/m1n1.bin build/m1n1-stage1-gpu-n1.bin

payload-gpu-n1-simpledrm: m1n1-gpu-n1-standalone ## package the verified N1 kernel/DT for native boot
	scripts/mkpayload.sh --m1n1 build/m1n1-stage1-gpu-n1.bin \
		--kernel build/linux-aurora-n1-out/arch/arm64/boot/Image.gz \
		--dtb build/linux-aurora-n1-out/arch/arm64/boot/dts/apple/t6050-j714s-gpu-n1-simpledrm.dtb \
		--out build/m1n1-gpu-n1-simpledrm-payload.bin

# Native boot in two stages. Keep the enrolled object a plain m1n1.bin:
# both objects with something appended (a kernel payload, a chainload=
# variable; sizes that are not multiples of 16 KiB) boot-looped under iBoot on
# J714s. So it carries its chainload target inside, reads the real loader from
# the EFI partition, and that one reads the kernel. Updating either is then a
# file copy, not a ceremony; without m1n1/boot.bin the enrolled loader falls
# back to its USB proxy.
m1n1-stage1:    ## the small object to enroll: chainloads m1n1/boot.bin from the EFI partition
	python3 scripts/prepare-m1n1-gpu.py --stage1 --chainload "$(ESP_PARTUUID);m1n1/boot.bin"
	M1N1=build/m1n1-stage1 CHAINLOADING=1 scripts/build-m1n1.sh
	cp build/m1n1-stage1/build/m1n1.bin build/m1n1-stage1-esp.bin
	@size=$$(wc -c < build/m1n1-stage1-esp.bin); \
	  [ $$((size % 16384)) -eq 0 ] && [ "$$(tail -c 8 build/m1n1-stage1-esp.bin)" = STACKBOT ] || \
	  { echo "build/m1n1-stage1-esp.bin is not a plain m1n1 image of a 16 KiB-multiple size" >&2; exit 1; }

esp-gpu-n1-simpledrm: ## EFI partition files for a native N1 boot: m1n1/boot.bin (loader), m1n1/payload.bin (kernel)
	python3 scripts/prepare-m1n1-gpu.py --simpledrm --n1 --standalone --storage --adt "$(GPU_ADT)"
	M1N1=build/m1n1-gpu-n1-esp CHAINLOADING=1 scripts/build-m1n1.sh
	mkdir -p build/esp-gpu-n1/m1n1
	{ cat build/m1n1-gpu-n1-esp/build/m1n1.bin; \
	  printf 'payload=%s;m1n1/payload.bin\n' "$(ESP_PARTUUID)"; } > build/esp-gpu-n1/m1n1/boot.bin
	scripts/mkpayload.sh --payload-file \
		--kernel build/linux-aurora-n1-out/arch/arm64/boot/Image.gz \
		--dtb build/linux-aurora-n1-out/arch/arm64/boot/dts/apple/t6050-j714s-gpu-n1-simpledrm.dtb \
		--out build/esp-gpu-n1/m1n1/payload.bin

aura:           ## build pinned proxy-only Mach-O Aura Stage 1 (no installation)
	scripts/build-aura.sh

aura-kernel:    ## build an isolated J714s kernel without fixed framebuffer markers
	scripts/build-aura-kernel.sh

aura-test: aura aura-kernel ## prepare RAM-only J714s tether + recovery artifacts
	python3 scripts/prepare-aura-test.py --rollback "$(AURA_ROLLBACK)"

kernel:         ## overlay DTs + build kernel (KCONFIG=asahi_defconfig to override)
	scripts/build-kernel.sh

kernel-aurora:  ## build the pinned Aurora J714s kernel with built-in DCP (no installation)
	scripts/build-kernel-aurora.sh

kernel-aurora-gpu: ## build the isolated J714s GPU trial; keep verified artifacts unchanged
	KERNEL_FLAVOR=aurora-gpu scripts/build-kernel-aurora.sh

kernel-aurora-gpu-simpledrm: ## build the shared GPU kernel with the isolated DCP-off DT
	KERNEL_FLAVOR=aurora-gpu-simpledrm scripts/build-kernel-aurora.sh

kernel-aurora-gpu-n1: ## this unit's GPU bins + N1 Wi-Fi/Bluetooth host, Linux DCP (use with m1n1-gpu-n1)
	KERNEL_FLAVOR=aurora-gpu-n1 scripts/build-kernel-aurora.sh

kernel-aurora-gpu-n1-simpledrm: ## same, DCP-off DTB (use with m1n1-gpu-n1)
	KERNEL_FLAVOR=aurora-gpu-n1-simpledrm scripts/build-kernel-aurora.sh

kernel-aurora-n1: ## the same kernel with TripleU613's unit DTB (GPU bins are per chip)
	KERNEL_FLAVOR=aurora-n1 scripts/build-kernel-aurora.sh

kernel-aurora-n1-simpledrm: ## TripleU613's unit, DCP-off DTB (for the installer m1n1)
	KERNEL_FLAVOR=aurora-n1-simpledrm scripts/build-kernel-aurora.sh

kernel-aurora-installer: ## build the installer's J714s kernel (N1 Wi-Fi/BT, PHYs, GPU)
	KERNEL_FLAVOR=aurora-installer scripts/build-kernel-aurora.sh

m1n1-installer: ## build the installer's J714s loader on omacom/m1n1 (N1 tunables)
	scripts/prepare-m1n1-installer.sh
	M1N1=build/m1n1-installer CHAINLOADING=1 scripts/build-m1n1.sh

m1n1-installer-stage2: ## build the ESP stage-2 (RELEASE=1 ESP_STAGE2=1) used by the J714s installer boot
	scripts/prepare-m1n1-installer.sh
	for s in 48 128 256; do cmp -s installer/recipes/m1n1-aurora/bootlogo_$$s.bin build/m1n1-installer/data/bootlogo_$$s.bin || cp installer/recipes/m1n1-aurora/bootlogo_$$s.bin build/m1n1-installer/data/; done
	cd build/m1n1-installer && $(MAKE) RELEASE=1 CHAINLOADING=1 ESP_STAGE2=1 USE_CLANG=1

dtbs:           ## overlay DTs + build device trees only (fast syntax check)
	scripts/build-kernel.sh dtbs

initramfs:      ## build a busybox/musl aarch64 initramfs (no root needed)
	scripts/mkinitramfs.py

payload:        ## m1n1 + bootargs + kernel + dtb + initramfs -> one boot object
	scripts/mkpayload.sh

tether:         ## pack proxyclient + artifacts for the Linux dev host
	scripts/mktether.sh

clean-vendor:   ## remove vendored sources
	rm -rf vendor/m1n1 vendor/linux vendor/aura
