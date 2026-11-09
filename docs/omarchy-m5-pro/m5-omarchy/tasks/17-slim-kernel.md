# Task 17: fit the boot object under ~11 MiB (in case the probe confirms a size cap of about 0xcb0000)

Goal: m5boot-gz total (shim + DTB + compressed Image + initramfs) <= 11 MiB, ideally <= 10 MiB.
1. A minimal bring-up kernel config: built-in only what first boot needs (arm64 Apple platform, AIC, DART, simplefb/simpledrm + fbcon, DWC3 gadget + configfs EEM, DockChannel/MTP keyboard, NVMe/ANS/SART, ext4, initramfs, devtmpfs), everything else =m or off. Keep the safety limits (no audio, no SMC, no cpufreq, no GPU/DCP). The modules go into the rootfs later.
2. Try compressors m5boot can inflate: gzip -9 now; report xz/zstd sizes too, in case it is worth adding a decoder later.
3. Shrink the initramfs (drop unneeded parts; keep busybox, dropbear, gadget-net, mkfs/sfdisk, install-rootfs.sh).
4. Report sizes: Image, Image.gz, initramfs.gz, projected m5boot-gz total. Update ~/m5boot/spec/inputs.md with the new artifacts as a separate "slim" section (keep the current ones).
Use all 24 cores. End with DONE 17.
