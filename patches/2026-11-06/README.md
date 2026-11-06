# Source changes, 2026-11-06 (built and reviewed; NOT yet tested natively)

Both diffs are against our FT19 kernel tree (Asahi `asahi-wip-7.2` base plus our earlier patches). Per-file licenses and upstream attribution are kept in the code comments. No Apple firmware, binaries or device-private data are included.

## `platform-r2/`: platform port, first stage
- **`src-platform-r2.diff`**, which contains:
  - **SMC lane:** a built-in DT overlay for the J714s SMC and nub-spmi0/PMIC NVMEM, applied at runtime because our boot loader builds the live device tree. Derived from edimoldovan/linux-aurora `4602eba4b9d2` and `c5b0600d19a4`.
  - **SMC children:** sensors, RTC and lid/power button, each behind its own boot switch and **all off by default**.
  - **SMC shared-memory reads:** done as byte loads.
  - **Display lane:** simpledrm eDP connector (`9dee12b1266c`); keyboard-backlight driver compiled in but off (`594f4b3a49ec`).
- **Config fragments:** `m5-platform-smc.config` (the battery driver `CONFIG_MACSMC_POWER` is **off**) and `platform-display.config` (nftables/xtables for ufw, PWM).
- **Stage-1 systemd drop-ins:** ignore lid, power key and idle, and refuse all sleep until our USB-gadget access is shown to survive resume.
- **Not working:** battery. The upstream `macsmc-power` driver hard-hung natively on FT19 (watchdog reset; cause unproven), so it is removed from this build.

## `ft21-reset-fresh/`: trackpad experiment (separate kernel)
- **`src-dchid-ft21.diff`**: a one-shot, opt-in host AFE reset pulse on SMC `pcIO`, using only the two existing reset values, with the release always sent.
  - It runs only after the firmware has itself requested a reset (`0xa2`) and the start has timed out.
  - It is followed by a fresh firmware image and power-ON only.
  - Only a positive result (trackpad READY) would be informative.
