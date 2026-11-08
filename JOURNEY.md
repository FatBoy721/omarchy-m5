# Journey: every build and what it did on the Mac

**Latest result (2026-11-08): all 15 CPUs online in native Omarchy, strict USB SSH and a rendered SDDM/Hyprland desktop.** The owner is testing the software-rendered desktop past the old 900-second guard deadline. The refreshed-stub/public m1n1 split-payload path is now the CPU profile; GPU acceleration remains unverified. [Current status and artifact identity](STATUS-2026-11-08.md).

## 2026-11-08 — 15-CPU desktop milestone

- The owner completed the 26C5035r stub refresh/enrollment. A fixed public-source-derived stage1 now reads a small ESP stage2, which loads separate kernel/DTB/initrd files through the public storage path.
- A monolithic candidate was rejected with `chainload: image span overlaps the live heap`; the guard was retained. A small split-payload loader then reached Linux with all 15 CPUs.
- That first Linux boot still admitted a legacy rootfs guard at its 900-second deadline. Per-boot masks were moved to `/run/systemd/system.control`, and the actual systemd resolver confirmed they override the regular `/etc` units. The current ten legacy M5 units are masked/inactive; the desktop continued beyond that deadline.
- Standard EEM-only USB, strict SSH, graphical startup and a rendered desktop were verified. The current profile reports 24 GiB physical RAM / 22.79 GiB Linux MemTotal and a 1 TB NVMe with the 120 GB ext4 root mounted RW. New-profile memory/I/O performance qualification is still pending.
- GPU kernel/DTB and Mesa `043a4c5` inputs are prepared; the isolated native Mesa build is in progress. No native GPU probe/rendering result is claimed, and this CPU milestone introduces no GPU/DVFS test.

## Earlier logbook

All on 2026-11-04 (US Eastern) unless noted; times are commit times of the build. Hashes are SHA-256 of the boot object (`m5boot*.bin`) as installed with `kmutil`. Labels: **NATIVE** (on our J714s), **INVALID** (claimed, later found never installed), **VM**, **PENDING**. Photos and videos of the screen are summarized as text; none are published.

## Before m5boot ran
| Time | Build | sha256 | What changed | Native outcome | Label |
|---|---|---|---|---|---|
| 17:26 | m5boot (first) | `039adce60427abf1d121ba321409c5132caecbf0f599c8fb5a872abdd09cbe55` (49,034,128 B) | First full boot object (shim + DTB + Linux + initramfs) | Apple logo, then power-off ×5, then Recovery. macOS panic report: **iBoot panic after the `fuos` image load**; PanicMedic sent it to Recovery after 5 | NATIVE |
| 19:42 | m5boot-gz | `dfab8d046940ce22f7a4af60bbfd36115c0c362c20645ef2871b3a3ec46e86fb` (18,893,904 B) | Compressed payload (Image.gz) | Same loop at the same boot stage. The stored fuOS object is our file byte-for-byte inside IMG4/IM4P `fuos` (report 16) | NATIVE |
| 19:58 | probe (192 KB) | `b3dbc9620427b390188b31401f107cf53b01f9cea8ded34d650cf85a83c35586` | Tiny probe image | **Also panicked**: size is not the cause | NATIVE |

## The fast-cycle detour (results later retracted)
| Time | Build | sha256 | What changed | Claimed outcome | Label |
|---|---|---|---|---|---|
| 20:35 | probe2 | `67223e7071f0faf59b14090b226d82a8c4429915403db750e93af3b7590131fc` | Branch header at offset 0, padded to 16 KiB | "no panic, black screen", read as "entry at offset 0 confirmed" | **INVALID** |
| 20:51 | gz2 | `df5f8d41bf4217466a7773689cab5ff125b9d2270a2a22ae481c28e87537b512` | Slim kernel payload (5.4 MB) | "runs, black screen" | **INVALID** |
| 20:59 | beacon | `11e5d666a4158b12bc9ca0cbb102186281fd18e5bbb7f64176ff8faf327b99f1` | Watchdog-timed reset beacon (no screen needed) | "reset after ~10 s" | **INVALID** |

**Retraction (21:25):** the owner's photo showed the fast re-arm script printing "This is not the recoveryOS paired with Omarchy … Press enter to shut down" on every cycle. kmutil never ran, so none of these were installed; the "black screen" was the shutdown. Cause: 1TR follows the *default* startup disk, and the fast script had kept macOS as default and dropped the stub re-bless. Fixed by re-blessing like the original step2 (m5-omarchy report 18). From then on a result only counts after checking the stub's stored kernelcache changed.

## m5boot runs
| Time | Build | sha256 | What changed | Native outcome | Label |
|---|---|---|---|---|---|
| 21:19 | beacon3 | `b40d853284ef39ec13f2721c99efc983c36ae09ba2579820b090ec1303ac4ed8` | MMU-off first, stage-coded beacon, early green paint; header: branch at 0 + 16 KiB pad | **Screen painted GREEN** on stub firmware mBoot-18000.161.10 (macOS 26.6.2), installed via finish-install. First code of ours to run. The stock-image iBoot panic is avoided by this header | NATIVE |
| 21:24 | gz3 | `f689052a9a1a84c851d0bd43a66ce23bb0f08ce0fc1c7ddb9645066e8cfc5385` | Slim payload + console | Console on screen. Entry at EL2 with MMU/caches off (SCTLR_EL2 0x30000180), boot_args revision 3, FB 0x105d3110000 3024×1964 stride 12096 30 bpp (equals ADT /vram). Then "no room to inflate" | NATIVE |
| 21:55 | gz4 | `09a4a35004b0c9450357dda5ec1eba7203251216482893b691c667c4f4c461dc` | Drop the carveout that equals the kernel RAM window | Steps 1–6 and the jump: inflate 3.1→7.9 MB, kernel/FDT/initrd placed. Then frozen on m5boot's text and a reboot: Linux died before fbcon | NATIVE |
| 22:14 | gz5 | `3bceded200788f7dae2e68179505f9021ea63e4acc6cbf04c13f5b71e5b05aa7` | Kernel with our framebuffer earlycon (`earlycon=m5fb`), panic=0 | **Linux 7.2 booted natively**, log on screen; **SError** right after the MTP DART probe; the panic stayed on screen | NATIVE |
| 22:22 | gz6 | `21d62e37ba3dccfd247dba027e6224153bc13cb136812371466126503a07435d` | DT: MTP and USB1/2 off, USB0 bound to its power domain | Reached userspace: `Run /init`, `=== m5 initramfs ===`, shell on tty0. USB never enumerated (USB0 DART -110). **Reset ~45 s later while idle** | NATIVE |
| 22:36 | gz7 | `786359c9ca01769f917eacc6f50afb7e278f7b23dac43cd8bcd8d6fc42d81bdc` | Dump + disable every armed watchdog in the main WDT block | Still reset at the same point, so a plain main-block WDT was ruled out | NATIVE |
| 22:42 | gz8 | `c6d66c70525019111cae82ed5f7726900cf231d3d39c172ee3bc1fe32e053ba1` | Slim v3 + static framebuffer node + ESP log (opt-in) | Linux ran, but no log appeared on the ESP. **Bug:** the logger used `sfdisk`, which in the initramfs couldn't load its shared libraries, so it found no ESP | NATIVE |
| 23:13 | gz9 | `0c2fe5f40d8a03e0e405be93d1a7bbed7d3371afe630684640967d506cac169a` | New logger: own GPT reader, raw channel on disk0s5 + verified FAT32 mount; read-only PMGR (`m5_pmgr_ro`) + DTB C | **First camera-free log** (`logs/native-gz9-m5log-raw.txt`, which ends at uptime ~77 s | NATIVE |
| 23:27 | gz10 | `b23bf78bed1ec702a4d7e5ef3ec34e5441174e82d6065e2c672889d7890c1f0d` | Clear the secondary watchdog word at 0x2_8833_0008 (ADT wdt reg[2]; lead from betizzel's agent, see README) | It read **0x7c** (armed) before the clear (`m5.wdt2=0x7c,0x0`). **No reset**: log to uptime 264 s (`logs/native-gz10-m5log-raw.txt`) | NATIVE |
| 23:44 | gz11 | `8b7ec61b902780dbe571892e2d46f08b47fe82012bd75a3054ab41e8d4cb1806` | Desktop kernel + `m5.root=s5` → switch_root into the Omarchy rootfs on disk0s5 | VM: initramfs → switch_root → systemd → SDDM → Hyprland | VM; native PENDING |
| 23:46 | gz12 | `10345b69044fe8b37a07349a1a721c51229b70bbaee29e2f0039f07f0d6da600` | DTB I1: internal keyboard/trackpad (MTP) back on, trackpad firmware in the initramfs | — | PENDING |
| 23:56 | gz13 | `d77ffc4db38bd59aa07a44a074c34de1362880759748c14d2a058758a5b57fe9` | DTB U1 + `m5_pmgr_allow=` ATC0 chain: USB0 power experiment (no PHY bring-up yet) | — | PENDING |

## Mistakes worth remembering
- **The fast-cycle results (probe2, gz2, beacon) were never installed.** See the retraction above.
- **A wrong framebuffer address.** betizzel's early kernel patch painted progress markers at a fixed address from *their* machine (0x10bd3110000; it sits 24 GiB above ours, which fits a larger-RAM machine: our arithmetic, unconfirmed). On our 24 GB machine that's not the panel. We disabled those markers (report 14); the real FB (0x105d3110000) comes from boot_args, and natively it equals the ADT /vram region (gz3).
- **`cttyhack`.** Alpine's static busybox has no `cttyhack`, so the first `/init` exited and the kernel panicked "Attempted to kill init". /init now respawns a console shell forever (report 14).
- **The sfdisk logger bug** (gz8): above. The logger now reads the GPT itself with dd/od.
- **The secondary watchdog** (gz6–gz9 idle reset): not in the main WDT block. ADT wdt reg[2] = 0x2_8833_0008 read 0x7c; clearing it ended the resets (gz10).
- **A hypothesis ranking that flipped:** report 19 ranked "26.6.x stub firmware can't boot raw images" first. The retracted probe2 seemed to refute it, then beacon3 really did. The cause was the image header, not the firmware.

## Firmware and machine facts (NATIVE)
macOS 26.6.2, system and stub firmware mBoot-18000.161.10, 24 GB, FileVault on. Stub cloned from the host install with betizzel's `prep-stub.sh`. disk0s5 = 120,000,000,000 B Linux partition; disk0s4 = 499,998,720 B FAT32 ESP; 4096-byte logical blocks.

| gz12 | 2026-11-05 00:03 | `10345b69…` | desktop kernel + DTB I1 (MTP on) + m5.root=s5 | **Omarchy desktop booted natively**: SDDM autologin → Hyprland, 302 s, no reset. MTP -62 → no keyboard/trackpad | NATIVE |
| gz13 | 2026-11-05 | `d77ffc4d…` | gz12 + DTB U1 + ATC0 power allow-list (USB power test) | built, not booted yet | — |
| gz14 | 2026-11-05 00:30 | `b786e82e…` | input-v2 kernel (MTP cold-restart) + rootfs v3 (input logs) | desktop OK; MTP `CPU_CONTROL at probe: stopped` → -62 → no keyboard | NATIVE |
| gz15 | 2026-11-05 01:10 | `c726bebc…` | loader (kexec) + apple_wdt + watchdog daemon + DTB I3 (MTP fw reserved-mem) | desktop OK; MTP still -62; kexec `EBUSY` → fell back to desktop (owner power-cycled) | NATIVE |
| guard | 2026-11-05 02:02 | `ca7eb95b…` | m5drop guard: reboot 15 min after sddm unless ESP/m5stay | fired at 925 s, Mac back in macOS unattended | NATIVE |
| gz16 | 2026-11-05 02:30 | `7a2d134f…` | loader `nr_cpus=1` (spin-table kexec fix), kexec fail ⇒ reboot | kexec works; test kernel ran and auto-rebooted to macOS; its ESP logs were empty → fixed test initrd v2 | NATIVE |

## 2026-11-05 morning: hands-free loop, Aurora kernel, USB, Wi-Fi, keyboard (gz16 onward)
All results NATIVE unless marked. Reports: `m5-omarchy/reports/29-50`, `wifi-n1-REPORT.md`, raw logs `native-t*/u*.txt`.

| What | Result | Label |
|---|---|---|
| Hands-free loop | macOS pushes Image/initrd/cmdline to ESP `m5next/`, `bless --nextonly`, reboots; gz16 loader kexecs it; guard/watchdog bring the Mac back to macOS; logs read from ESP. See REMOTE-LOOP.md | NATIVE |
| Disk after kexec | needs `m5_pmgr_allow=ans nvme_apple.force_cold_reset=1` (ANS reset) | NATIVE |
| Chain kexec | arm64 `kexec_file_load` ignores `--dtb`; built a CONFIG_KEXEC chain kernel to load our own DTB | in progress |
| Aurora 7.3 kernel (GPL) | boots via the chain after two fixes: AIC at EL2 (don't touch VM_TMR_FIQ_ENA) and a SART t6050 port; disk works | NATIVE |
| Wi-Fi (N1) | chip on apcie port 0 (106b:1901-1903); firmware located on the Mac; PCIe link not up yet. Lesson: never allow-list apcie_* domains genpd can power off as unused (shared with storage) | blocked |
| Keyboard/trackpad (MTP) | firmware sits in MTP SRAM, but its CPU never starts (RUN accepted, CPU_STATUS stays 0x4c); active DART TCRs locked by PROTECT. Next: identity DART mapping via DT before lock | blocked |
| USB ATC0 | power up one domain at a time (genpd path hung), PHY RUN, dwc3 binds, UDC exists, but "not attached" | NATIVE |
| Why USB stayed detached | left-back port (by MagSafe) = Apple DFU port; its USB-C controller hpm0 reports MODE "ADFU" and owns the USB2 pair | NATIVE |
| Port map | left-back = hpm0/ATC0, left-front = hpm1 (USID 0xA)/ATC1 usb-drd1 0x2aa280000, right = hpm2/ATC2 (die 1). u7 targets left-front | NATIVE ADT; u7 pending |

### Mistakes this morning
- A tmux message to a worker was typed but never sent (~25 min lost). Fix: file-based messages + Enter sent separately + verify.
- A wait-for-macOS script parsed `usec` instead of `sec` from boot time (Mac idle 49 min). Fixed.
- Stale ESP logs chosen by FAT mtime (all 1980) → analysed the wrong kernel once. Logs now moved aside before each run and matched by marker.
- A watcher waited for "DONE 49" while the worker printed "DONE 50" (~1 h idle).

## 2026-11-05 midday: every USB (u/h), Wi-Fi (W), keyboard and boot-loader run
All NATIVE on the M5 Pro unless noted. Raw logs: `m5-omarchy/reports/native-u*/h*`, `wifi-n1/logs/`, `keyboard/`. Wi-Fi set notes (diagnosis + predictions): `wifi-n1/sets/*-README.md`.

### USB: device mode (Mac as USB gadget, PC as host)
| Run | Change | Result |
|---|---|---|
| u6 | read hpm0 (left-back port controller) | MODE "ADFU": the left-back port is Apple's DFU port and owns the USB2 pair → use another port |
| u7 | same flow on left-front (ATC1, hpm1) | first ever enumeration on the PC (`1d6b:0104 m5-omarchy`), then `can't set config #1, error -110` |
| u8 / u8p | ECM only + dwc3 tracing / + `iommu.passthrough=1` | same -110 → DART ruled out; trace: ep0 status stage never completes |
| u9 | ACM only + FIFO/debug dump | same -110 (ACM also queues IN data at SET_CONFIGURATION) |
| **u10d** | generic serial (no IN data at config) | **configured** (bConfigurationValue=1): root cause = IN data queued on another EP blocks the ep0 status stage |
| u10e | ECM with deferred notify | still -110 → fix must be in dwc3 (u10f/u10g built) |

### USB: host mode (Mac as host, Pixel 4a phone tethering)
| Run | Change | Result |
|---|---|---|
| h1 | tiny initramfs, dwc3 host on ATC1, dial-out SSH to PM PC | no device; phone not powered (hpm1 asleep, SPMI reads time out) |
| h2 | hpm1 wake_poll (aurora tipd/spmi.c GPL) + SSPS S0 | hpm1 answers: MODE "APP ", S0 OK; still no VBUS |
| h3 | + SWSr/SWDF role swap | STATUS: power role SOURCE, data role DFP; phone briefly offers USB tethering, then drops; no enumeration |
| obs. | owner: tethering prompt appears ~5 s while the kernel is still booting | iBoot/macOS leaves the port working; something early in Linux (suspect: loader kernel's kexec shutdown of ATC1 PMGR domains) turns it off → h4 / gz18 keep ATC1 on |
| macOS | system_profiler | Pixel 4a (18d1:4ee7) on ATC1 bus 0x01000000 at 480 Mb/s: port mapping confirmed |

### Wi-Fi (N1, apcie port 0)
| Run | Change | Result |
|---|---|---|
| N1J | chain kexec_load + our DTB | stage 2 silent: it was the old Image without the AIC fix (not a DTB problem) |
| N1K | chain, current Image + tidied DTB | **stage 2 boots on our DT** |
| W1c | read-only, our node | module binds; PMGR APCIE_SYS_* = target f + AUTO_ENABLE (on-demand, not off) |
| W2 | first port-0 writes | SError reading the PLL while APCIE_PHY_SW clock-gated → watchdog returned to macOS |
| W2b | skip PLL unless PHY_SW on | died right after the lane write (W2c: every individual read after it is fine → timing) |
| W4 | PERST# GPIO 80 + train | 0xa8 enable-ack TIMEOUT |
| W5–W7 | lane tunable; hold APCIE_PHY_SW on; PLL/AUSPMA ADT tunables (44/45 already set by iBoot) | ack still TIMEOUT; storage unaffected |
| W8/W8b | SMC (macsmc) + gP13 key | SMC RTKit works under our kernel; **gP13=…01 powers the N1 (CLKREQ# asserts)** |
| W9 | Asahi port bring-up order | **PORT_STATUS.READY** for the first time |
| W10 | Asahi config + train | **root port config space answers: Apple 106b:100c**; LTSSM stays 0x00 |
| W11 | 6 combos gP13 value × PERST# level | gP13 level 1 = N1 power on; LTSSM 0x00 in all |
| W12 | full RP/port/lane dumps | LTSSM never leaves 0x00 ⇒ controller not running (not "no device") |
| W13 | clear port reset bit 16 (0x82c) | bit cleared, LTSSM still 0x00 |
| W13b/W14 | lane reset bit 4; aurora full disable/enable handshake | running |

### Keyboard / trackpad (MTP)
| Run | Change | Result |
|---|---|---|
| gz17 | m5boot writes DART-mtp bypass pre-Linux | built; the owner's 1TR install did not take (no marker in logs) |
| N1K-DARTMTP | (gz16 still) | MTP CPU_CONTROL RUN by bootloader; RTKit wake -62 |
| N1L-MTPID | Linux-side DART bypass | DART is protect-locked (prot/plock 0x1a) when Linux runs → fix must be pre-Linux (gz18) |

### Process lessons (midday)
- One reboot per question was too slow; runs now carry several hypotheses with predicted log lines.
- A local process kept connecting to the PM listener and jammed the dial-in (fixed: `range=` LAN only).
- Arming finish-install made Omarchy the default boot volume (fixed by re-blessing macOS; arming now always restores the default).
- Reference: the official MIT [omarchy-mac-installer](https://github.com/omacom/omarchy-mac-installer) (M1–M3) is the base for our M5 installer plan: same flow, our m5boot as the boot object.

## 2026-11-05 13:01 — ROOT SHELL ON OMARCHY, NATIVE
The breakthrough came from a reviewer's observation: **u10d** (generic-serial gadget) had already passed USB SET_CONFIGURATION, but nothing was listening on `/dev/ttyGS0`.
**u10s** = u10d + `agetty -a root -L ttyGS0` (runner: `usb/u10s-m5-exp.sh`).
- PC side: `echo "1d6b 0104" > /sys/bus/usb-serial/drivers/generic/new_id` → `/dev/ttyUSB0`.
- First command round trip (`usb/native-root-shell-proof.txt`, NATIVE):
  ```
  PRETTY_NAME="Omarchy"
  Linux m5-j714s 7.2.2-m5slim+ … aarch64
  Apple MacBook Pro (14-inch, M5 Pro, 2026)
  uid=0(root)
  Hyprland --watchdog-fd 4
  ```
- Kept alive by stopping the guard timer, the initramfs autoreboot and the experiment's ExecStopPost reboot (hardware watchdog still fed by systemd).
- `tools/serbridge.sh` + `tools/msh.py`: the serial line is bridged so worker sessions run commands on the Mac live (no reboot per experiment).
- Also this hour: h4 proved the 3-minute guard natively (macOS back 256 s after push) and showed the host-mode gap precisely (hpm1 = SOURCE+DFP, conn usb2/usb3 = 1, but xHCI PORTSC CCS=0 / RxDetect; `irq 39: nobody cared`). W13b/W14/W15: Wi-Fi port reset/enable handshake mapped (reset-assert ack works; enable ack and LTSSM never start; W15's undocumented core read faulted).

Still missing for a usable desktop: internal keyboard/trackpad (MTP), Wi-Fi (N1 link), local networking. Next work happens live over this shell.

## 2026-11-05 13:52 — SSH INTO NATIVE OMARCHY OVER USB-C
- The gadget offers one configuration with **gser + CDC-EEM** (both bulk-only; anything with an interrupt-IN endpoint stalls SET_CONFIGURATION on this controller).
- The first EEM attempts "failed" only on the PC side: `usbserial_generic` (bound by VID:PID) also grabbed the EEM interface, and NetworkManager then dropped the manual address. Fix: `tools/eemfix.sh` (unbind generic from the class 02/0c interface, bind `cdc_eem`) + `nmcli device set usb0 managed no`.
- Result (NATIVE, `usb/native-ssh-proof.txt`): ping 10.55.0.1 at ~0.2 ms, `ssh root@10.55.0.1` → `uid=0(root)`, `PRETTY_NAME="Omarchy"`, 7.2.2-m5slim+.
- Worker sessions reach the Mac through `tools/sshbridge.sh`. All further hardware work (Wi-Fi port experiments, keyboard coprocessor) is now done live, not one reboot per question.
- Boot-loader (gz18) install for the keyboard fix failed 3× (startup-picker boot goes straight to the installed gz16; system-1TR `kmutil` refuses with a local-policy error; re-arming no longer drops into the paired recoveryOS). Under investigation before asking the owner again.

## 2026-11-05, later: FT1–FT9 keyboard bring-up

All results below are **NATIVE** on the J714s. Full details and build hashes: [keyboard status](keyboard/STATUS-2026-11-05.md).

| Run | Change | Result |
|---|---|---|
| FT1 | installed gzft1 gives an instrumented kernel the first MTP start | decoded SID0 read fault at `0x28830c000`; no valid iBoot SID0 table existed, retracting the locked-table theory |
| FT2 | read-only RAM substitute at that IOVA | firmware advances to a write fault at the same address |
| FT3 | read/write RAM substitute, with cache maintenance | full RTKit handshake and `MTP Says Hello`; next fault at GPIO address `0x2881e4050` |
| FT4 | second RAM substitute for the GPIO page | firmware no longer crashes; keyboard ready and multi-touch input registered, not yet usable |
| FT5 | enable `HID_APPLE` and its LED dependencies | keyboard input device registers too; owner reports it does not work, bounded capture records zero events |
| FT6 | matching USB helper modules, dynamic DT support, gser + EEM | root SSH command round trip and file read succeed on the same kernel as the input changes |
| FT7 | opt-in classic transport, avoiding the shared-ring `0x91` timeout | live SSH stays up; a guarded real GPIO pin-20 data-bit change causes `IPD HIDSPI attached`; STM ID query now succeeds |
| SMC S1 | read-only controller driver, no key writes or child drivers | `pcIO` metadata is `hex_`, size 8; identifies the proposed AFE-reset path, does not test it |
| **FT9** | set the same GPIO bit before the first MTP RUN | correct `05ac:0359` controller identity at boot; **owner confirms keyboard typing, very slowly**. Trackpad still fails |
| **FT10** | port PM2 firmware-managed reset from J714c; fix interrupted-sleep guard cancellation | USB root SSH and disarm verified; keyboard device opens. Trackpad AFE image received, then attach fails (`No HINT_L`), startup times out. Still no working trackpad or SMC key writes |

The temporary FT7 GPIO change was restored before reboot. FT9 repeats it at startup only with exact-state and power-state guards. USB SSH is verified on FT9; a permanent unattended reboot cycle is still pending.

Two access lessons from the takeover: the earlier permanent-SSH attempt booted a different kernel build and rejected its USB modules; checking only `uname -r` was insufficient. A separate recovery-staging mistake caused an unintended second kexec. The live-switch preflight now rejects an active `m5next/` set. Neither successful USB setup nor a successful build substitutes for a command round trip.
