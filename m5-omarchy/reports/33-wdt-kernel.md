# 33 — Watchdog in every kernel/DT (loop v1). Built; VM can't exercise apple_wdt; NATIVE pending

## Artifacts (`~/m5boot/spec/inputs.md` § Loop v1, new filenames)
- `build/loop-v1/Image(.gz)` = input-v2 (patches 0001–0003: m5fb earlycon, PMGR log/ro/allow-list, rtkit-helper cold restart; `strings` confirms `m5_pmgr_ro` and `cold restart`) + `tools/kernel/m5-loop.config`: `WATCHDOG=y WATCHDOG_CORE=y APPLE_WATCHDOG=y WATCHDOG_HANDLE_BOOT_ENABLED=y`.
- `tools/build-slim.sh` still refuses `APPLE_WATCHDOG=y` in non-loop builds, and asserts it in loop builds.
- `build/loop-v1/t6050-j714s-I3W.dtb` = I3 + `&wdt { status = "okay"; }` (`watchdog@28836c000`, `apple,t6050-wdt`, `clocks = <&clkref>` 24 MHz fixed clock, IRQ 721).
- `tools/rootfs/m5drop/etc/systemd/system.conf.d/m5-watchdog.conf`: `RuntimeWatchdogSec=60`, `RebootWatchdogSec=60`.

## `drivers/watchdog/apple_wdt.c` (asahi-wip-7.2 @236788cd), what it does
- **Probe (l.157–196) neither starts nor stops WD1.**
  - It needs the clock (`devm_clk_get_enabled`, l.171).
  - Sets `max_hw_heartbeat_ms = U32_MAX / clk_rate * 1000` (l.183) and `timeout = APPLE_WDT_TIMEOUT_DEFAULT` = 30 s (l.54, l.184).
  - Reads `WD1_CTRL`; **if `RESET_EN` is already set it marks `WDOG_HW_RUNNING`** (l.186–188).
  - Calls `apple_wdt_set_timeout()` (l.191), which **writes `WD1_CUR_TIME = 0` and `WD1_BITE_TIME = clk × timeout`** (l.100–103). That re-arms the countdown value but not `CTRL`.
- **With `HANDLE_BOOT_ENABLED=y`,** the watchdog core pings a HW_RUNNING watchdog from the kernel until userspace opens /dev/watchdog. **m5boot disables WD1 before the jump, so in our chain it is NOT running at probe:** nothing is armed until something opens `/dev/watchdog` (`apple_wdt_start`, l.67–75: `CUR_TIME = 0`, `CTRL = RESET_EN`). Hence the busybox `watchdog` in the initramfs.
- **Max timeout:** ⌊(2³²−1) / 24,000,000⌋ = **178 s** (integer division in l.183, then ×1000 ms). `set_timeout` clamps to it (l.102). 60 s is fine.
- **Restart handler** (l.121–139, priority 128 via `watchdog_set_restart_priority`, l.193): `WD1_CTRL = RESET_EN`, `WD1_BITE_TIME = 0`, `WD1_CUR_TIME = 0`, a read-back to flush, `mdelay(150)` ("can take up to ~120-125ms until the SoC is actually reset"). So `reboot`/`systemctl reboot` resets the Mac immediately. betizzel REPORTED the same, landing back in their stage-1 in ~15 s (report 28 research, summarized).
- **Writes added by enabling it:** WD1 `CUR_TIME`/`BITE_TIME` at probe; `CTRL` on start/stop/restart. All are inside the main WDT block (0x28836c000), the block m5boot already writes. No PMGR/SMC.

## Hand-off for the implementer (loader/test initramfs)
1. As soon as `/dev/watchdog` exists: `watchdog -t 10 -T 60 /dev/watchdog` (busybox 1.37 applet, present in our initramfs-slim). That's a 60 s hardware timeout, pinged every 10 s.
2. **Before `switch_root`: `kill -TERM` it and wait.** busybox's watchdog handles SIGTERM by writing the magic 'V' and closing, which stops WD1. A leftover initramfs process would keep the device open and systemd's `RuntimeWatchdogSec` open would fail with EBUSY.
   - The few seconds until systemd re-opens it are unprotected. [Alternative, not chosen] close without 'V' leaves WD1 counting; with HW_RUNNING set the kernel then keeps pinging it, which hides a hang anyway.
3. **systemd** (m5drop drop-in) opens it with 60 s and pings at half that. A frozen PID 1 or kernel lets it bite after ≤60 s, and the Mac resets to the default startup disk (macOS, per the PM's `bless --nextonly` flow).
4. **Before kexec** (loop design): either stop it the same way, or keep it running. kexec doesn't touch the WDT, so the next kernel's userspace must re-open within 60 s. **That's a 60 s budget for the new kernel + initramfs.**

## Not verified
QEMU virt has no apple_wdt, so none of this ran in a VM. The kernel builds and the config/DT checks pass. First native check: `dmesg | grep -i wdt`, `ls /dev/watchdog*`, `cat /sys/class/watchdog/watchdog0/{timeout,max_timeout,state}`. Expect timeout 30 (60 once opened), max_timeout 178.
