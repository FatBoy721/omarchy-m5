# 62 — hpm1 SPMI timeouts = the ACE3 is asleep → wake_poll; h2; where u10f/u10g are

## (1) Why the hpm1 registers time out (from the u7 log, NATIVE)
- **What fails:** on hpm1 (USID 0xa), the select of MODE (0x03), CMD1, SYSTEM_POWER_STATE, BOOT_STATUS and POWER_STATUS never echoes. Reg 0 stays at 0x00, or at the last selected value 0x1a, for the whole 100 ms poll.
- **What works:** only 0x1a (STATUS `1d 6c 00 10`) and 0x5f (DATA_STATUS `f3 00 00 80`) answer.
- **Comparison:** hpm0 on the DFU port answers everything (u6: MODE `ADFU`).
- **Aurora's GPL driver** (`drivers/usb/typec/tipd/spmi.c` @1edf9d01, `~/m5-n1/linux`, GPL-2.0) documents this case:
  - "A sleeping controller does not answer a select";
  - "An idle controller sleeps after [1000 ms] without register access";
  - "A sleeping ACE3 ACKs commands but returns zeros until it is awake".
  
  Its `sn201202x_wake_poll()` does this: SPMI WAKEUP → poll select(MODE) until the size at 0x1f is non-zero, for ≤ 500 ms, re-sending WAKEUP every 20 tries.
- **Cause (HYPOTHESIS, strong):** hpm1 is in its idle sleep. Our `wake=1` sent a single WAKEUP plus 20 ms with no poll, and u7 didn't even set it.
- **Fix:** `m5_hpm.ko` (`a98532cc…`) now ports `wake_poll`. It runs **automatically** when a quick (10 ms) MODE select fails, or when `wake=1`.

**What puts hpm1 into source/DFP?** (owner: the phone charges on left-back but not on left-front)
- **Aurora's probe** (`tipd/core.c:2912`) first does `switch_power_state(S0)`, i.e. `cd321x_switch_power_state` → **`SSPS` S0** (core.c:1987–1999).
- **Role swaps exist** but are only issued on request: `SWDF`/`SWUF` for data (core.c:425; "on the J613 SN201202x, SWDF/SWUF can stay busy forever") and `SWSr`/`SWSk` for power (core.c:463).
- **HYPOTHESIS:**
  - With SYSTEM_POWER_STATE ≠ S0, i.e. the SoC "off/sleep" as macOS left it at shutdown, the APP firmware doesn't source VBUS.
  - **SSPS S0 is the documented first step**, and it is already pre-approved (task 50: only if MODE == "APP " and not S0).
  - hpm0 sources by default because it runs ADFU (the DFU firmware) on the DFU port.
- **Next, if S0 still doesn't source:** `SWSr` + `SWDF` on hpm1. These need PM/owner approval and are not built.

## h2 = h1 + hpm1 wake + SSPS S0 (built)
- **Push:**
  - m5next/ = `build/usb-v1/m5next-h2/`: Image `ca23e30b…` (the same as h1), initrd `78054a6a…`, cmdline `75c4abe0…` with marker `USB-H2`;
  - **no m5drop**.
- **What changes in /init:** before the ATC1 host bring-up, it runs `m5_hpm op=auto usid=0xa wake=1`. That does wake_poll, the full register dump, and then SSPS S0 if MODE is `APP ` and the state is not S0. The result goes to tty1, the ESP log and dmesg.
- **Everything else as h1:** tethering drivers, DHCP or 10.66.0.2, dial-out to 10.168.168.151:2222, keyboard shell, guard disarm, m5-kexec.
- **The owner checks:** does the phone **charge** on left-front with h2? If it does, VBUS is solved, and the phone should then see a host.

## (2) Device mode: u10f and u10g exist on ush
- `build/` is git-ignored, so these sets live only on ush, at `~/m5-omarchy/build/usb-v1/`:
  - **u10g (recommended, report 60):** `m5next-u10g/` (Image `5b9108c2…`, initrd `6fe015a9…`, cmdline `6dfdc381…`) + `loop/u10g/m5drop/`. It sets all three fixes (no-op START skip, IN hold, ECM defer), then ECM + sshd at 10.55.0.1. Cable: PC ↔ left-front.
  - **u10f:** `m5next-u10f/` (cmdline `5b2e824e…`) + `loop/u10f/m5drop/`. It has the IN hold only, and report 60 predicts it fails.
  - **u10c:** the knob matrix.
- **u10g is unchanged** (still the old m5_hpm), so the device test keeps a single variable.

## Low priority: ATC0 / left-back host (h1 variant)
Not built. hpm0 runs ADFU and owns the USB2 pair (report 50), so the phone gets VBUS there but probably no data. The SS lanes would need the ATC0 USB3 PHY/pipehandler bring-up, which we don't have.

Labels: the u7 register pattern is NATIVE; the sleep diagnosis is HYPOTHESIS backed by aurora's source comments; h2 is built, not run.

## Addendum (task 63, PM 11:25): 3-minute guard for all host/dial images
- **h2 cmdline:** `m5.autoreboot=180`. If nothing connects within 3 min of the initramfs start, it reboots to macOS.
- **The disarm condition changes:**
  - **before:** a keyboard OR any IPv4 address disarmed the guard;
  - **now:** only a **USB keyboard** OR a **live dial-out SSH session** does. A live session means `dropbear -i` is running, i.e. nc reached 10.168.168.151:2222. An IP address alone no longer disarms it.
- **The tty1 banner** shows `guard: armed (3 min unless keyboard or SSH session)`, then DISARMED.
- **h2 now:** `build/usb-v1/m5next-h2/`: Image `ca23e30b…`, initrd `8c1a14f9…`, cmdline `bd29f64b…`. No m5drop.
- **h1 is left as it was** (15 min). It is superseded by h2.

## Addendum (task 64, PM 11:43, pre-approved): h3 = h2 + SWSr / SWDF on hpm1
- **`m5_hpm op=srcdfp`** (`eaaabec8…`) first runs the `auto` path: wake_poll, the dump, and SSPS S0 if MODE is APP and the state is not S0. Then, **only when MODE is `APP `**, after 200 ms:
  1. Read STATUS[0]. The bits are tipd tps6598x.h: bit 0 = plug present, **bit 5 = power role (1 = source)**, **bit 6 = data role (1 = DFP)**. In u7, hpm1's STATUS[0] was 0x1d: plug present, sink, UFP.
  2. If it is still sink, send **`SWSr`**, wait 500 ms and re-read.
  3. If it is still UFP, send **`SWDF`**, wait 500 ms and re-read.
  4. Read POWER_STATUS and DATA_STATUS.
- **How each command runs** (logged before every write): CMD1 must be idle; CMD1 := 4CC; poll ≤ 1 s for 0 or `!CMD`; then the DATA1[0] result (0 = success).
- **Guard against hangs:** aurora notes that SWDF can stay busy forever on J613. The 1 s bound keeps h3 from hanging; a stuck CMD1 is logged as busy.
- **The changes are volatile:** they last until the next reset or replug.
- **h3:** `build/usb-v1/m5next-h3/`: Image `ca23e30b…`, initrd and cmdline as in its SHA256SUMS (marker `USB-H3`, `m5.autoreboot=180`, the same 3-minute guard/disarm as task 63). No m5drop.
- **Visible on tty1 and in the ESP log:** the `hpm1:` line with MODE, awake, SSPS, STATUS[0] (role before and after) and the SWSr/SWDF results.
