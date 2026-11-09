#!/bin/sh
# eemfix.sh: after the gadget re-enumerates with gser+eem, make sure cdc_eem owns the EEM interface, then bring it up
for i in $(seq 1 600); do D=$(grep -l 0104 /sys/bus/usb/devices/*/idProduct 2>/dev/null | head -1 | xargs -r dirname); [ -n "$D" ] && ls -d $D:1.1 >/dev/null 2>&1 && break; sleep 1; done
echo "dev=$D $(date +%T)"; for itf in $D:1.*; do echo "$itf class=$(cat $itf/bInterfaceClass) sub=$(cat $itf/bInterfaceSubClass) proto=$(cat $itf/bInterfaceProtocol) drv=$(basename $(readlink $itf/driver 2>/dev/null) 2>/dev/null)"; done
for itf in $D:1.*; do [ "$(cat $itf/bInterfaceClass)" = 02 ] || [ "$(cat $itf/bInterfaceSubClass)" = 0c ] || continue; d=$(readlink $itf/driver); [ -n "$d" ] && echo $(basename $itf) | sudo -n tee $itf/driver/unbind >/dev/null; echo $(basename $itf) | sudo -n tee /sys/bus/usb/drivers/cdc_eem/bind >/dev/null; done
sleep 2; IF=$(for n in /sys/class/net/*; do readlink -f $n/device 2>/dev/null | grep -q "$(basename $D):" && basename $n; done | head -1); echo "IF=$IF"
[ -n "$IF" ] && { sudo -n ip addr add 10.55.0.2/24 dev $IF 2>/dev/null; sudo -n ip link set $IF up; sleep 2; ping -c3 -W2 10.55.0.1; }
