#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# mktether.sh - pack everything the Linux dev host needs to drive the M5
# over USB-C into one tarball.
#
# The M5 is the target: while m1n1 owns it, macOS (and this repo) are not
# running, so the proxyclient has to live on the other machine.
#
#   scripts/mktether.sh              -> build/tether-bundle.tar.gz
#   KERNEL_FLAVOR=aurora scripts/mktether.sh -> build/tether-aurora-bundle.tar.gz
#   KERNEL_FLAVOR=aurora-gpu scripts/mktether.sh -> build/tether-aurora-gpu-bundle.tar.gz
#   KERNEL_FLAVOR=aurora-gpu-simpledrm scripts/mktether.sh -> separate DCP-off GPU bundle
# The GPU trial uses its isolated loader; M1N1_CHAIN overrides the binary.
#   scp build/tether-bundle.tar.gz thinkpad:
#
# Everything in the bundle is self-contained: m1n1's proxyclient package,
# the kernel/DT/initramfs, a chainloadable m1n1, the udev rule, and two
# runner scripts.

set -euo pipefail

cd "$(dirname "$0")/.."

BOARD="j714s"
KERNEL_FLAVOR="${KERNEL_FLAVOR:-asahi}"
CHAIN="${M1N1_CHAIN:-build/m1n1-chain.bin}"
DT_NAME="t6050-$BOARD.dtb"
GPU_TRIAL=0

die() { echo "ERROR: $*" >&2; exit 1; }

case "$KERNEL_FLAVOR" in
    asahi)
        OUT="build/tether-bundle.tar.gz"
        STAGE="build/tether"
        BOOT="vendor/linux/arch/arm64/boot"
        BUILD_COMMAND="make kernel"
        ;;
    aurora)
        OUT="build/tether-aurora-bundle.tar.gz"
        STAGE="build/tether-aurora"
        BOOT="build/linux-aurora-out/arch/arm64/boot"
        BUILD_COMMAND="make kernel-aurora"
        ;;
    aurora-gpu|aurora-gpu-simpledrm)
        GPU_TRIAL=1
        OUT="build/tether-$KERNEL_FLAVOR-bundle.tar.gz"
        STAGE="build/tether-$KERNEL_FLAVOR"
        BOOT="build/linux-aurora-gpu-out/arch/arm64/boot"
        BUILD_COMMAND="make kernel-$KERNEL_FLAVOR"
        GPU_SUFFIX=""
        DISPLAY_SCOPE="Linux DCP handoff enabled; GPU+DCP coexistence is not yet qualified."
        if [ "$KERNEL_FLAVOR" = aurora-gpu-simpledrm ]; then
            GPU_SUFFIX="-simpledrm"
            DISPLAY_SCOPE="Linux DCP handoff disabled; inherited simpledrm scanout is retained."
        fi
        DT_NAME="t6050-$BOARD-gpu$GPU_SUFFIX.dtb"
        CHAIN="${M1N1_CHAIN:-build/m1n1-chain-gpu$GPU_SUFFIX.bin}"
        M1N1="${M1N1:-build/m1n1-gpu$GPU_SUFFIX}"
        ;;
    *) die "unknown KERNEL_FLAVOR=$KERNEL_FLAVOR (use asahi, aurora, aurora-gpu or aurora-gpu-simpledrm)" ;;
esac
M1N1="${M1N1:-vendor/m1n1}"
DTB="$BOOT/dts/apple/$DT_NAME"
KERNEL="$BOOT/Image.gz"

[ -d "$M1N1/proxyclient" ]      || die "$M1N1/proxyclient missing; prepare the selected loader source"
[ -f "$KERNEL" ]               || die "$KERNEL missing - run: $BUILD_COMMAND"
[ -f "$DTB" ]                  || die "$DTB missing - run: $BUILD_COMMAND"
[ -f build/initramfs.cpio.gz ] || die "initramfs missing - run: make initramfs"
[ -f "$CHAIN" ]               || die "$CHAIN missing; build and stage the selected chainloadable loader first"

echo "==> Staging $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/boot"

# proxyclient is pure python; ship it verbatim so the host needs no clone
cp -R "$M1N1/proxyclient" "$STAGE/proxyclient"
find "$STAGE/proxyclient" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
cp "$M1N1/udev/80-m1n1.rules" "$STAGE/"

# Live-hardware probes (guarded sysreg/MMIO from the m1n1 proxy) and the
# PMGR tree they check; they find proxyclient/ as their sibling.
mkdir -p "$STAGE/hv"
cp scripts/probes/*.py dt/t6050-pmgr.dtsi "$STAGE/hv/"

cp "$KERNEL"                 "$STAGE/boot/Image.gz"
cp "$DTB"                    "$STAGE/boot/$DT_NAME"
cp build/initramfs.cpio.gz   "$STAGE/boot/"
cp "$CHAIN"                 "$STAGE/boot/m1n1-chain.bin"
if [ "$KERNEL_FLAVOR" = asahi ] && [ -f build/m1n1-chain-payload.bin ]; then
    cp build/m1n1-chain-payload.bin "$STAGE/boot/"
fi

# On this DT boot, earlycon=efifb needs patch 0001's marker-enabled screen_info
# and framebuffer geometry verified for this boot. Normal marker-disabled
# builds reject earlycon; visible console output starts via simpledrm/fbcon.
# pd_ignore_unused: T6050 SErrors when genpd powers off unclaimed domains
# (patch 0004 makes sync_state honour it). See mkpayload.sh for the rest.
# m5.root: switch_root to Arch on disk0s5 (scripts/provision-rootfs.sh); /init
# stays in the initramfs shell if it does not mount.
# arm64.nowfxt: M5 cores lose state in WFIT/WFET (patch 0009). WFI loses it
# too on every core but the boot CPU; patch 0012 saves it, so idle=nop is
# gone. kvm-arm.wfi_trap_policy=trap keeps a guest's WFI off the bare core.
# All 15 cores start once the stub runs mBoot >= 20457.60 (macOS 27.3
# beta 1); on older stub firmware add maxcpus=1.
BOOTARGS="earlycon=efifb keep_bootcon console=tty0 loglevel=8 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0 arm64.nowfxt kvm-arm.wfi_trap_policy=trap m5.root=/dev/nvme0n1p5"
GPU_PREFLIGHT=""
if [ "$GPU_TRIAL" = 1 ]; then
    GPU_PREFLIGHT="python3 hv/gpu-preflight.py"
fi

cat > "$STAGE/boot-linux.sh" <<EOF
#!/bin/sh
# Boot the M5's kernel over the m1n1 proxy without changing the installed
# boot object. The default cmdline mounts the existing SSD root read-write.
# A failed boot may need a power-cycle back into m1n1.
set -e
cd "\${0%/*}"
: "\${M1N1DEVICE:=/dev/m1n1}"
export M1N1DEVICE
if [ ! -e "\$M1N1DEVICE" ]; then
    echo "\$M1N1DEVICE is gone: the Mac is not sitting in the m1n1 proxy." >&2
    echo "This must run BEFORE ./boot-linux.sh - once Linux is entered the" >&2
    echo "USB gadget disappears. Power-cycle into m1n1, ./chainload.sh, then" >&2
    echo "re-run this." >&2
    exit 1
fi
$GPU_PREFLIGHT
exec ./proxyclient/tools/linux.py \\
    boot/Image.gz \\
    boot/$DT_NAME \\
    "\${INITRAMFS:-boot/initramfs.cpio.gz}" \\
    -b "\${BOOTARGS:-$BOOTARGS}" "\$@"
EOF

cat > "$STAGE/chainload.sh" <<'EOF'
#!/bin/sh
# Load a new m1n1 into RAM and jump to it (for iterating on m1n1 itself).
# Default target is the CHAINLOADING=1 build shipped in this bundle.
set -e
cd "${0%/*}"
: "${M1N1DEVICE:=/dev/m1n1}"
export M1N1DEVICE
if [ ! -e "$M1N1DEVICE" ]; then
    echo "$M1N1DEVICE is gone: the Mac is not sitting in the m1n1 proxy." >&2
    echo "Power-cycle into m1n1 (power-hold -> picker -> Omarchy), run" >&2
    echo "./chainload.sh, then re-run this before booting Linux." >&2
    exit 1
fi
exec ./proxyclient/tools/chainload.py -r "${1:-boot/m1n1-chain.bin}"
EOF

cat > "$STAGE/dump-adt.sh" <<'EOF'
#!/bin/sh
# Dump the *runtime* ADT that iBoot handed m1n1.
#
# This is not the same tree as the on-disk devicetree.img4: iBoot patches
# it before handing it over (different size, different properties), so
# offline analysis of the firmware file can be actively misleading.
# Send adt-runtime.bin back to the build host.
set -e
cd "${0%/*}"
: "${M1N1DEVICE:=/dev/m1n1}"
export M1N1DEVICE
if [ ! -e "$M1N1DEVICE" ]; then
    echo "$M1N1DEVICE is gone: the Mac is not sitting in the m1n1 proxy." >&2
    echo "Power-cycle into m1n1 (power-hold -> picker -> Omarchy), run" >&2
    echo "./chainload.sh, then re-run this before booting Linux." >&2
    exit 1
fi
exec ./proxyclient/tools/dump_adt.py "${1:-adt-runtime.bin}"
EOF

cat > "$STAGE/proxyclient/tools/dump_adt.py" <<'EOF'
#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
import sys, pathlib
sys.path.append(str(pathlib.Path(__file__).resolve().parents[1]))

out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "adt-runtime.bin")

from m1n1.setup import *

data = u.get_adt()
out.write_bytes(data)
print(f"Wrote {len(data)} bytes to {out}")
EOF
chmod +x "$STAGE/proxyclient/tools/dump_adt.py" "$STAGE/dump-adt.sh"

cat > "$STAGE/dump-fdt.sh" <<EOF
#!/bin/sh
# Dump the *final, patched* FDT m1n1 hands to Linux.
#
# Not the input DTB and not the Apple ADT: this is the tree after every
# m1n1 fixup (CPU pruning, framebuffer node, initrd, bootargs, memory
# map). It does everything boot-linux.sh does EXCEPT the jump, so the
# machine stays in the proxy afterwards.
set -e
cd "\${0%/*}"
: "\${M1N1DEVICE:=/dev/m1n1}"
export M1N1DEVICE
if [ ! -e "\$M1N1DEVICE" ]; then
    echo "\$M1N1DEVICE is gone: the Mac is not sitting in the m1n1 proxy." >&2
    echo "This must run BEFORE ./boot-linux.sh - once Linux is entered the" >&2
    echo "USB gadget disappears. Power-cycle into m1n1, ./chainload.sh, then" >&2
    echo "re-run this." >&2
    exit 1
fi
exec ./proxyclient/tools/dump_fdt.py \\
    boot/$DT_NAME boot/initramfs.cpio.gz \\
    "\${BOOTARGS:-$BOOTARGS}" "\${1:-fdt-final.dtb}"
EOF

cat > "$STAGE/proxyclient/tools/dump_fdt.py" <<'EOF'
#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Dump the FDT m1n1 prepares for Linux, without booting it."""
import sys, pathlib, struct
sys.path.append(str(pathlib.Path(__file__).resolve().parents[1]))

dtb_path = pathlib.Path(sys.argv[1])
initramfs_path = pathlib.Path(sys.argv[2])
bootargs = sys.argv[3]
out = pathlib.Path(sys.argv[4] if len(sys.argv) > 4 else "fdt-final.dtb")

from m1n1.setup import *

dtb = dtb_path.read_bytes()
initramfs = initramfs_path.read_bytes()

# Mirror linux.py's setup so the fixups match a real boot exactly.
print(f'Setting boot args: "{bootargs}"')
p.kboot_set_chosen("bootargs", bootargs)

dtb_addr = u.malloc(len(dtb))
print(f"Loading DTB to 0x{dtb_addr:x}...")
iface.writemem(dtb_addr, dtb)

initramfs_base = u.memalign(65536, len(initramfs))
print(f"Loading {len(initramfs)} initramfs bytes to 0x{initramfs_base:x}...")
iface.writemem(initramfs_base, initramfs, True)
p.kboot_set_initrd(initramfs_base, len(initramfs))

if p.kboot_prepare_dt(dtb_addr):
    print("DT prepare failed")
    sys.exit(1)

fdt_addr = p.kboot_get_dt()
header = iface.readmem(fdt_addr, 8)
magic, totalsize = struct.unpack(">II", header)
if magic != 0xD00DFEED:
    sys.exit(f"Bad FDT magic 0x{magic:08x} at 0x{fdt_addr:x}")

data = iface.readmem(fdt_addr, totalsize)
out.write_bytes(data)
print(f"Wrote {totalsize} bytes of prepared FDT from 0x{fdt_addr:x} to {out}")
print("The machine is still in the proxy; nothing was booted.")
EOF
chmod +x "$STAGE/proxyclient/tools/dump_fdt.py" "$STAGE/dump-fdt.sh"

# Linux as a guest of the m1n1 hypervisor: the kernel console comes back
# over USB (/dev/m1n1-sec) and survives into userspace, and the host keeps
# a debugger. The guest is m1n1 + payloads, booted --raw at 0x800. Needs
# the patched m1n1 running (./chainload.sh): stock m1n1's hypervisor dies
# on T6050's locked VM_TMR_FIQ_ENA_EL2 (patches/m1n1/0002).
HV_BOOTARGS="maxcpus=1 earlycon console=tty0 console=ttySAC0 loglevel=8 pd_ignore_unused clk_ignore_unused no_console_suspend"
cat > "$STAGE/boot-hv.sh" <<EOF
#!/bin/sh
# Boot Linux under the m1n1 hypervisor. Run ./chainload.sh first, and keep a
# reader on the guest console: hv/vuart-log.py (logs to hv/vuart.log) or
# picocom /dev/m1n1-sec. Ctrl+C here drops into the hypervisor shell.
set -e
cd "\${0%/*}"
: "\${M1N1DEVICE:=/dev/m1n1}"
export M1N1DEVICE
if [ ! -e "\$M1N1DEVICE" ]; then
    echo "\$M1N1DEVICE is gone: the Mac is not sitting in the m1n1 proxy." >&2
    exit 1
fi
{
    cat boot/m1n1-chain.bin
    printf 'chosen.bootargs=%s\n' "\${BOOTARGS:-$HV_BOOTARGS}"
    cat boot/Image.gz boot/$DT_NAME boot/initramfs.cpio.gz
} > hv/guest-payload.bin
exec ./proxyclient/tools/run_guest.py -l hv/hv.log --raw hv/guest-payload.bin "\$@"
EOF

# The whole cycle after `systemctl reboot` (watchdog reset into m1n1) or a
# power cycle: wait for the proxy, chainload, put ANS in the state Linux's
# NVMe driver handles (hv/nvme-proxy-probe.py), boot, wait for SSH.
cat > "$STAGE/boot-m5.sh" <<'EOF'
#!/bin/sh
# Boot the M5 into Arch on the SSD: ./boot-m5.sh [extra boot-linux.sh args]
set -e
cd "${0%/*}"
: "${M1N1DEVICE:=/dev/m1n1}"
i=0
until [ -e "$M1N1DEVICE" ]; do
    i=$((i + 1)); [ $i -gt 90 ] && { echo "no $M1N1DEVICE after 3 min: power-cycle the Mac into m1n1" >&2; exit 1; }
    sleep 2
done
./chainload.sh
python3 hv/nvme-proxy-probe.py
EOF
if [ "$GPU_TRIAL" = 1 ]; then
    printf '%s\n' 'python3 hv/wdt-arm.py 120' >> "$STAGE/boot-m5.sh"
fi
cat >> "$STAGE/boot-m5.sh" <<'EOF'
./boot-linux.sh "$@" || true    # pyserial raises when the proxy vanishes at handoff
# The M5 answers on 10.55.<n>.2, n = the M5 port the cable is in (UDC 0
# left-back, 1 left-front, 2 right); subnets without a link fail at once.
echo "waiting for ssh bay@10.55.<port>.2 ..."
i=0
while :; do
    for n in 0 1 2; do
        if ssh -o ConnectTimeout=3 -o BatchMode=yes bay@10.55.$n.2 true 2>/dev/null; then
            echo "M5 is up: ssh bay@10.55.$n.2"; exit 0
        fi
    done
    i=$((i + 1)); [ $i -gt 40 ] && { echo "no SSH after ~3 min; check the panel" >&2; exit 1; }
    sleep 3
done
EOF

chmod +x "$STAGE/boot-linux.sh" "$STAGE/chainload.sh" "$STAGE/boot-hv.sh" "$STAGE/boot-m5.sh"

if [ "$GPU_TRIAL" = 1 ]; then
    FEATURE_SCOPE="This is the isolated J714s GPU trial, with Rust/Asahi and a GPU DT.
It is not a replacement for the verified battery/DCP or default bundles.
GPU initialization alone is not proof of rendering; use the isolated Mesa
userspace and verify real work and visible output before calling it qualified.
The GPU boot-linux.sh reads the live ADT and rejects different firmware
metadata or voltage bins before invoking Linux; it does not import m1n1.setup.
Display profile: $DISPLAY_SCOPE"
else
    FEATURE_SCOPE="The default kernel is the simpledrm fallback. Aurora adds the internal
DCP display driver, brightness control and display off/on. Neither of these
two baseline flavors provides GPU acceleration."
fi
WATCHDOG_STEP=""
if [ "$GPU_TRIAL" = 1 ]; then
    WATCHDOG_STEP="    python3 hv/wdt-arm.py 120"
fi

cat > "$STAGE/README.md" <<EOF
# omarchy-m5 tether bundle

Drives a MacBook Pro M5 Pro (J714s / T6050) sitting in m1n1 proxy mode
from this Linux host over USB-C.

Kernel variant: \`$KERNEL_FLAVOR\`. Kernel and DTB are from \`$BOOT\`;
the chainloadable m1n1 is from \`$CHAIN\`. No installed boot object is changed.
The default cmdline boots the existing internal SSD root, read-write.

## Host setup (Arch)

    sudo pacman -S --needed python python-pyserial python-construct
    sudo cp 80-m1n1.rules /etc/udev/rules.d/
    sudo udevadm control --reload

The rule matches m1n1's USB gadget (1209:316d) and creates:

  * \`/dev/m1n1\`     - proxy channel (what the tools talk to)
  * \`/dev/m1n1-sec\` - m1n1's own console output

Your user needs read/write on those: \`sudo usermod -aG uucp \$USER\`,
then re-login. Without the udev rule, pass \`M1N1DEVICE=/dev/ttyACM0\`.

## Boot Linux (the normal loop)

    ./chainload.sh
    python3 hv/nvme-proxy-probe.py
$WATCHDOG_STEP
    ./boot-linux.sh

Override the cmdline without repacking:

    BOOTARGS="... initcall_debug" ./boot-linux.sh   # start from the default in boot-linux.sh

The console uses \`console=tty0\` on the Mac's panel: simpledrm on the
default and aurora-gpu-simpledrm profiles, Apple DCP on the other Aurora
profiles. Early marker bands are disabled in normal builds. The m1n1 USB serial device disappears at Linux
handoff; reconnect over the USB network. If pyserial reports a non-TTY
miniterm error after "Preparing to boot kernel", check the panel/network
before trying another load. m1n1's own output uses \`/dev/m1n1-sec\`.

For the Aurora DCP fallback, append \`nomodeset\` to the full default
cmdline via \`BOOTARGS\`: simpledrm will keep the display. Firmware tables
are build-specific; the tested stub is mBoot-20457.60.65.0.1 (27.3 beta 1).

## Boot Linux under the hypervisor (console over USB)

This optional hypervisor path has not been qualified for the Aurora/DCP
kernel; use the normal tethered loop above for that variant.

    ./chainload.sh                 # the patched m1n1 hosts the hypervisor
    hv/vuart-log.py /dev/m1n1-sec hv/vuart.log &   # or: picocom /dev/m1n1-sec
    ./boot-hv.sh

The guest's \`console=ttySAC0\` is the hypervisor's virtual UART, so the
kernel log and the \`/init\` shell are on \`/dev/m1n1-sec\` - interactive,
and still there after Linux takes over. Ctrl+C in \`boot-hv.sh\` gives the
hypervisor shell (registers, memory, MMIO tracing). The guest runs at EL1,
single core.

## Iterate on m1n1 itself

    ./chainload.sh                     # the bundled CHAINLOADING=1 build

Only the default bundle may also contain \`boot/m1n1-chain-payload.bin\`,
an optional prebuilt m1n1 + kernel + DT + initramfs payload. It is not
included in the Aurora bundle.

After \`chainload.sh\` the new m1n1 re-enumerates its USB gadget and drops
back into proxy mode, so run \`./boot-linux.sh\` again afterwards.

## Hardware baseline

With stub firmware mBoot-20457.60.65.0.1, all 15 usable CPUs start. Keep
\`arm64.nowfxt kvm-arm.wfi_trap_policy=trap\`; the kernel saves registers
around WFI, so \`idle=nop\` is no longer needed. The three fused-off CPU
slots are not failed starts. Only older stub firmware needs \`maxcpus=1\`.

$FEATURE_SCOPE
See the repository's docs/bringup.md for the verified feature scope and
experimental-kernel limitations.

## Dumping the final FDT

    ./dump-fdt.sh          # -> fdt-final.dtb, send it to the build host

This is the tree **after** every m1n1 fixup (CPU pruning, framebuffer node,
initrd, bootargs, memory map) - not the input DTB and not the ADT. It does
everything \`boot-linux.sh\` does except the jump, so the machine stays in
the proxy and you can run it back to back with a boot attempt.

## Dumping the runtime ADT

    ./dump-adt.sh          # -> adt-runtime.bin, send it to the build host

The runtime tree is **not** the on-disk \`devicetree.img4\`: iBoot patches
it first (737280 bytes at runtime vs 835984 on disk), and the two disagree
about this very DART. Analyze only the runtime dump.

## Checking the boot

Look for 14 secondary CPUs reporting \`Started.\`, then a login console.
Over SSH, check \`cat /sys/devices/system/cpu/online\` (0-14),
\`findmnt /\` (the SSD root), and \`cat /sys/class/graphics/fb0/name\`.
The Aurora DCP console reports \`appledrmfb\`; fallback reports
\`simpledrmdrmfb\`. A failed root mount leaves the diagnostic initramfs
shell rather than booting the SSD.
EOF

echo "==> Packing $OUT"
tar -czf "$OUT" -C "${STAGE%/*}" "${STAGE##*/}"
rm -rf "$STAGE"

ls -lh "$OUT"
echo
echo "Copy to the ThinkPad:"
echo "  scp $OUT <host>:"
echo "  ssh <host> 'tar xzf ${OUT##*/} && cat ${STAGE##*/}/README.md'"
