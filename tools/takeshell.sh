#!/bin/sh
# takeshell.sh: wait for the gser gadget, bind generic usb-serial, disarm reboots on the Mac
cd ~/m5-build
for i in $(seq 1 240); do D=$(grep -l 0104 /sys/bus/usb/devices/*/idProduct 2>/dev/null | head -1 | xargs -r dirname); [ -n "$D" ] && [ "$(cat $D/bConfigurationValue 2>/dev/null)" = 1 ] && break; sleep 2; done
echo "gadget $D $(date +%T)"; sudo -n modprobe usbserial; echo "1d6b 0104" | sudo -n tee /sys/bus/usb-serial/drivers/generic/new_id >/dev/null 2>&1; sleep 4; ls /dev/ttyUSB*
for k in 1 2 3 4 5 6 7 8; do ./msh-tcp.py 'echo up' 10 >/dev/null 2>&1 && break; sleep 5; done
./msh-tcp.py 'systemctl stop m5-guard.timer 2>/dev/null; pkill -f m5-autoreboot; mkdir -p /run/systemd/system/m5-exp.service.d; printf "[Service]\nExecStopPost=\nTimeoutStartSec=infinity\n" > /run/systemd/system/m5-exp.service.d/zz-stay.conf; systemctl daemon-reload; ps -eo args | grep -cE "m5-autoreboot" ; uptime; grep PRETTY /etc/os-release' 30
