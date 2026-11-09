#!/bin/sh
# m5-exp u10d: task 55: u9 flow (left-front ATC1, usbdbg3 trace + FIFO dump) with a generic-serial (gser) gadget: bulk IN/OUT only, NO IN data queued at SET_CONFIGURATION (ACM/ECM both queue a notify on ep2in)
T=u10s; DESC="task 55: u9 flow (left-front ATC1, usbdbg3 trace + FIFO dump) with a generic-serial (gser) gadget: bulk IN/OUT only, NO IN data queued at SET_CONFIGURATION (ACM/ECM both queue a notify on ep2in)"
# Sourced by /usr/local/bin/m5-exp (task 35). Logs to /run/m5exp.log + kmsg; esp_save writes log + dmesg to
# ESP m5log/exp-$T-<boot>.txt after every stage (verified mount; rw,noatime like the other loggers; retries).
B=$(cut -c1-8 /proc/sys/kernel/random/boot_id); KO=/usr/local/lib/m5/m5_mtp.ko; L=/run/m5exp-$T.log
log() { echo "$(cut -d' ' -f1 /proc/uptime) $*" >> $L; echo "m5exp-$T: $*" > /dev/kmsg; }
esp_save() {
  p=$(for d in /sys/block/nvme0n1/nvme0n1p*; do [ "$(cat $d/size)" = 976560 ] && echo /dev/${d##*/}; done | head -1)
  [ -n "$p" ] || { log "no ESP"; return 1; }
  M=/run/m5exp-esp; mkdir -p $M
  for i in 1 2 3 4 5 6 7 8 9 10; do mount -o rw,noatime -t vfat "$p" $M 2>/dev/null && break; sleep 1; done
  grep -q "^$p $M vfat " /proc/mounts || { log "ESP mount failed"; return 1; }
  mkdir -p $M/m5log; F=$M/m5log/exp-$T-$B.txt
  { cat $L; echo "--- dmesg"; dmesg; } > $F.tmp && mv $F.tmp $F; sync; umount $M
}
mod() { log "insmod m5_mtp $* (EAGAIN = ran and unloaded)"; esp_save; insmod $KO "$@" >> $L 2>&1; esp_save; }
dump() { for r in "$@"; do mod op=dump region=$r; done; }
bind() { log "stock rtkit-helper re-probe (bind 294600000.mtp)"
         echo 294600000.mtp > /sys/bus/platform/drivers/rtkit-helper/bind 2>> $L; log "bind rc=$?"; sleep 5; esp_save; }
input() { log "input proof"; { echo "--- /proc/bus/input/devices"; cat /proc/bus/input/devices
          echo "--- drivers bound"; ls -l /sys/bus/platform/devices/294600000.mtp/driver /sys/bus/platform/devices/294b28000.input/driver 2>&1; } >> $L; esp_save; }
log "start $T ($DESC)"; uname -r >> $L; modinfo -F vermagic $KO >> $L 2>&1
rng() { mod op=dump region=$1 from=$2 to=$3; }	# task 36: read-only range dump of a window
twice() { "$@"; sleep 2; "$@"; }		# task 36: same reads 2 s apart (are counters/state moving?)
U=/usr/local/lib/m5/m5_usb.ko
if [ "$(uname -r)" != "7.2.2-m5slim+" ] || ! grep -qw "m5.testmarker=USB-U10S" /proc/cmdline; then
  log "WRONG KERNEL/SET: uname $(uname -r), cmdline $(cat /proc/cmdline); push build/usb-v1/m5next-u10d as m5next/. Nothing done."; esp_save; exit 0; fi
TR=/sys/kernel/tracing; mountpoint -q $TR || mount -t tracefs none $TR; mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
echo 8192 > $TR/buffer_size_kb; echo 1 > $TR/events/dwc3/enable; echo 0 > $TR/events/dwc3/dwc3_readl/enable; echo 0 > $TR/events/dwc3/dwc3_writel/enable
echo 1 > $TR/events/gadget/enable 2>>$L; echo 1 > $TR/tracing_on; log "trace on: $(cat $TR/set_event | tr '\n' ' ' | cut -c1-300)"
echo 'file drivers/usb/dwc3/* +p; file drivers/usb/gadget/* +p; file drivers/iommu/apple-dart.c +p' > /sys/kernel/debug/dynamic_debug/control 2>>$L; log "dyndbg rc=$?"
trsave() {	# trace snapshot -> ESP m5log/trace-$T-<boot>.txt (separate file; same verified mount)
  p=$(for d in /sys/block/nvme0n1/nvme0n1p*; do [ "$(cat $d/size)" = 976560 ] && echo /dev/${d##*/}; done | head -1); [ -n "$p" ] || return 1
  M=/run/m5exp-esp; mkdir -p $M; mount -o rw,noatime -t vfat "$p" $M 2>/dev/null; grep -q "^$p $M vfat " /proc/mounts || return 1
  tail -c 6000000 $TR/trace > $M/m5log/trace-$T-$B.txt.tmp && mv $M/m5log/trace-$T-$B.txt.tmp $M/m5log/trace-$T-$B.txt; sync; umount $M; log "trace saved"; }
dartinfo() { log "iommu: $(for g in /sys/kernel/iommu_groups/*; do echo "${g##*/}:$(cat $g/type 2>&1):$(ls $g/devices | tr '\n' ,)"; done | tr '\n' ' ')"; dmesg | grep -iE "dart|iommu|fault" | tail -40 >> $L; }
umod() { log "insmod m5_usb $* (EAGAIN = ran and unloaded)"; esp_save; insmod $U port=1 "$@" >> $L 2>&1; esp_save; }
log "insmod m5_hpm op=ssps (WRITES: hpm1 read; SSPS only if APP and not S0)"; esp_save; insmod /usr/local/lib/m5/m5_hpm.ko op=auto usid=0xa >> $L 2>&1; esp_save
umod op=state
for d in atc1_common atc1_usb atc1_phymxwrap; do
  umod op=pon dom=$d step=auto; umod op=pon dom=$d step=target
  dmesg | grep -q "m5usb: pon $d +[0-9]*us 0x[0-9a-f]* actual f" || { log "STOP: $d did not reach actual f (children not attempted)"; umod op=state; esp_save; exit 0; }
  log "$d actual f"
done
umod op=state
umod op=dev
umod op=dt_nopd; sleep 2
for d in 2aaf00000.iommu 2aaf80000.iommu 2aa280000.usb; do log "$d driver: $(readlink /sys/bus/platform/devices/$d/driver 2>&1)"; done
[ -e /sys/bus/platform/devices/2aa280000.usb/driver ] || { echo 2aa280000.usb > /sys/bus/platform/drivers/dwc3/bind 2>>$L; log "dwc3 bind rc=$?"; sleep 2; }
log "udc: $(ls /sys/class/udc 2>&1)"; esp_save
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
G=/sys/kernel/config/usb_gadget/m5; mkdir -p $G/strings/0x409 $G/configs/c.1/strings/0x409
echo 0x1d6b > $G/idVendor; echo 0x0104 > $G/idProduct; echo m5-omarchy > $G/strings/0x409/product; echo gser > $G/configs/c.1/strings/0x409/configuration
umod op=dwc3dump; mkdir -p $G/functions/gser.0; ln -s $G/functions/gser.0 $G/configs/c.1/ 2>>$L; dartinfo; trsave
ls /sys/class/udc | head -1 > $G/UDC 2>>$L; log "UDC bind rc=$? -> $(cat $G/UDC 2>&1)"
sleep 1; sleep 5; umod op=dwc3dump; ls -l /dev/ttyGS* >> $L 2>&1; dartinfo; trsave
umod op=dwc3dump
setsid /usr/bin/agetty -a root -L ttyGS0 115200 vt100 >> $L 2>&1 & log "agetty on ttyGS0 started (root autologin)"; systemctl start sshd >> $L 2>&1; log "sshd: $(systemctl is-active sshd)"
ip addr >> $L; esp_save
for n in 1 2 3 4 5 6 7 8 9 10; do sleep 60; [ $n -le 2 ] && umod op=dwc3dump; [ $n = 99 ] && { S=/sys/class/udc/2aa280000.usb/soft_connect; echo disconnect > $S 2>>$L; sleep 1; echo connect > $S 2>>$L; log "soft_connect toggled rc=$?"; }; dartinfo; trsave; log "t+${n}m udc state $(cat /sys/class/udc/*/state 2>&1) usb0 $(cat /sys/class/net/usb0/operstate 2>&1)"; esp_save; done
log "end"; esp_save
