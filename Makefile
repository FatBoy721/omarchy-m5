# omarchy-m5 dev harness
.PHONY: setup fetch m1n1 m1n1-gpu m1n1-gpu-simpledrm aura aura-kernel aura-test kernel kernel-aurora kernel-aurora-gpu kernel-aurora-gpu-simpledrm dtbs initramfs payload tether clean-vendor
AURA_ROLLBACK ?= build/m1n1-enrolled-stage1.bin

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
