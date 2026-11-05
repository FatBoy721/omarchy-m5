# Task 28 — INPUT for the native desktop (keyboard/trackpad), then USB gadget

Status: gz10 native = no idle reset (owner, log confirmation pending; cause = secondary WDT 0x2_8833_0008, third-party lead). gz11 (desktop via m5.root=s5) is being built. Desktop will have NO input → not usable. This task fixes that.

Priority 1 — internal keyboard + trackpad via MTP/DockChannel:
- Report 24 §4: MTP + DART disabled since the SError; DAPF programming unsolved. Solve it from our ADT dump (reports/04-j714s-full.txt) + Linux asahi sources + betizzel's public Linux patches/DT (github.com/betizzel/omarchy-m5, MIT-noted earlier; NOT its patches/m1n1/). betizzel's agent reports (private message, summarized) that their provisioning boot was operated from the M5's built-in keyboard — so MTP keyboard worked for them natively under Linux (after m1n1). Find what state MTP/DAPF needs and whether Linux alone can set it.
- Trackpad firmware tpmtfw-j714s.bin: extract (betizzel scripts/extract-tpmtfw.py, read its license first) from the Mac's macOS — give me exact read-only macOS commands; put it in the initramfs + rootfs.
- Safety: no SMC writes, no audio. Any new PMGR write must be listed in the report.

Priority 2 — USB gadget (SSH): a private message from betizzel's agent (third-party reported; summarized, not published): ATC0 needs no PMP; power COMMON(0x280600208)+USB_AON+USB with ~10 ms polling (Linux pwrstate gives up after 100 us), then eUSB2 PHY + PIPE-mux bring-up. Linux-side implementation, no m1n1 code. Note m5_pmgr_ro is on in gz10/11: design an allow-list (only the ATC0 chain may be written).

Deliver kernel/DT/initramfs/rootfs updates with hashes in ~/m5boot/spec/inputs.md § Input v1, VM-tested where possible, report reports/28-input-usb.md. Print exactly `DONE 28` (or `BLOCKED 28: <q>`). No dialogs.
