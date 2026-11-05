#!/bin/bash
# gz3-firstboot.sh: on "work", the moment gz3's USB gadget appears. Read-only on the Mac:
# network up, ssh, collect facts + logs, install-rootfs --dry-run (guards only, writes nothing).
# Usage: tools/gz3-firstboot.sh [--wait SECONDS]   (default 900)   Logs: build/firstboot/gz3-<time>/
set -u
cd "$(dirname "$0")/.."
WAIT=900; [ "${1:-}" = --wait ] && WAIT=$2
OUT=build/firstboot/gz3-$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"
# dropbear makes a fresh host key each boot; pin it per session in a private known_hosts (point-to-point USB link)
SSH=(ssh -o UserKnownHostsFile="$OUT/known_hosts" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 root@10.55.0.2)

tools/host-usbnet.sh --wait "$WAIT" 2>&1 | tee "$OUT/usbnet.txt" || exit 1
for i in $(seq 30); do "${SSH[@]}" true 2>/dev/null && break; sleep 2; done
run() { echo "### $1"; "${SSH[@]}" "$1" 2>&1; echo; }
{
  run 'uname -a; cat /proc/cmdline'
  run 'grep -c ^processor /proc/cpuinfo; cat /sys/class/tty/console/active'
  run 'cat /proc/device-tree/compatible | tr "\0" " "'
  run 'ls /sys/class/drm /sys/class/graphics 2>&1; cat /sys/class/graphics/fb0/virtual_size 2>&1'
  run 'cat /proc/partitions; sfdisk -l /dev/nvme0n1 2>&1 | head -30'
  run 'ip -br addr'
} | tee "$OUT/facts.txt"
"${SSH[@]}" dmesg > "$OUT/dmesg.txt" 2>&1
echo "### install-rootfs --dry-run" | tee "$OUT/dryrun.txt"
"${SSH[@]}" 'sh /bin/install-rootfs.sh --dry-run' 2>&1 | tee -a "$OUT/dryrun.txt"; rc=${PIPESTATUS[0]}
echo; echo "logs: $OUT   dry-run exit: $rc"
echo "dmesg warnings:"; grep -iE 'error|fail|panic|oops|timed out|SError' "$OUT/dmesg.txt" | head -20
echo
echo "NOT run (needs PM go): zstd -dc build/rootfs-alarm.tar.zst | ${SSH[*]} 'sh /bin/install-rootfs.sh --yes'"
