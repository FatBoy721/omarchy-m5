# 30 — Keyboard/trackpad: cold-restart the MTP that iBoot left running (built, VM-checked; NATIVE pending)

## What gz12 showed (NATIVE, `reports/native-gz12-rootfs-dmesg.txt`)
- **No SError with MTP + its DART enabled** (USB DARTs off). gz5's SError was the USB0 DART, as suspected in reports 24/28. The MTP DART probes fine ("16 streams, bypass support: 1, locked: 0").
- `rtkit-helper 294600000.mtp`: `apple_rtkit_wake()` timed out (-62/-ETIME) after 2 s. Then the probe's cleanup (`apple_rtkit_helper_stop` → `apple_rtkit_shutdown`) also timed out: "Coprocessor shutdown failed: -62; DMA must remain mapped". So `dockchannel-hid` (`294b28000.input`) stays deferred. It refuses to start unless `apple_rtkit_helper_is_running()`.

## Cause
- `rtkit-helper` probe writes `CPU_CONTROL.RUN`, then `apple_rtkit_wake()`. That sends `SET_IOP_PWR_STATE(INIT)` and waits for a fresh HELLO/EPMAP (`apple_rtkit_boot`).
- The MTP is **already running** from iBoot (ADT `pre-loaded = 1`) in an RTKit session Linux never booted, so no new handshake comes.
- **The same T6050 situation is documented in our kernel tree** for ANS: `drivers/nvme/host/apple.c` (asahi-wip-7.2 @236788cd + betizzel 0006): "Some bootloaders (iBoot on T6050) hand ANS over with its CPU running in an RTKit state we never booted. If waking that session does not work, force_cold_reset=1 stops the CPU so the reset path below runs". That reset path is: `CPU_CONTROL = 0` → `apple_rtkit_reinit()` → `CPU_CONTROL = RUN` → `apple_rtkit_boot()`.

## Fix: `tools/kernel/patches/0003-m5-rtkit-helper-cold-restart.patch` (GPL, ours)
- At probe, read `CPU_CONTROL` and log whether the bootloader left it running.
- Keep the stock path: `RUN` + `apple_rtkit_wake()` (so a cleanly sleeping IOP behaves as before).
- **If that fails and the CPU was running at probe:** `CPU_CONTROL = 0`, wait 1–2 ms, `apple_rtkit_reinit()`, `CPU_CONTROL = RUN`, `apple_rtkit_boot()` (fresh HELLO from the firmware iBoot preloaded). Logged as "cold restart: RTKit booted / failed (rc)".
- **New hardware writes:** two writes to the MTP ASC's own `CPU_CONTROL` (0x294600044: 0, then RUN). The stock driver already writes this register (RUN at probe, 0 at stop). **No PMGR, SMC or audio writes.** The MTP has no PMGR domain.
- [HYPOTHESIS] The firmware restarts from its reset vector with its iBoot-preloaded image still in place, as on the ANS cold path. If it doesn't, the log shows "cold restart: failed (-62)" and the next step is a PMGR-level reset, which the MTP doesn't have in the ADT.
- Still no DAPF programming (report 28). If the RTKit boots but HID shows no events, DAPF is next.

## Input proof in the ESP log (rootfs v3)
`m5-esplog-rootfs` (every 30 s) now also writes:
- `m5log/rootfs-<boot>-input.txt`: `/proc/bus/input/devices`, `hyprctl devices` (run as alarm on the live Hyprland instance), udev `ID_INPUT_KEYBOARD/TOUCHPAD/MOUSE`, and the mtp/rtkit/dockchannel/hid dmesg lines.
  - `libinput list-devices` is attempted, but `libinput` (package libinput-tools) isn't in the image; `hyprctl devices` covers what the compositor sees.
- `m5log/rootfs-<boot>-user.txt`: `journalctl -b _UID=1000` (uwsm/Hyprland output) + `hyprland.log` tails if present.

**VM (rootfs v3, QEMU, 4K NVMe):** both files appear on the ESP. `hyprctl devices` returns the (empty) device lists from the running Hyprland, and the user journal shows "Welcome to Hyprland!". MTP can't be tested in a VM.

## Deliverables (new filenames; hashes in `~/m5boot/spec/inputs.md` § Input v2)
`build/input-v2/Image.gz` (+ `Image`), `build/input-v2/t6050-j714s-I2.dtb` (byte-identical to I1), `build/rootfs-omarchy-v3.ext4(.zst)`. Initramfs unchanged (r28a).

## CORRECTION 2026-11-05 (NATIVE gz14): the premise above was wrong
`reports/native-gz14-rootfs-dmesg.txt`: `rtkit-helper 294600000.mtp: CPU_CONTROL at probe: stopped`. **The MTP was NOT running at hand-off**, so the "iBoot left it running in a session Linux never booted" explanation and the cold-restart fallback didn't apply. The fallback never ran (it needs `was_running`). The wake after RUN timed out (-62) the same way, and `hyprctl devices` lists no keyboards/mice. The text above stays as written. The cold-restart code is harmless and kept. The next hypothesis (firmware memory not reserved/mapped) is in report 31.
