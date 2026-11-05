# 34 — VM proof of the loop safety guard (`tools/rootfs/m5drop-guard`): works, with one fix

**Harness:** `tools/vmtest/guard-vm.sh CASE [ON_ACTIVE]` (VM only).
- **Disk:** the Mac's layout on a 4 KiB-block NVMe: ESP 499,998,720 B (FAT32) + Linux 120,000,000,000 B with **rootfs v3**.
- **ESP:** `m5drop/` = the guard tree, with `--on-active` patched **in the test copy only**, plus `m5stay` for the stay case.
- **Boot:** vm-v1 kernel + **m5boot's own `initramfs-loop.cpio.gz`** (`4434904f…`, the inputs.md entry), so the real `m5-drop` allow-list copy runs. Cmdline `m5.root=s5 m5.esplog=1`.
- **Readout:** `-no-reboot`, so a guest reboot ends QEMU. Results are read back from the ESP (rootfs journal/dmesg via `tools/fat32-cat.py`).
- This is the same mechanism `~/m5boot/tests/qemu-loop.sh` uses for m5drop, with NVMe instead of virtio and rootfs v3 instead of its stub root.

## Results (VM)
| | Evidence | Result |
|---|---|---|
| **(a) drop-in applied, guard scheduled** | `m5drop: copied etc/systemd/system.conf.d/m5-watchdog.conf`, `… sddm.service.d/m5-guard.conf`, `… usr/local/bin/m5-guard`, `done: 3 copied, 0 rejected`; then `systemd-run: Running timer as unit: m5-guard.timer` / `Will run service as unit: m5-guard.service` at ~29 s (sddm `ExecStartPre`) | **PASS** |
| **(b) no m5stay → reboot** (on-active 60) | ~93 s: `m5-guard: rebooting to return to macOS (ESP /dev/nvme0n1p1, no m5stay)`, `reboot requested … (unit m5-guard.service)`; QEMU exit 0 at 99 s | **PASS** (old and fixed guard) |
| **(c) m5stay → no reboot** | ~93 s: `m5-guard: m5stay present (/dev/nvme0n1p1), not rebooting`, timer/service deactivated; QEMU still running at the 600 s timeout | **PASS** (fixed guard) |
| **(d) ESP match** | 499,998,720 B / 512 = **976560** sysfs sectors (sysfs `size` is always in 512-byte units, also on 4 KiB disks); the guard picked `/dev/nvme0n1p1` | **PASS** for this layout and the Mac's (task 18 fact: disk0s4 = 499,998,720 B) |

## Bug found and fixed (VM, first run with the PM's guard)
```
m5-guard[3068]: mount warning:
m5-guard[3068]:       * nvme0n1p1: Can't mount, would change RO state
m5-guard[3058]: m5-guard: rebooting to return to macOS
```
- **Cause:** the rootfs ESP logger (`m5-esplog-rootfs`, every 30 s; slow under TCG, so it's mounted for seconds) had the same ESP mounted **rw**. A second vfat mount of the same device with `-o ro` is refused, and the old guard treated "can't mount" as "no m5stay".
- **Effect:** with `m5stay` present, the guard would reboot anyway whenever its run overlapped a logger write. On the Mac, at 900 s, that's a 1-in-several chance per boot, depending on how long the logger's mount lasts.
- **Fix:** mount `rw,noatime` like the logger (the kernel reuses the mounted superblock instead of conflicting); retry up to 10 × 2 s; if still busy, read `m5stay` from an existing mount of the device (`findmnt -S`). The decision rule is unchanged: reboot unless `m5stay` is seen.
- Still **900 s** in the shipped drop-in; only the test copy used 60.

## Exact diff (the only file changed; `m5-guard.conf` and `m5-watchdog.conf` unchanged)
```diff
--- a/tools/rootfs/m5drop-guard/usr/local/bin/m5-guard (PM, as on the Mac ESP)
+++ b/tools/rootfs/m5drop-guard/usr/local/bin/m5-guard (task 34)
@@ -1,9 +1,19 @@
 #!/bin/sh
 # m5-guard: hands-free loop safety net. Reboots (-> macOS via one-shot bless) unless the ESP has m5stay.
+# Task 34 (VM-proved): the ESP logger (m5-esplog-rootfs, every 30 s) mounts the same ESP rw; a second mount with
+# "-o ro" then fails ("Can't mount, would change RO state") and the old guard rebooted even with m5stay present.
+# Now: mount rw,noatime like the logger (shares the superblock), retry ~20 s, else read an existing mount of it.
 p=$(for d in /sys/block/nvme0n1/nvme0n1p*; do [ "$(cat $d/size)" = 976560 ] && echo /dev/${d##*/}; done | head -1)
-mkdir -p /run/m5esp
-if [ -n "$p" ] && mount -o ro -t vfat "$p" /run/m5esp 2>/dev/null; then
-  [ -e /run/m5esp/m5stay ] && { echo "m5-guard: m5stay present, not rebooting"; umount /run/m5esp; exit 0; }
-  umount /run/m5esp
+M=/run/m5esp; mkdir -p $M; seen=""
+if [ -n "$p" ]; then
+  for i in 1 2 3 4 5 6 7 8 9 10; do
+    if mount -o rw,noatime -t vfat "$p" $M 2>/dev/null; then
+      [ -e $M/m5stay ] && seen=1; umount $M; break
+    fi
+    o=$(findmnt -nro TARGET -S "$p" | head -1)            # mounted elsewhere (e.g. by the logger): read it there
+    [ -n "$o" ] && { [ -e "$o/m5stay" ] && seen=1; break; }
+    sleep 2
+  done
 fi
-echo "m5-guard: rebooting to return to macOS"; sync; systemctl reboot || reboot -f
+[ -n "$seen" ] && { echo "m5-guard: m5stay present ($p), not rebooting"; exit 0; }
+echo "m5-guard: rebooting to return to macOS (ESP ${p:-not found}, no m5stay)"; sync; systemctl reboot || reboot -f
```
New sha256 of `usr/local/bin/m5-guard`: `ca7eb95b755564b2b523d0d6caa74acc0a8cad0c5e64b0acb411f23f65ba1aca` (1175 B). Copy it to the Mac ESP's `m5drop/usr/local/bin/m5-guard`.

## Minor, for m5boot's `m5-drop` (not changed here)
FAT gives every file mode 0755, so the copied `.conf` files are executable. systemd warns "Configuration file /etc/systemd/system/sddm.service.d/m5-guard.conf is marked executable", which is harmless. Suggest `m5-drop` set 0644 for everything outside `*/bin/*`.
