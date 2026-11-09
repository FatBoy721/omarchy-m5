# Task 13 — Bake the Omarchy userland into the rootfs image (Stage B prep; no Mac changes)

Per report 12: Omarchy honors the `generic-aarch64` image manifest only while the root **isn't booted**, so we install the userland offline into our rootfs image. Output: `build/rootfs-omarchy.tar.zst` + SHA-256, `reports/13-omarchy-image.md`.

Constraints:
- **No root on ush.** Use `proot` + `qemu-aarch64-static`, user-level, no binfmt registration needed. Fall back to `systemd-nspawn`/`arch-chroot` only if proot can't work, and then end with `BLOCKED 13: need sudo for …` and the exact commands.
- Start from our `build/rootfs-alarm.tar.zst` (safe kernel + modules). Keep **our** kernel: `IgnorePkg` for `linux-aarch64*`, `linux-aurora*`, `linux` if Omarchy pulls it.
- **Never install any m1n1 package** (`m1n1-aurora`, `m1n1`, `uboot-asahi`, `omarchy-mac-boot`, `asahi-*` boot tooling). Use the generic `aarch64` platform via the image manifest exactly as report 12 describes. Add them to `IgnorePkg` too, as a belt-and-braces guard. Verify at the end with `pacman -Q | grep -iE "m1n1|aurora|asahi"` (expect nothing m1n1-related; list anything Asahi-related and justify it).
- Verify package signatures: Omarchy key `40DFB630…C571` via keys.openpgp.org + the `omarchy-keyring` package, plus the ALARM key.
- Display: simpledrm + Mesa llvmpipe (no Apple GPU drivers). Make sure Hyprland/uwsm/sddm configs don't require a GPU driver. Note anything that will need tweaks on first boot.
- Keep it reproducible: `tools/rootfs/build-omarchy.sh`.

Report: the package count, size, what's left for first boot (user creation? Omarchy's first-run steps), and any packages that failed on aarch64. End with `DONE 13`.
