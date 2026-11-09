#!/bin/sh
# serwatch.sh: wait for the m5 gser gadget, bind usbserial, prove a command round trip
for i in $(seq 1 200); do lsusb | grep -q 1d6b:0104 && break; sleep 3; done
date; lsusb | grep 1d6b:0104 || { echo "no gadget"; exit 1; }
sleep 3; cat /sys/bus/usb/devices/3-3.2/bConfigurationValue 2>/dev/null
sudo -n modprobe usbserial vendor=0x1d6b product=0x0104 2>&1; sleep 3
T=$(ls /dev/ttyUSB* 2>/dev/null | head -1); echo "tty=$T"; [ -n "$T" ] || { journalctl -k -n 15 --no-pager | grep -v UFW | tail -8; exit 2; }
sudo -n chmod 666 $T; stty -F $T 115200 raw -echo
for k in 1 2 3 4 5 6; do
  (timeout 6 cat $T > /tmp/m5ser.out &) ; sleep 0.5
  printf '\r\necho M5OK; id; uname -a; cat /proc/device-tree/model; echo; echo M5END\r\n' > $T
  sleep 6; grep -q M5END /tmp/m5ser.out && break; sleep 10
done
cat /tmp/m5ser.out
