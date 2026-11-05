# Task 30 — keyboard/trackpad: attach to the iBoot-running MTP instead of restarting it

NATIVE gz12 (2026-11-05 00:03): Omarchy booted to SDDM autologin → uwsm Hyprland, 302 s, no reset. Logs: reports/native-gz12-rootfs-{journal,dmesg}.txt.
Input failed:
  rtkit-helper 294600000.mtp: Coprocessor shutdown failed: -62; DMA must remain mapped
  rtkit-helper 294600000.mtp: error -62: Failed to wake up coprocessor
  probe with driver rtkit-helper failed with error -62
  platform 294b28000.input: deferred probe pending
MTP is pre-loaded and RUNNING from iBoot (ADT pre-loaded=1). The driver tries shutdown→reboot and the coprocessor doesn't answer.
Fix in Linux (our patch, GPL): make the MTP/rtkit path attach to an already-running coprocessor (skip shutdown; do the RTKit hello/wake handshake on the running IOP, or a proper "boot from running" sequence), or whatever Asahi's rtkit/mtp code does for pre-loaded IOPs — cite sources. Also add the user journal (journalctl --user / Hyprland log) and `libinput list-devices` + /proc/bus/input/devices to the ESP logger so the next run proves input.
Deliver an input-v2 kernel/DTB (+rootfs overlay if changed) under NEW filenames, hashes in ~/m5boot/spec/inputs.md § Input v2. Then I'll have m5boot build gz14. Report reports/30-mtp-attach.md. Print exactly `DONE 30` (or `BLOCKED 30: <q>`). No dialogs.
