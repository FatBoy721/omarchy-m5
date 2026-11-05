# Task 33 — post-kexec disk writes never land (NVMe/ANS after kexec?)
NATIVE N1E (05:45): no test-N1E-CHAIN file at all; back in 249 s. Re-read the evidence: NO native boot after a kexec has ever written usable data to the ESP. T01b created rootfs-ff0f5a45 files but all 0 bytes. Common factor is likely NVMe/ANS after kexec: the old kernel shutdown hook stops ANS, and the new kernel cannot get ANS back, so disk I/O hangs or fails.
Our tree drivers/nvme/host/apple.c has the T6050 note about force_cold_reset=1 for an ANS in a state we never booted.
Do:
1. Next test set: T01b set (loop-v1 + initramfs-test-v2 + T01b cmdline + nr_cpus=1) with the nvme_apple force-cold-reset param (exact name from our tree). The test-v2 logger should also print every step to the m5fb earlycon.
2. Evaluate: keep ANS running across kexec (skip its shutdown in the loader kernel path so the new kernel adopts it like at cold boot) if the driver allows; that would need a loader-kernel change, so only as a plan for gz17.
3. Deliver the m5next set (cmdline + initrd) under build/kexec-nvme/, VM test, print exactly DONE 33. No dialogs.
