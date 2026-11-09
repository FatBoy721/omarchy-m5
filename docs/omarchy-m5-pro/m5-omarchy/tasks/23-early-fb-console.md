# Task 23 (URGENT): see Linux's early boot on the screen

**NATIVE (owner, gz4 09a4a350):** m5boot steps 1–6 OK. Inflate 3.1→7.9 MB, kernel at 0x10072c00000, FDT 0x10073400000, initrd 0x10073600000, bootargs `maxcpus=1 keep_bootcon console=tty0 loglevel=8 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0`. The countdown ran, step 7 (the jump) printed, and then the **screen stayed frozen on m5boot's text, and the Mac rebooted** some seconds later. No USB gadget appeared on work. So Linux ran, but died before simpledrm/fbcon showed anything. The reboot suggests a panic with a non-zero panic timeout (restart via the watchdog), but check it.

Do, in our slim kernel (GPL; your tree):
1. **Early framebuffer console:** add an earlycon that renders printk text directly to a linear framebuffer given on the cmdline, e.g. `earlycon=m5fb,0x105d3110000,3024,1964,12096,30` (base, width, height, stride bytes, bpp), or read the DT simple-framebuffer node if that's easy that early. Adapt `drivers/firmware/efi/earlycon.c` (GPL: early_memremap/fixmap, font rendering, scrolling) to take its parameters from the cmdline instead of EFI screen_info. Handle x2r10g10b10 (white = 0x3fffffff). Keep it small and self-contained, as a patch file in our tree.
2. **Make failures stay on screen:** `CONFIG_PANIC_TIMEOUT=0` and `panic=0` in the default cmdline. Check the slim config for anything that reboots on panic/oops (`PANIC_ON_OOPS` is fine as long as the timeout is 0). Make sure no watchdog driver auto-arms (`APPLE_WATCHDOG` built in? `WATCHDOG_HANDLE_BOOT_ENABLED`? Disable it for now).
3. Also add `initcall_debug ignore_loglevel` to the recommended cmdline for this test, and print a marker very early in `setup_arch` (so we see the kernel got that far).
4. Rebuild the slim Image/Image.gz, check it boots in QEMU if possible (VM; earlycon with a fake FB region), and update `~/m5boot/spec/inputs.md` (slim section, new hashes). Tell the PM the exact cmdline m5boot should pass (m5boot knows the FB values at runtime and will build the earlycon string itself).

End with `DONE 23`.
