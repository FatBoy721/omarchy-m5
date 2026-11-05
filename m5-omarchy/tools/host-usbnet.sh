#!/bin/bash
# host-usbnet.sh — on "work": find the Mac's CDC-EEM gadget netdev(s) (USB 1d6b:0104, serial m5pro-<n>),
# give each 10.55.<n>.1/24, bring it up, and print the ssh command. Needs sudo for `ip`.
# Usage: tools/host-usbnet.sh [--wait SECONDS]   (default: wait up to 60 s for the gadget to appear)
set -euo pipefail
WAIT=60; [ "${1:-}" = --wait ] && WAIT=$2
found=0
for ((i = 0; i < WAIT && found == 0; i++)); do
  for net in /sys/class/net/*; do
    dev=$(readlink -f "$net/device" 2>/dev/null) || continue
    usb=${dev%/*}                                   # interface dir -> USB device dir
    [ -r "$usb/idVendor" ] || continue
    [ "$(cat "$usb/idVendor"):$(cat "$usb/idProduct")" = 1d6b:0104 ] || continue
    serial=$(cat "$usb/serial" 2>/dev/null || true)
    case $serial in m5pro-[0-9]*) n=${serial#m5pro-} ;; *) continue ;; esac
    ifc=${net##*/}
    driver=$(basename "$(readlink -f "$net/device/driver")")
    echo "found $ifc: usb $(basename "$usb") serial=$serial driver=$driver"
    # keep NetworkManager from running DHCP on it, if NM is in use
    command -v nmcli >/dev/null && nmcli dev set "$ifc" managed no 2>/dev/null || true
    sudo ip addr flush dev "$ifc"
    sudo ip addr add "10.55.$n.1/24" dev "$ifc"
    sudo ip link set "$ifc" up
    echo "  $ifc = 10.55.$n.1/24  ->  ssh root@10.55.$n.2"
    found=1
  done
  [ $found = 1 ] || sleep 1
done
[ $found = 1 ] || { echo "no 1d6b:0104 m5pro-* gadget after ${WAIT}s (lsusb shows:)"; lsusb | grep -i '1d6b:0104' || true; exit 1; }
ping -c 2 -W 2 10.55.${n}.2 || echo "(no ping reply yet: the Mac side may still be configuring)"
