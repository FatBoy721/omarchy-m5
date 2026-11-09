#!/bin/bash
# build-omarchy.sh — bake the Omarchy userland (generic aarch64 platform) into our ALARM rootfs, offline.
# No root: everything runs inside an unprivileged user namespace (unshare --map-root-user --map-auto:
# uid 0 + this user's subuid range), aarch64 binaries run via the host's qemu-aarch64 binfmt (F flag).
# Recipe adapted from omacom/omarchy-mac-installer image-builder (MIT): omarchy-settings first, the root-owned
# image manifest (format=1, platform=generic-aarch64), the runtime packages, then
#   omarchy-apply-system --defer-provisioning --first-install
# Never installs m1n1 / Aurora / Asahi boot packages (IgnorePkg + final check).
# Input: build/rootfs-alarm.tar.zst. Output: build/rootfs-omarchy.tar.zst (+ .sha256), log in build/omarchy-build/.
set -euo pipefail
R=$(cd "$(dirname "$0")/../.." && pwd)
W=$R/build/omarchy-build; T=$W/root; L=$W/logs
OMARCHY_KEY=40DFB630FF42BCFFB047046CF0134EE680CAC571
# never installed: other kernels (ours stays) and every m1n1/Aurora/Asahi boot package (rule 7)
GUARD="linux-aarch64 linux-aarch64-headers linux linux-headers linux-aurora linux-aurora-headers m1n1 m1n1-aurora m1n1-neo aura uboot-asahi omarchy-mac omarchy-mac-boot omarchy-apple-boot asahi-* limine-mkinitcpio-hook"
OMARCHY_CHANNEL=${OMARCHY_CHANNEL:-stable}   # PM: prefer the signed stable channel
RUNTIME_COMMIT=${RUNTIME_COMMIT:-50bb5db319933569c9d5c3abc3a4485af943004b}   # omacom/omarchy quattro, for the package lists
STAGE=${1:-all}
mkdir -p "$W" "$L"

if [ "${M5_IN_NS:-0}" != 1 ]; then
  # host side (unprivileged): fetch the Omarchy key + package lists, then re-exec inside the namespace
  [ -s "$W/omarchy-key.asc" ] || curl -sfL "https://keys.openpgp.org/vks/v1/by-fingerprint/$OMARCHY_KEY" -o "$W/omarchy-key.asc"
  for f in omarchy-base.packages omarchy-aarch64.packages; do
    [ -s "$W/$f" ] || gh api "repos/omacom/omarchy/contents/install/$f?ref=$RUNTIME_COMMIT" -q .content | base64 -d > "$W/$f"
  done
  mkdir -p "$W/seed"; I=omarchy-themes-intros-2026.10.14-1-any.pkg.tar.zst
  for x in "" .sig; do [ -s "$W/seed/$I$x" ] || curl -sfL -o "$W/seed/$I$x" "https://pkgs.omarchy.org/${OMARCHY_CHANNEL}/aarch64/$I$x"; done
  G=$(mktemp -d); GNUPGHOME=$G gpg -q --import "$W/omarchy-key.asc" 2>/dev/null
  GNUPGHOME=$G gpg --status-fd 1 --verify "$W/seed/$I.sig" "$W/seed/$I" 2>/dev/null | grep -q "VALIDSIG $OMARCHY_KEY" \
    || { echo "seed package signature invalid"; exit 1; }; rm -rf "$G"
  # ALARM's own mirrorlist, from the GPG-verified ALARM tarball (Omarchy 4.0.6 replaces it with its x86 mirror)
  [ -s "$W/alarm-mirrorlist" ] || bsdtar -xOf "$R/build/dl/alarm/ArchLinuxARM-aarch64-latest.tar.gz" ./etc/pacman.d/mirrorlist > "$W/alarm-mirrorlist"
  exec unshare --map-root-user --map-auto --mount --pid --fork env M5_IN_NS=1 "$0" "$@"
fi

# ---------- inside the namespace: we are "root" ----------
CH() {  # run a command in the aarch64 root with API filesystems
  chroot "$T" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/bin HOME=/root TERM=dumb LANG=C.UTF-8 \
    OMARCHY_PATH=/usr/share/omarchy "$@"
}
mount_api() {
  mount -t proc proc "$T/proc"; mount -t tmpfs nopci "$T/proc/bus/pci" 2>/dev/null || true  # hide host PCI (lspci)
  mount -t tmpfs sysfs-empty "$T/sys"   # never expose host hardware to the build
  # Omarchy 4.0.6 hardware scripts read DMI under bash -e and fail on a DMI-less (device-tree) machine. Give the
  # build the TARGET's true identity (our J714s dump: Mac17,9, Apple); no 4.0.6 script matches it (Intel-Mac regexes).
  mkdir -p "$T/sys/class/dmi/id"; echo "Mac17,9" > "$T/sys/class/dmi/id/product_name"; echo "Apple Inc." > "$T/sys/class/dmi/id/sys_vendor"
  mkdir -p "$T/sys/bus/pci/devices"   # lspci: an empty PCI bus (the J714s's real PCIe devices are unknown to the build); mount --rbind /dev "$T/dev"
  mount -t tmpfs tmpfs "$T/run"; mount -t tmpfs tmpfs "$T/tmp"
}
PAC=(pacman --noconfirm --disable-sandbox --color never)

if [ "$STAGE" = all ] || [ "$STAGE" = extract ]; then
  rm -rf "$T"; mkdir -p "$T"
  bsdtar -xpf "$R/build/rootfs-alarm.tar.zst" -C "$T"
fi
mount_api
rm -f "$T/etc/resolv.conf"; cp -L /etc/resolv.conf "$T/etc/resolv.conf"

if [ "$STAGE" = all ] || [ "$STAGE" = repo ]; then
  # guards first: our kernel stays; nothing m1n1/Aurora/Asahi-boot may ever be installed
  sed -i -E "s/^IgnorePkg *=.*/IgnorePkg = $GUARD/" "$T/etc/pacman.conf"
  grep -q '^\[omarchy\]' "$T/etc/pacman.conf" || \
    sed -i "s|^\\[core\\]|[omarchy]\\nServer = https://pkgs.omarchy.org/${OMARCHY_CHANNEL}/\\\$arch\\n\\n[core]|" "$T/etc/pacman.conf"
  sed -i 's/^CheckSpace/#CheckSpace  # m5-build: no mount table in the build chroot; restored at pack/' "$T/etc/pacman.conf"
  grep -q '^DisableSandbox' "$T/etc/pacman.conf" || sed -i 's/^\[options\]/[options]\n# m5-build: no Landlock under qemu-user; removed at pack\nDisableSandbox/' "$T/etc/pacman.conf"
  CH pacman-key --init >"$L/keys.log" 2>&1
  CH pacman-key --populate archlinuxarm >>"$L/keys.log" 2>&1
  cp "$W/omarchy-key.asc" "$T/root/omarchy-key.asc"
  CH pacman-key --add /root/omarchy-key.asc >>"$L/keys.log" 2>&1
  CH pacman-key --finger "$OMARCHY_KEY" | tee -a "$L/keys.log" | grep -q "$(echo $OMARCHY_KEY | sed 's/..../& /g; s/ $//; s/\(.\{24\}\) /\1  /')" \
    || { echo "Omarchy key fingerprint mismatch"; exit 1; }
  CH pacman-key --lsign-key "$OMARCHY_KEY" >>"$L/keys.log" 2>&1
  CH "${PAC[@]}" -Sy omarchy-keyring archlinuxarm-keyring >"$L/keyring.log" 2>&1
fi

if [ "$STAGE" = all ] || [ "$STAGE" = settings ]; then
  CH "${PAC[@]}" -Syu --needed omarchy-settings >"$L/settings.log" 2>&1
  install -d -m 0755 -o 0 -g 0 "$T/var/lib/omarchy/image"
  printf 'format=1\nplatform=generic-aarch64\nimage_profile=m5-j714s-lab\n' > "$T/var/lib/omarchy/image/target"
  chown 0:0 "$T/var/lib/omarchy/image/target"; chmod 0644 "$T/var/lib/omarchy/image/target"
fi

if [ "$STAGE" = all ] || [ "$STAGE" = runtime ]; then
  # omarchy-themes-intros: the [omarchy] db carries no embedded PGPSIG for it; its detached .sig (Omarchy key, EdDSA)
  # verifies (checked on the host, see report 13). Seed it + .sig into the cache so pacman verifies the detached .sig.
  sed -i 's/^ParallelDownloads.*/ParallelDownloads = 1/' "$T/etc/pacman.conf"
  for f in "$W"/seed/*.pkg.tar.*; do [ -e "$f" ] && cp "$f" "$T/var/cache/pacman/pkg/"; done
  # stable [omarchy] hyprland-0.56.2 needs libaquamarine.so=14 but ALARM ships aquamarine 0.16 (2026-11-04), so the
  # Hyprland stack comes from signed ALARM extra (hyprland 0.57.1 already contains hyprwm/Hyprland#16343, the
  # software-render detection omarchy-pkgs#649 backports). omarchy depends on unversioned "hyprland".
  CH "${PAC[@]}" -Syu --needed extra/hyprland >"$L/hyprland.log" 2>&1 || { echo "extra/hyprland install failed"; tail -20 "$L/hyprland.log"; exit 1; }
  grep -q '^IgnorePkg.* hyprland\( \|$\)' "$T/etc/pacman.conf" || sed -i 's/^IgnorePkg = .*/& hyprland/' "$T/etc/pacman.conf"   # keep ALARM hyprland (see above)
  # install the runtime first, then take the package lists from the runtime itself so lists and repo versions match
  CH "${PAC[@]}" -Syu --needed omarchy >"$L/runtime.log" 2>&1 || { echo "omarchy install failed"; tail -20 "$L/runtime.log"; exit 1; }
  # package lists from the installed runtime itself (base + aarch64 list when the runtime has one)
  CH bash -c 'cd /usr/share/omarchy/install && sed -e "s/#.*//" -e "/^[[:space:]]*$/d" omarchy-base.packages $(ls omarchy-aarch64.packages 2>/dev/null) | sort -u' > "$W/wanted-all.txt"
  CH pacman -Slq > "$W/available.txt"
  LC_ALL=C sort -u -o "$W/wanted-all.txt" "$W/wanted-all.txt"; LC_ALL=C sort -u -o "$W/available.txt" "$W/available.txt"
  grep -vx hyprland "$W/wanted-all.txt" | LC_ALL=C comm -12 - "$W/available.txt" > "$W/wanted.txt"        # hyprland: from ALARM (above)
  LC_ALL=C comm -23 "$W/wanted-all.txt" "$W/available.txt" | grep -vx hyprland > "$L/skipped-unavailable.txt" || true
  echo "wanted $(wc -l <"$W/wanted-all.txt"), installing $(wc -l <"$W/wanted.txt"), unavailable on aarch64: $(tr '\n' ' ' <"$L/skipped-unavailable.txt")"
  # substitutes for names the aarch64 repos spell differently (recorded in report 13)
  grep -qx nvim "$L/skipped-unavailable.txt" && grep -qx neovim "$W/available.txt" && echo neovim >> "$W/wanted.txt"
  echo sudo >> "$W/wanted.txt"   # Omarchy's setup scripts call sudo; the ALARM base has none (Omarchy's ISO base does)
  cp "$W/wanted.txt" "$T/root/wanted.txt"
  CH bash -c "pacman --noconfirm --disable-sandbox --color never -S --needed \$(cat /root/wanted.txt)" >>"$L/runtime.log" 2>&1 \
    || { echo "runtime install failed, see $L/runtime.log"; tail -20 "$L/runtime.log"; exit 1; }
  if [ -x "$T/usr/bin/omarchy-hw-platform" ]; then
    echo "platform seen in the image: $(CH bash -p /usr/bin/omarchy-hw-platform 2>&1)" | tee "$L/platform.log"
    grep -qx 'platform seen in the image: aarch64' "$L/platform.log" || { echo "platform is not aarch64"; exit 1; }
  else
    echo "runtime $(CH pacman -Q omarchy) has no omarchy-hw-platform (pre-platform runtime): manifest kept for later runtimes" | tee "$L/platform.log"
  fi
fi

if [ "$STAGE" = all ] || [ "$STAGE" = apply ]; then
  # ext4 root, no btrfs/snapper/limine (m5boot boots us): snapper.sh's own switch writes its config without
  # calling snapper (create-config can't work on ext4 anyway). Recorded in report 13.
  # ufw needs nftables netlink, which qemu-user does not emulate. Build-time only: bind-mount a recorder over
  # /usr/bin/ufw (the image's real ufw is untouched); every ufw command Omarchy runs is written to
  # /var/lib/m5/ufw-replay, and m5-firstboot replays it natively on the Mac before ufw starts.
  install -d -m 0755 "$T/var/lib/m5"; : > "$T/var/lib/m5/ufw-replay"
  cat > "$W/ufw-record" <<'REC'
#!/bin/bash
printf 'ufw' >> /var/lib/m5/ufw-replay; printf ' %q' "$@" >> /var/lib/m5/ufw-replay; echo >> /var/lib/m5/ufw-replay
[ "${1:-}" = status ] && echo "Status: inactive"
exit 0
REC
  chmod 755 "$W/ufw-record"; mount --bind "$W/ufw-record" "$T/usr/bin/ufw"
  CH env OMARCHY_PATH=/usr/share/omarchy OMARCHY_SNAPPER_CONFIGURE_TEST=1 /usr/bin/omarchy-apply-system --defer-provisioning --first-install \
    >"$L/system-setup.log" 2>&1 || { echo "omarchy-apply-system failed (logs/system-setup.log)"; tail -30 "$T/var/log/omarchy-install.log"; }
  umount "$T/usr/bin/ufw"
  echo "recorded ufw commands for first boot:"; cat "$T/var/lib/m5/ufw-replay"
  install -m 0644 "$R/tools/rootfs/files/m5-ufw-replay.service" "$T/etc/systemd/system/"
  ln -sf /etc/systemd/system/m5-ufw-replay.service "$T/etc/systemd/system/multi-user.target.wants/m5-ufw-replay.service"
fi

if [ "$STAGE" = all ] || [ "$STAGE" = pack ]; then
  # Omarchy 4.0.6's post-install/pacman.sh copies its x86 templates (core/extra/multilib + an x86 mirror) over
  # pacman.conf and the mirrorlist, dropping [alarm] and our guards. Final config for this aarch64 machine:
  install -m 0644 "$W/alarm-mirrorlist" "$T/etc/pacman.d/mirrorlist"
  cat > "$T/etc/pacman.conf" <<PACCONF
# pacman.conf for Omarchy on the J714s (m5 image). Written by tools/rootfs/build-omarchy.sh:
# Omarchy's [options] + [omarchy] ${OMARCHY_CHANNEL}, ALARM's repos and mirrorlist, and our guards.
# Don't let omarchy-update/post-install overwrite this (it installs x86 templates); see report 13.
[options]
Color
ILoveCandy
VerbosePkgLists
HoldPkg = pacman glibc
Architecture = auto
CheckSpace
ParallelDownloads = 5
DownloadUser = alpm
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
# our kernel + m5boot boot path stay; hyprland stays on ALARM's 0.57 (stable [omarchy] 0.56.2 is unresolvable)
IgnorePkg = $GUARD hyprland

[omarchy]
Server = https://pkgs.omarchy.org/${OMARCHY_CHANNEL}/\$arch

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[alarm]
Include = /etc/pacman.d/mirrorlist

[aur]
Include = /etc/pacman.d/mirrorlist
PACCONF
  CH pacman -Q > "$L/packages.txt"
  if grep -iE '^(m1n1|aura|uboot-asahi|omarchy-mac-boot|linux-aurora)' "$L/packages.txt"; then
    echo "FORBIDDEN boot package present"; exit 1
  fi
  grep -iE 'm1n1|aurora|asahi' "$L/packages.txt" > "$L/asahi-related.txt" || true
  rm -f "$T/etc/resolv.conf" "$T/root/omarchy-key.asc" "$T/root/wanted.txt"; ln -sfn /run/systemd/resolve/resolv.conf "$T/etc/resolv.conf"
  CH pacman -Scc --noconfirm >/dev/null 2>&1 || true
  # Stage A first boot: console + SSH only. SDDM (a Hyprland greeter on simpledrm/llvmpipe, 1 core) and Omarchy's
  # owner provisioning stay off until Stage B: systemctl set-default graphical.target (see report 13).
  ln -sfn /usr/lib/systemd/system/multi-user.target "$T/etc/systemd/system/default.target"
  CH gpgconf --homedir /etc/pacman.d/gnupg --kill all >/dev/null 2>&1 || true
  rm -f "$T"/etc/pacman.d/gnupg/S.* "$T"/root/.gnupg/S.* 2>/dev/null || true   # agent sockets (tar can't archive them)
  umount -R "$T/proc" "$T/sys" "$T/dev" "$T/run" "$T/tmp" 2>/dev/null || true
  bsdtar --zstd --options zstd:compression-level=10,zstd:threads=0 --numeric-owner -cpf "$R/build/rootfs-omarchy.tar.zst" -C "$T" .
  (cd "$R/build" && sha256sum rootfs-omarchy.tar.zst | tee rootfs-omarchy.tar.zst.sha256)
fi
