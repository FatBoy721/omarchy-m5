# Task 11 — First native boot runbook for m5boot (no Mac changes)

m5boot is being written by a separate clean-room session (~/m5boot). You prepare everything around it. Output: `reports/11-first-native-boot.md` + scripts in `tools/`.

1. **Arming over SSH (PM runs it; the owner only clicks Run or types a password):**
   - The exact commands to copy `m5boot.bin` to the Mac and run `finish-install.sh --m1n1 ~/m5boot.bin` over `ssh -tt`.
   - Does `bless --setBoot --user` work over SSH? If not, give the exact console alternative.
   - Expected output, and stop conditions.
2. **TSS signing check (read-only; owner puts the Mac in DFU):**
   - Exact `idevicerestore -t` command on work, using the local IPSW `~/m5-recovery/UniversalMac_26.6.2_25G83_Restore.ipsw` and the libs in `~/.local/dfu/lib`.
   - What success looks like (a .shsh written), and confirmation that it performs no restore.
   - Also: `usbmuxd` needs to run as root; give the exact command.
3. **1TR ceremony for m5boot:** exact screens/keys for the owner, the credentials prompts, and expected results. Note `step2.sh` runs `kmutil configure-boot -c boot.bin` where boot.bin is now m5boot.
4. **First native boot observation:**
   - What the owner sees on screen: m5boot step lines, then Linux.
   - What `work` should see: the `cdc_eem` gadget appears (`1d6b:0104`). Give `tools/host-usbnet.sh` for work: assign 10.55.0.1/24 to the new usb netdev, then `ssh root@10.55.0.2`.
   - The cable/port: the USB 2.0 path that worked for DFU.
   - Failure triage table: black screen, m5boot panic step N, Linux panic, no USB gadget.
5. **After SSH works:** the exact sequence to run `install-rootfs.sh --dry-run`, then the real install, then the first probe groups (09 plan), and how to switch to the loader initramfs and kexec for kernel iteration.

End with `DONE 11`.
