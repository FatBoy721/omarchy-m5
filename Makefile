# omarchy-m5 dev harness
.PHONY: setup fetch m1n1 aura aura-kernel aura-test kernel dtbs initramfs payload tether clean-vendor
AURA_ROLLBACK ?= build/m1n1-enrolled-stage1.bin

setup:          ## install host deps (brew llvm, rust target, ...)
	scripts/setup.sh

fetch:          ## clone/update vendor/m1n1 + vendor/linux
	scripts/fetch-sources.sh

m1n1:           ## build chainloadable m1n1 (CHAINLOADING=0 for install image)
	scripts/build-m1n1.sh

aura:           ## build pinned proxy-only Mach-O Aura Stage 1 (no installation)
	scripts/build-aura.sh

aura-kernel:    ## build an isolated J714s kernel without fixed framebuffer markers
	scripts/build-aura-kernel.sh

aura-test: aura aura-kernel ## prepare RAM-only J714s tether + recovery artifacts
	python3 scripts/prepare-aura-test.py --rollback "$(AURA_ROLLBACK)"

kernel:         ## overlay DTs + build kernel (KCONFIG=asahi_defconfig to override)
	scripts/build-kernel.sh

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
