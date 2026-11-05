# Task 28 — chain-loader initrd (work around a gz16 loader bug WITHOUT a new 1TR)
NATIVE (03:40): m5next with a dtb → gz16 loader ran ONLY `kexec -c -l Image --initrd --dtb` (kexec_load) → "Function not implemented" (loader kernel has no CONFIG_KEXEC) → reboot (safety OK). It never tried `kexec -s --dtb` (kexec_file_load supports a dtb on arm64). Log: the PM can scp it; key lines:
  m5next: kexec -c -l Image --initrd=/tmp/m5n/initrd --dtb=/tmp/m5n/dtb (kexec_load)
  kexec_load failed: Function not implemented ... FAIL: kexec load failed (both syscalls)
Fix later in gz17 (note it in NOTES), but NOW build a two-stage workaround usable with gz16:
- m5next = loop-v1 Image (works with file_load, no dtb) + cmdline incl. nr_cpus=1 + a "chain" initrd.
- chain initrd: busybox+kexec (from the loop initramfs) + an embedded payload dir (Image2, dtb2, initrd2, cmdline2, SHA256SUMS). Its /init: start the m5wdt daemon, verify hashes, log to ESP (verified mount), `kexec -s -l Image2 --dtb=dtb2 --initrd=initrd2 --command-line="$(cat cmdline2)"` (append live earlycon like the loader does), stop wdt daemon, `kexec -e`. On ANY failure: log, sync, reboot -f after 30 s.
- Provide tools/loop/mkchain.sh PAYLOADDIR OUT.cpio.gz so the PM can wrap any kernel. First payload: ~/m5-n1/out/{Image,dtb,cmdline} + initramfs-test-v2 as initrd2.
VM-test the chain (loop-v1 → chain → a second kernel with a supplied dtb, spin-table CPUs). Print exactly `DONE 28` (or `BLOCKED 28: <q>`). No dialogs.
