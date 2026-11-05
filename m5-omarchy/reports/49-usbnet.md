# 49: SSH over USB: host-side steps and the persistent drop-in (prepared while u6 runs)

## Host side (work host, cable in the Mac's **left-back** USB-C port, by MagSafe)
1. Once u6's gadget is up, `lsusb` shows **`1d6b:0104 … m5-omarchy`**, and `05ac:f014` (Port DFU Mode) should be gone.
2. Find the new interface: `ip -br link` shows a new `enx…` or `usb0`. The NCM function is usually the first; `cdc_ncm` should appear in `dmesg`. The ECM one is `cdc_ether`.
3. If NetworkManager on the work host grabs it, run `nmcli dev set <if> managed no`.
4. `sudo ip addr add 10.55.0.2/24 dev <ncm-if> && sudo ip link set <ncm-if> up`
   - For ECM instead: `10.55.1.2/24` on the cdc_ether interface, then reach `10.55.1.1`.
5. `ssh -i <private key of build/work.pub> alarm@10.55.0.1`
   - The authorized key is the ed25519 key `build/work.pub` (fingerprint `SHA256:<redacted>`). On the Mac it is installed as `/etc/ssh/m5_authorized_keys` through `sshd_config.d/m5.conf`. **Password login is off.**
   - Use the work host's matching private key: the one `build/work.pub` was taken from. It is not in this repo.
6. **Window:** u6 stays up about 10 minutes. The guard reboots at 15 min after sddm unless `m5stay` is on the ESP.

## Persistent: every Omarchy boot gets SSH over USB
- **Drop-in `tools/rootfs/m5drop-usbnet/`.** Copy its tree onto the ESP's `m5drop/`. Everything is under the m5-drop allow-list (`etc/`, `usr/local/`). It contains:
  - `usr/local/bin/m5-usbnet`: the u6 sequence without the experiment logging. It sends hpm0 `SSPS` S0, powers ATC0 one domain at a time (and stops if a domain doesn't reach f), runs the eUSB2 device PHY with USBCTL = RUN, brings up dwc3 via live DT, binds the NCM + ECM gadget, sets 10.55.0.1/24 and 10.55.1.1/24, and starts sshd. It logs to the journal and kmsg (`m5-usbnet:`).
  - `etc/systemd/system/m5-usbnet.service`: oneshot, RemainAfterExit. It is pulled in by `sddm.service.d/m5-usbnet.conf` (`Wants=`), the same mechanism as m5-exp.
  - `etc/ssh/sshd_config.d/m5.conf` and `etc/ssh/m5_authorized_keys`: key-only login. The key file is copied from `build/work.pub` and is git-ignored.
  - `etc/NetworkManager/conf.d/m5-usbnet.conf`: usb0 and usb1 unmanaged, so NM doesn't remove the static addresses.
  - `usr/local/lib/m5/m5_usb.ko` and `m5_hpm.ko`.
- **Kernel requirement.** The script only acts on the **usb-v1 kernel** (`7.2.2-m5slim+` with configfs). The modules are built for it, and it needs OF_DYNAMIC and the NCM/ECM gadget functions. On any other kernel it logs "skip" and exits 0.
  - So persistence also needs **usb-v1 to be the kernel the normal boot runs**: m5next/ = `build/usb-v1/m5next-u6` contents with a non-test cmdline, or m5boot's default kernel switched to usb-v1. That is an m5boot or PM decision.
- **Only after u6 is confirmed (NATIVE).** Then copy the drop-in to the ESP once, and drop `m5stay` if the guard should no longer apply.
- **Not covered yet:**
  - Hot-unplug and replug: the gadget stays bound, so it should re-enumerate, but that is untested.
  - Suspend.
  - The other two ports.
