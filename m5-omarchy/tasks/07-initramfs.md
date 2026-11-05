# Task 07 — First-boot initramfs + loader (no Mac changes)

Goal: everything the first tethered boot and the Option B loader need, built and checked on ush. Output: `build/initramfs.cpio.gz` (+ loader variant), `reports/07-initramfs.md`.

PM-approved downloads (routine): official Alpine aarch64 packages (busybox-static, dropbear or dropbear-static, kexec-tools, plus their deps) from dl-cdn.alpinelinux.org, verified against the APKINDEX signatures/checksums. Record each URL + SHA-256. If your permission checker still refuses, say exactly what it refused and propose the next-best source.

Initramfs contents:
1. busybox, an /init that:
   - mounts proc/sys/dev/devtmpfs
   - prints `uname -a`, `nproc`, `/proc/device-tree/compatible` and the model to the console
   - starts USB gadget CDC-EEM networking on every UDC (10.55.n.2/24), as betizzel's `usb-gadget-net.sh` does. That's our own reimplementation, since theirs is unlicensed.
   - starts a dropbear SSH server with **work**'s public key (`ssh-ed25519 …` from `~/.ssh/id_ed25519.pub` on work; the PM will scp it to ush as `build/work.pub`)
   - drops to a console shell on tty0
2. `t6050_probe.ko` + the loader script for Option B (mount the NVMe Linux root if present, then `kexec` from /boot with `--dtb=/sys/firmware/fdt`).
3. A size budget: keep it small (it's chainloaded over USB).

Checks: `cpio -t` listing, `file` on each binary (aarch64, static), and a qemu-aarch64 `virt` smoke boot of our Image + this initramfs **only if** it's quick (label any result VM). End with `DONE 07`.
