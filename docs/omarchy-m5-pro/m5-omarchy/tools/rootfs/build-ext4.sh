#!/bin/sh
# build-ext4.sh (task 27): build/rootfs-omarchy.tar.zst -> overlay (m5-desktop-overlay.sh) -> build/rootfs-omarchy.ext4(.zst)
# ext4, 4 KiB blocks, label "omarchy", size = content + 4 GiB slack + 1 GiB for metadata; grows on first boot.
# Rootless: unshare --map-root-user --map-auto keeps owners; bsdtar keeps file capabilities (GNU tar drops them).
set -eu
R=$(cd "$(dirname "$0")/../.." && pwd); cd "$R"
W=build/t27/root; IMG=build/rootfs-omarchy.ext4
unshare --map-root-user --map-auto --mount --pid --fork sh -euc "
  rm -rf $W && mkdir -p $W
  zstd -dc -T0 build/rootfs-omarchy.tar.zst | bsdtar -xp --numeric-owner --xattrs --acls -C $W -f -
  tools/rootfs/m5-desktop-overlay.sh $W
  B=\$(du -s -B1 $W | cut -f1); S=\$(( (B + 4*1024*1024*1024) / 4096 * 4096 + 1024*1024*1024 ))
  rm -f $IMG; truncate -s \$S $IMG
  mke2fs -q -t ext4 -b 4096 -L omarchy -U random -E lazy_itable_init=0 -d $W $IMG"
e2fsck -fn $IMG
zstd -T0 -10 -q -f $IMG -o $IMG.zst
sha256sum $IMG $IMG.zst
