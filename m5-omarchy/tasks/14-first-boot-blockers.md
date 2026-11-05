# Task 14 — PRIORITY: two first-boot blockers found by the m5boot implementer (pause 13 at a safe point)

Found in a QEMU run of our J714s Image + initramfs through m5boot (VM):
1. **initramfs /init dies:** `exec setsid cttyhack sh` fails because Alpine busybox-static 1.37.0 has no `cttyhack` applet. init exits and the kernel panics ("Attempted to kill init") about 2 s in, taking SSH down. Fix `/init` so it **never exits**: start the console shell in a respawn loop (`while true; do setsid sh -c 'exec sh </dev/tty0 >/dev/tty0 2>&1'; sleep 1; done`, or similar, using applets that exist), keep dropbear + gadget-net in the background, and check each applet you use exists in that busybox (`busybox --list`). Apply the same fix to the loader initramfs.
2. **Hard-coded framebuffer write:** early in boot the kernel writes red 10-bit pixels (0x3ff00000) to fixed PA `0x10bd3110000` with a 3024 stride, whatever iBoot/m5boot report. Find the source (likely one of betizzel's 9 patches or a DT fixed address) and **remove it**, or make it use only the DT simple-framebuffer address. Our rule: no writes to unknown memory. Record which patch/file it was.

Then:
- Rebuild Image + initramfs (+ loader), boot-test the initramfs in QEMU if quick (VM). Confirm /init stays up and dropbear listens.
- Update `~/m5boot/spec/inputs.md` with the new paths + SHA-256 (keep the old hashes in a "superseded" line).
- Resume task 13 afterwards.

End with `DONE 14`.
