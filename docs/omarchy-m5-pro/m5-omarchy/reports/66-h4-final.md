# 66 — h4 (final): ordered bring-up, 1 s hpm/PORTSC trace, real-login guard (VM-proven), guard bug fixed

## Set
- **m5next/ = `build/usb-v1/m5next-h4/`:** Image `ca23e30b…`, initrd `16aedaba…`, cmdline `67eacd45…` (marker `USB-H4`, `m5.autoreboot=180`).
- **No m5drop.**
- **Phone:** the Pixel 4a (18d1:4ee7, RNDIS/NCM tethering) on the **left-front** port. `rndis_host`, `cdc_ncm`, `cdc_ether` and `usbnet` are built into Image `ca23e30b…`. macOS shows the phone on ATC1 at 480 Mb/s (PM, NATIVE), which confirms the port mapping.

## 1. The guard bug behind "h3 never rebooted" (found and fixed, VM-proven)
- **Cause:** `m5-autoreboot` (m5boot) runs `kill ${LOGPID:-0}` just before `reboot -f`. h1–h3 started it **without LOGPID**, so it ran `kill 0`, which killed its own process group. **The guard killed itself right after writing the final ESP snapshot.** In the VM this prints `Terminated` with no reboot (before the fix: `qemu exit 124`).
- **Fix:** `sleep 999999 & LOGPID=$!` gives it a harmless target. It applies to every h image; **h1–h3 have the bug**.

## 2. Disarm only on a real login (PM 12:00)
- **The marker file:** `/etc/profile` touches `/tmp/m5.login`. That file is read only by a **login shell**:
  - an **SSH session after key authentication** (dropbear starts `-sh`);
  - the tty1 shell, which now starts only **after Enter** is read on tty1 (a keyboard).
- **What doesn't count:** a TCP connection to the dial port, or a non-interactive `ssh host cmd`.
- **Rule:** the guard is disarmed only when `/tmp/m5.login` exists. Otherwise there is a hard reboot at 180 s.
- **QEMU proof** (`tools/vmtest/h4-guard-vm.sh`: the vm kernel + virtio-net, the h4 initrd plus a VM-only overlay with this host's test key; the Mac set keeps the work key; `m5.autoreboot` is shortened for the test):

| case | setup | result |
|---|---|---|
| none | nobody listening on the dial port, AR=20 | `qemu exit 0 after 27 s`: rebooted (`m5autoreboot: reboot -f`) |
| jam | socat accepts TCP and never speaks SSH, AR=45 | `qemu exit 0 after 52 s`: **still rebooted** |
| login | real `ssh -tt` over the dial-out (socat listener ProxyCommand), AR=90 | `m5: login shell (… 10.0.2.2 22220 10.0.2.15 …)` → `SUCCESS: guard DISARMED` → `qemu exit 124` at 210 s (no reboot); `VM-LOGIN-OK` echoed |

- **Also checked in the VM:** the direct dropbear and the `nc -e /bin/h1-dbi` dial path both serve SSH (`dropbear_2026.91` banner, command ran).

## 3. Bring-up order and trace (PM 12:12)
- **Order:**
  1. ATC1 pon (common/usb/phymxwrap);
  2. PHY `op=dev sig=0x01c1700f` (HOST SIG bits);
  3. `dt_nopd drmode=host`, then the dwc3 bind (xHCI);
  4. **then** hpm1: `m5_hpm op=read wake=1 persist=1`, followed by **one pass** (wake, SSPS S0 if needed, SWSr if sink, SWDF if UFP).
- **Trace:** every 1 s for 60 s, `trace t+Ns hpm1 [STATUS[0] decode] portsc [xhci debugfs port PORTSC] usb [devices]` goes to kmsg and the ESP log.
- **After that:** every 2 s, the pass is **re-applied only if STATUS has lost the SOURCE role while no device is enumerated**. No blind re-sends.
- **New kick mode:** `m5_hpm` (`8a1c84ad…`) adds `kick=s` (STATUS only, waking the chip if needed) for the trace.
- **Banner:** tty1 and kmsg say `h4 (USB-H4)`.

## 4. Owner's observation: tethering appears ~5 s during the early kernel log (PM 12:13) — HYPOTHESIS
- **What it means:** iBoot/macOS left hpm1 as source/host and ATC1 powered. The phone's options vanish while the **loader** (gz16 → loop-v1 kernel → kexec) shuts down. The owner's photo shows `apple-pmgr-pwrstate … shutdown` for the power-controller domains right before kexec, which would power ATC1 down. hpm1 then drops the attach, and its later sleep leaves STATUS = no connection.
- **Why we can't fix it in the loader:** the loader kernel is m5boot's, and its shutdown runs before our kernel exists. m5next's cmdline applies only to the kexec'd kernel. So h4 does (2) from the PM's list: **it re-powers ATC1 first**, then re-establishes the roles, so the port is fully up before hpm1 negotiates.
- **Proper fix (m5boot; not ours to change):** in the loader kernel, skip the pwrstate shutdown for `atc1_*` (or mark them `apple,always-on`) before kexec. Added to the m5boot questions in this report rather than to their spec, pending the PM.

Labels: guard and login results are VM (QEMU); the h3 role result is NATIVE (PM); §4 is HYPOTHESIS; h4 is built, not run natively.
