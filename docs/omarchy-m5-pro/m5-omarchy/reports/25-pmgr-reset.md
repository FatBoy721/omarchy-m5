# 25 — gz6 reset: logging, visibility, the USB/PMP question, an ESP log foothold (VM-tested; NATIVE pending)

The PM addendum (gz6 video) moved the reset to ~45 s **after** the initcalls, while idle. This report follows the revised priorities. Artifacts and hashes are in `~/m5boot/spec/inputs.md` § Slim v3.

## Built
1. **PMGR write log** (`tools/kernel/patches/0002-m5-pmgr-write-log.patch`): `pr_emerg("m5 pmgr: <domain> <op> off=… val=…")` **before** every PMGR register write. That covers set-pre, power-on/off, auto-enable, reset-assert/deassert, probe-min-state and probe-auto-enable. The earlycon now ends each write with `wmb()`, so the line reaches the panel before the next store. If a write resets the SoC, the last line names it.
2. **Visibility:**
   - **Root cause of the missing tty0:** `framebuffer0` in the DT was `status = "disabled"`, `reg = <0 0 0 0>`, "to be filled by loader". Unless m5boot fills and enables it, simpledrm never binds and fbcon has no device.
   - Fix: a static, enabled node in our overrides (gz6 DT + framebuffer, **the recommended DTB**). No power-domains on it: adding display domains means PMGR writes.
   - m5fb's new **x offset**: `…,30,1512` keeps the bootconsole in the right half, so fbcon (left) and `keep_bootcon` don't overwrite each other (VM: 0 pixels in the left half).
   - /init now mirrors to /dev/kmsg. VM run: `m5init: === m5 initramfs ===`, uname, model, the shell banner, all on the earlycon (`build/t23/fb-v3.png`).
3. DTB-A / DTB-B are built (optional, per the addendum). They **lack** the static fb node.

## (3) Why the USB path fails [analysis; source labels kept]
- **ATC0 USB's parent chain** (`ps_atc0_usb` 0x150 → `atc0_common` 0x208 + `atc0_usb_aon` 0x148). [Publish note: a sentence that relied on a research-only decode (not published) was removed here.]
- With gz6's `power-domains = <&ps_atc0_usb>`, genpd powers atc0_common through plain PMGR writes. A PMP-notified domain with PMP not running plausibly never reaches the target state, so the DART probe gets -110 (ETIMEDOUT from `apple_pmgr_ps_set`'s poll). Consistent with the gz6 log; [HYPOTHESIS].
- **`b2bd_afc_0/1`, `b2bd_afr_0/3` are not in the ATC/USB chain.** Their parents/children are only other `b2bd_*` fabric domains (`*_dfx`, `afr_1/2`). They aren't in report 05's notify_pmp list. [guess] They're fabric/die-to-die domains a probe tried to power because of `apple,always-on` or a consumer.
- **Caution reading those lines:** the driver prints `reg` (the value *before* the write), not the polled `cur`, in "Failed to reach power state 0x%x (now: 0x%x)". So "now: 0xd0f" is the pre-write register: target 0xf, actual 0.
- **Is the gadget blocked?** Not necessarily. betizzel's working USB gadget (REPORTED) uses the **same DT without power-domains on dwc3**: ATC0 was already powered, by m1n1's USB proxy or iBoot for the cabled port. In our chain nobody powers it: gz5 had no power-domains and hit the SError on the USB DART read, gz6 had them and got -110. Options, cheapest first:
  - (a) have m5boot **read** the ATC0 USB/COMMON PS registers (0x150/0x208/0x148 in PMGR) and print them: is ATC0 on at hand-off? A read only, within m5boot's limits.
  - (b) if it's off and plain PMGR power-on is refused, USB needs the PMP (report 03), and the gadget is blocked for now.
- **Alternative foothold: the ESP log (built, opt-in `m5.esplog=1`).** NVMe works without PMP so far (ANS is left on by iBoot, report 05). `/bin/m5-esplog` waits for nvme0n1, then picks the **single** partition with the EFI GPT type and size 200–1100 MB, refusing if there are none or two. It mounts it vfat and writes **only** `m5log/boot-N.txt` (dmesg + uptime) at 5/20/60 s and every 60 s after, sync + umount each time. An idle reset still leaves the latest snapshot.
  - Read it from macOS: `sudo diskutil mount disk0s4; cat /Volumes/EFI/m5log/boot-*.txt` (PM: check the ESP's identifier first).
  - **This is a disk write on the Mac (our own ESP), so it needs owner/PM approval before the flag is added.**

## Recommendation for the next boot
gz6+fb DTB + slim v3 Image + initramfs-slim, cmdline from inputs.md, **without** `m5.esplog=1` until approved. Expected: the earlycon (right half) shows the PMGR write log and initcalls, then fbcon (left) shows the shell. If the Mac resets again while idle, the last `m5 pmgr:` line (if any) or the silence tells PMGR apart from a watchdog.
