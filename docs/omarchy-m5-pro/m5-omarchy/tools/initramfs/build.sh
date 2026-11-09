#!/bin/bash
# build.sh — build build/initramfs.cpio.gz (first boot) and build/initramfs-loader.cpio.gz (+ kexec-tools).
# Inputs: verified Alpine v3.24 aarch64 apks in build/dl/alpine/pkgs (see reports/07), build/work.pub,
# tools/t6050-probe/t6050_probe.ko. Uses the kernel's own gen_init_cpio, so files are root-owned without fakeroot.
set -euo pipefail
R=$(cd "$(dirname "$0")/../.." && pwd)
P=$R/build/dl/alpine/pkgs
GEN=$R/build/linux/usr/gen_init_cpio
T=$R/tools/initramfs

extract() {  # extract an apk's data stream (3rd gzip member) into $1, data-only tar filter
  python3 -I - "$1" "$2" <<'EOF'
import io, sys, tarfile, zlib
dest, apk = sys.argv[1], sys.argv[2]
blob, pos, members = open(apk, "rb").read(), 0, []
while pos < len(blob):
    d = zlib.decompressobj(16 + zlib.MAX_WBITS); d.decompress(blob[pos:])
    end = len(blob) - len(d.unused_data); members.append(blob[pos:end]); pos = end
if len(members) != 3: sys.exit(f"unexpected apk layout {apk}")
data = zlib.decompress(members[2], 16 + zlib.MAX_WBITS)
with tarfile.open(fileobj=io.BytesIO(data), mode="r:") as t:
    t.extractall(dest, filter="data")
EOF
}

build() {  # build NAME PKG...
  local name=$1; shift
  local S=$R/build/initramfs-root-$name; rm -rf "$S"; mkdir -p "$S"
  for p in "$@"; do extract "$S" "$(ls "$P"/$p-[0-9]*.apk)"; done
  # keep only what we run: busybox, dropbear (+libs), kexec (+libs); drop docs/aux
  rm -rf "$S"/usr/share "$S"/etc/conf.d "$S"/etc/init.d "$S"/usr/bin/dbclient "$S"/usr/bin/dropbearkey \
         "$S"/usr/bin/dropbearconvert "$S"/usr/sbin/vmcore-dmesg "$S"/usr/lib/libz.so.1.* 2>/dev/null || true
  rm -rf "$S"/usr/lib/libz.so.1.* ; extract "$S" "$(ls "$P"/zlib-[0-9]*.apk)"; rm -rf "$S"/usr/share
  mkdir -p "$S"/bin "$S"/sbin "$S"/etc "$S"/root/.ssh "$S"/lib/modules "$S"/proc "$S"/sys "$S"/dev "$S"/tmp "$S"/run "$S"/mnt
  mv "$S"/bin/busybox.static "$S"/bin/busybox
  install -m 0755 "$T"/init "$S"/init
  install -m 0755 "$T"/m5-gadget-net "$T"/m5-sshd "$T"/m5-loader "$T"/m5-esplog "$T"/m5-root "$S"/bin/
  install -m 0755 "$R"/tools/install-rootfs.sh "$S"/bin/install-rootfs.sh
  install -m 0600 "$R"/build/work.pub "$S"/root/.ssh/authorized_keys
  install -m 0644 "$R"/tools/t6050-probe/t6050_probe.ko "$S"/lib/modules/
  # task 28: MTP trackpad firmware (Apple's, extracted from the 26.6.2 IPSW by betizzel's extract-tpmtfw.py; local use only)
  [ -f "$R"/build/firmware/apple/tpmtfw-j714s.bin ] && install -D -m 0644 "$R"/build/firmware/apple/tpmtfw-j714s.bin "$S"/lib/firmware/apple/tpmtfw-j714s.bin
  printf 'root:x:0:0:root:/root:/bin/sh\n' > "$S"/etc/passwd
  printf 'root:x:0:\n' > "$S"/etc/group
  printf '/bin/sh\n' > "$S"/etc/shells
  # slim (task 17): first-boot only, for the slim kernel; no fsck, no econftool
  [ "$name" = slim ] && rm -f "$S"/sbin/e2fsck "$S"/sbin/fsck.ext* "$S"/usr/bin/econftool
  # cpio list: everything root-owned, plus a console node for early /init output
  local L=$R/build/initramfs-$name.list
  { (cd "$S" && find . -mindepth 1 | sort) | while read -r f; do
      p=${f#.}; s="$S$p"
      if [ -L "$s" ]; then echo "slink $p $(readlink "$s") 0777 0 0"
      elif [ -d "$s" ]; then echo "dir $p $(stat -c %a "$s") 0 0"
      else echo "file $p $s $(stat -c %a "$s") 0 0"; fi
    done; echo "nod /dev/console 0600 0 0 c 5 1"; } > "$L"
  "$GEN" "$L" | gzip -9n > "$R/build/initramfs$([ "$name" = base ] || echo -$name).cpio.gz"
}

DISK="e2fsprogs e2fsprogs-libs libcom_err sfdisk libfdisk libsmartcols libblkid libuuid libeconf libncursesw"
[ -n "$M5_SLIM" ] || build base   busybox-static dropbear utmps-libs skalibs-libs musl $DISK
[ -n "$M5_SLIM" ] || build loader busybox-static dropbear utmps-libs skalibs-libs musl kexec-tools xz-libs zstd-libs $DISK
[ -n "$M5_SLIM" ] && build slim busybox-static dropbear utmps-libs skalibs-libs musl $DISK
cd "$R/build" && sha256sum initramfs*.cpio.gz | tee initramfs.SHA256SUMS
