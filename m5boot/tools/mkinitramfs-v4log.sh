#!/bin/sh
# Task 18: initramfs-slim-v4log = the listed slim-v3 initramfs-slim (unchanged bytes, verified by check-inputs)
# + an appended newc cpio overlay (initramfs-v4log/: /bin/m5-esplog v4). The kernel unpacks concatenated archives
# in order; a later file replaces the earlier one (Documentation/driver-api/early-userspace/buffer-format.rst).
# Usage: tools/mkinitramfs-v4log.sh BASE_INITRAMFS OUT
set -e
sh tools/check-inputs.sh "$1"
chmod 755 initramfs-v4log/bin/m5-esplog
ov=$(mktemp)
(cd initramfs-v4log && find . -mindepth 1 | LC_ALL=C sort | cpio -o -H newc --owner=0:0 --reproducible --quiet) | gzip -9n > "$ov"
cat "$1" "$ov" > "$2"
rm -f "$ov"
sha256sum "$2"; stat -c %s "$2"
