# 61 — h1: USB HOST rescue initramfs (root shell via USB keyboard, SSH via USB Ethernet)

## Set
- **m5next/ = `build/usb-v1/m5next-h1/`:**
  - Image `e25707ea…`;
  - initrd `5988aa1e…`;
  - cmdline `b24101cf…`, marker `USB-H1`, `m5.autoreboot=900`, **no `m5.root`**, loglevel 4 so the console stays usable.
- **m5drop/:** nothing is needed. h1 never touches the rootfs, so any m5drop on the ESP is ignored.
- **Cable/device:** a USB keyboard and/or a USB Ethernet adapter on the **LEFT-FRONT** USB-C port (Port-USB-C@2). A hub or USB-C dock works too.

## Kernel "usbhost" = usbdbg5 + `tools/kernel/m5-usbhost.config`
- **Host side was already built in:** xHCI-plat, DWC3 dual-role, usbhid/hid-generic.
- **Added, all built in:** hid-apple, usb-storage/UAS + sd, usbnet with cdc_ether/cdc_ncm/cdc_eem/r8152/ax88179_178a/asix, and kexec_file.
- **The dwc3 knobs (u10*) are present and default off;** they are irrelevant in host mode.

## initrd = the u10d initrd + an h1 overlay (`tools/h1/`)
The u10d initrd supplies busybox, dropbear, kexec, the work key, m5-wdt, m5-autoreboot and m5-esp. The overlay replaces `/init` and adds `m5_usb.ko` (`4c0a430f…`, new `drmode=` param) and `m5-kexec`.

**/init does this:**
1. Starts the watchdog daemon (petted forever).
2. Arms `m5-autoreboot` (the 900 s guard; it is the only auto-reboot).
3. Starts a respawning **root `sh` on tty1**, the fb console, so a USB keyboard gives an instant shell.
4. **Powers ATC1 exactly as in u10d:** pon atc1_common/usb/phymxwrap, then `op=dev`, but with the PHY **SIG host bits** (`sig=0x01c1700f`; asahi atc.c `USB2PHY_SIG_HOST = 7<<12`).
5. Runs `dt_nopd drmode=host`, which sets dwc3's `dr_mode` to `"host"` in the live DT, then binds `2aa280000.usb`. dwc3 then creates `xhci-hcd`.
6. Starts **dropbear** on port 22 on all interfaces: key-only, work key, `-s` (no passwords).
7. **Every 5 s:**
   - each new `eth*`, `usb*` or `en*` interface is brought up and tries `udhcpc` (6 tries). If that fails it gets the **static 10.66.0.2/24**;
   - the IPs are **printed big on tty1**; the screen stops repainting once a keyboard is present, so the shell is usable;
   - every 30 s, `m5log/h1-<boot>.txt` is written to the ESP (log, `ip addr`, USB devices, dmesg).
8. **Success = a USB input device OR an IPv4 address.** The guard is then **disarmed** (its sleep and its shell are killed, which is logged), and the ESP log is written.
- **kexec from inside:** `m5-kexec Image [initrd] ["cmdline"]` does `kexec -s -l` (the live FDT is reused), then `m5-wdt stop`, sync and `kexec -e`.

## How to use it (owner / PM)
- **Keyboard:** plug it in → press Enter on the Mac's screen → `#` root shell.
- **Ethernet:**
  1. Watch the screen for `>>>>>> eth0 192.168.x.y/24 <<<<<<`, then `ssh root@<ip>`.
  2. With a direct cable and no DHCP, the work machine sets `10.66.0.1/24` and connects with `ssh root@10.66.0.2`.

## Risks (HYPOTHESIS)
- **VBUS:** hpm1 (SN201202x, APP firmware) must source VBUS to the device. hpm1 reads time out from Linux (u7), so we can't command it. A sink device with its own power, or a **self-powered hub/dock**, avoids the problem. A bus-powered keyboard depends on hpm1's autonomous source role.
- **Host-mode PHY:** the SIG host bits come from aurora/asahi atc.c. The eUSB2 repeater (on the device side, m1n1-style) is untested in host mode.
- **Not tested:** this was not tested in a VM; the hardware path can't be emulated. `sh -n` is clean.

Labels: built, not run.

## Addendum 61b (2026-11-05): phone tethering + owner-approved dial-out
- **Kernel:** adds `rndis_host` (Android), `cdc_subset` and `ipheth` (iPhone) to cdc_ether/cdc_ncm/usbnet. Image `ca23e30b…`.
- **Dial-out:** tethering is NAT, so nothing can connect in. The owner approved this route, and the owner set the PM PC's firewall rule for port 2222.
  - Once any IPv4 address is up, a loop runs forever: `nc -w 10 10.168.168.151 2222 -e /bin/h1-dbi`, then `sleep 3`.
  - `h1-dbi` runs `dropbear -i -s -R`: inetd mode, key-only with the work key, no passwords, and the host key created on first use. dropbearkey is not in the initrd.
  - The target can be overridden with `m5.dial=ip:port`.
  - The state is shown on tty1 (`DIAL-OUT ssh -> … : dialing / failed / session ended`) and in the ESP `m5log/h1-*.txt`.
- **PM PC side:** e.g. `ssh -o ProxyCommand='nc -l -p 2222' root@m5` (listen first, and the Mac dials in within 3 s). Or relay: `socat TCP-LISTEN:2222,reuseaddr TCP-LISTEN:2223,reuseaddr` + `ssh -p 2223 root@127.0.0.1`.
- **Set:** `build/usb-v1/m5next-h1/`: Image `ca23e30b…`, initrd `c9119ce5…`, cmdline `b24101cf…`. **No m5drop needed.**
