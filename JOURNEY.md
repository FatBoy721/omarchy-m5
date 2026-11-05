# Journey: every build and what it did on the Mac

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
