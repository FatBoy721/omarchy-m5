#!/usr/bin/env python3
"""Build the M5's root filesystem image on the host, no root needed.

Arch Linux ARM's generic aarch64 tarball, minus what our kernel never uses
(linux-aarch64: /boot, modules; linux-firmware*: ~1 GB), plus the bring-up
config, written as a tar and turned into ext4 by `mke2fs -d <tarball>`
(e2fsprogs >= 1.47.1 reads tarballs through libarchive, taking uid/gid/mode/
xattrs from the headers, so the result is right without fakeroot/sudo).

  scripts/mkrootfs-image.py                       # -> build/rootfs/m5root.img.gz

The image is small (2 GiB, mostly empty); fstab's x-systemd.growfs grows the
filesystem to the whole partition on the first boot. Flash it with
provision-rootfs.sh on the M5 (guarded: only nvme0n1p5 with the expected
geometry).
"""
import argparse, glob, gzip, io, os, pathlib, shutil, subprocess, sys, tarfile, time

ALARM_URL = "http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
DROP_PKGS = ("linux-aarch64-", "linux-firmware")   # pacman local db dir prefixes
DROP_TREES = ("boot/", "usr/lib/firmware/", "usr/lib/modules/")

FILES = {
    "etc/hostname": "m5pro\n",
    # growfs: the image is 2 GiB; the first boot grows it to the partition.
    "etc/fstab": "LABEL=m5root / ext4 noatime,x-systemd.growfs 0 1\n",
    # usb-gadget-net.sh (initramfs) gives the gadget on UDC n (M5 port) the
    # EEM netdev usb<n>; the ThinkPad side is scripts/host-usbnet.sh
    # (10.55.<n>.1, NAT). One file per port, so any port gets a route.
    # The tether is only a fallback default route: the host forwards nothing
    # unless host-usbnet.sh runs, so Wi-Fi (NetworkManager metric 600) and
    # Ethernet have to outrank it.
    **{f"etc/systemd/network/10-usb-gadget-{n}.network": f"""[Match]
Name=usb{n}

[Network]
Address=10.55.{n}.2/24
DNS=1.1.1.1

[Route]
Gateway=10.55.{n}.1
Metric=2048
""" for n in range(3)},
    # iBoot counts every boot the OS does not acknowledge in the PMU's
    # scratchpad and, after a few in a row, stops starting the OS ("needs to be
    # reinstalled"). The m1n1 proxy tools zero the count, but only with the
    # cable attached, and macsmc-reboot is not loaded here (it would take
    # restart over from the watchdog). One watchdog restart was measured to
    # add one boot error; this clears the byte once the system is up.
    "usr/local/sbin/omarchy-m5-boot-ok": """#!/bin/sh
# Acknowledge this boot to iBoot: zero the PMU's boot-error/panic byte.
set -eu
for cell in /sys/bus/nvmem/devices/*/cells/boot-error-count@*; do
    [ -e "$cell" ] || exit 0
    at=${cell##*@}
    offset=$((0x${at%%,*}))     # boot-error-count@f802,0 -> 0xf802
    nvmem=${cell%/cells/*}/nvmem
    was=$(od -An -tx1 -j "$offset" -N 1 "$nvmem" | tr -d ' ')
    # One byte: boot errors in the low nibble, panics in the high one.
    printf '\\0' | dd of="$nvmem" bs=1 seek="$offset" conv=notrunc status=none
    echo "boot acknowledged (the PMU's boot-error/panic byte was 0x$was)"
done
""",
    "etc/systemd/system/omarchy-m5-boot-ok.service": """[Unit]
Description=Acknowledge a successful boot to iBoot (clear the PMU boot-error count)
ConditionPathExistsGlob=/sys/bus/nvmem/devices/*/cells/boot-error-count@*

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/omarchy-m5-boot-ok

[Install]
WantedBy=multi-user.target
""",
}
SYMLINKS = {
    "etc/systemd/system/multi-user.target.wants/omarchy-m5-boot-ok.service":
        "../omarchy-m5-boot-ok.service",
}


def is_pkg_db(path):
    p = path.split("/")
    return (len(p) >= 4 and p[:3] == ["var", "lib", "pacman"] and p[3] == "local"
            and len(p) >= 5 and p[4].startswith(DROP_PKGS) and not p[4].startswith("linux-api-headers"))


def dropped_files(src):
    """Paths owned by the dropped packages, from their pacman db 'files'."""
    owned = set()
    with tarfile.open(src) as tf:
        for m in tf:
            name = m.name.removeprefix("./")
            if is_pkg_db(name) and name.endswith("/files"):
                sect = None
                for line in tf.extractfile(m).read().decode().splitlines():
                    if line.startswith("%"):
                        sect = line
                    elif sect == "%FILES%" and line and not line.endswith("/"):
                        owned.add(line)
    return owned


def info(name, data=None, mode=0o644, link=None):
    ti = tarfile.TarInfo(name)
    ti.uid = ti.gid = 0
    ti.uname = ti.gname = "root"
    ti.mtime = int(time.time())
    if link is not None:
        ti.type, ti.linkname, ti.mode = tarfile.SYMTYPE, link, 0o777
    else:
        ti.mode, ti.size = mode, len(data)
    return ti


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tarball", default="build/cache/ArchLinuxARM-aarch64-latest.tar.gz")
    ap.add_argument("--keys", default=None, help="authorized_keys for root (default: ~/.ssh/*.pub)")
    ap.add_argument("--firmware", default="build/firmware",
                    help="tree installed as /usr/lib/firmware (apple/tpmtfw-j714s.bin: the "
                         "trackpad driver loads it on every open, i.e. after switch_root too)")
    ap.add_argument("--size", default="2G", help="image size (grown on first boot)")
    ap.add_argument("--out", default="build/rootfs/m5root.img.gz")
    a = ap.parse_args()

    src = pathlib.Path(a.tarball)
    if not src.exists():
        sys.exit(f"{src} missing: curl -L -o {src} {ALARM_URL}  (check the .md5 next to it)")
    keys = (pathlib.Path(a.keys).read_bytes() if a.keys else
            b"".join(pathlib.Path(k).read_bytes() for k in sorted(glob.glob(os.path.expanduser("~/.ssh/*.pub")))))
    if not keys:
        sys.exit("no SSH public key (~/.ssh/*.pub or --keys)")

    out = pathlib.Path(a.out)
    work = out.parent
    work.mkdir(parents=True, exist_ok=True)
    tar_path, img_path = work / "m5root.tar", work / "m5root.img"

    print("==> scanning pacman db for", ", ".join(DROP_PKGS))
    owned = dropped_files(src)
    replaced = set(FILES) | set(SYMLINKS) | {"root/.ssh/authorized_keys"}
    kept = dropped = 0
    gone = set()
    print(f"==> repacking {src.name} (dropping {len(owned)} owned files + {', '.join(DROP_TREES)})")
    with tarfile.open(src) as tf, tarfile.open(tar_path, "w", format=tarfile.PAX_FORMAT) as tw:
        for m in tf:
            name = m.name.removeprefix("./").rstrip("/")
            if not name:
                continue
            drop = (is_pkg_db(name) or name in replaced
                    or (not m.isdir() and name in owned)
                    or any(name.startswith(t) for t in DROP_TREES)
                    or (m.islnk() and m.linkname.removeprefix("./") in gone))
            if drop:
                gone.add(name)
                dropped += 1
                continue
            m.name = name
            tw.addfile(m, tf.extractfile(m) if m.isreg() else None)
            kept += 1
        for name, text in FILES.items():
            data = text.encode()
            tw.addfile(info(name, data, 0o755 if text.startswith("#!") else 0o644), io.BytesIO(data))
        for name, target in SYMLINKS.items():
            tw.addfile(info(name, link=target))
        tw.addfile(info("root/.ssh/authorized_keys", keys, 0o600), io.BytesIO(keys))
        fw = pathlib.Path(a.firmware)
        for f in sorted(fw.rglob("*")) if fw.is_dir() else []:
            rel = "usr/lib/firmware/" + str(f.relative_to(fw))
            if f.is_dir():
                d = info(rel, b"", 0o755); d.type = tarfile.DIRTYPE; d.size = 0
                tw.addfile(d)
            else:
                data = f.read_bytes()
                tw.addfile(info(rel, data), io.BytesIO(data))
                print(f"    firmware: /{rel}")
    print(f"    kept {kept}, dropped {dropped}, tar {tar_path.stat().st_size / 1e6:.0f} MB")

    print(f"==> mke2fs -d -> {img_path} ({a.size})")
    img_path.unlink(missing_ok=True)
    subprocess.run(["mke2fs", "-q", "-F", "-t", "ext4", "-b", "4096", "-L", "m5root",
                    "-d", str(tar_path), str(img_path), a.size], check=True)
    subprocess.run(["e2fsck", "-fn", str(img_path)], check=True, stdout=subprocess.DEVNULL)

    print(f"==> gzip -> {out}")
    with open(img_path, "rb") as f, open(out, "wb") as raw, \
            gzip.GzipFile(fileobj=raw, mode="wb", compresslevel=6, mtime=0) as g:
        shutil.copyfileobj(f, g, 16 << 20)
    tar_path.unlink()       # m5root.img stays (sparse) for debugfs inspection
    print(f"    {out} {out.stat().st_size / 1e6:.0f} MB")


if __name__ == "__main__":
    main()
