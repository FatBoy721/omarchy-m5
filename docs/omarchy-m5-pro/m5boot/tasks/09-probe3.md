# Task 09 (URGENT): probe3 = first NATIVE foothold, black screen

NATIVE RESULT (probe2, sha 67223e70): NO iBoot panic, NO loop. Power stays on and the screen is BLACK. So H-ENTRY is confirmed: iBoot enters at file offset 0, and our branch header fixed it. Our code runs and halts (WDT off), but it found no FB it trusts.

OBSERVED-BY-US (our own ADT dump of THIS Mac, reports/04-j714s-full.txt via spec): node vram@D3110000, reg = PA 0x105_D311_0000, size 0x57AC000 (91,930,624 B), device_type "vram". This is the boot framebuffer carveout. betizzel 0x10b_D311_0000 has the same low bits on a bigger-RAM Mac. DRAM here = 0x100_0000_0000 + 24 GiB.

Build probe3 (and update gz2 the same way):
1. FB selection order: (a) the boot_args Video base, if it lies inside the vram region of the runtime ADT (/vram reg, translated) and geometry fits; (b) the runtime ADT /vram region with the boot_args geometry; (c) LAST RESORT: the OBSERVED-BY-US vram region 0x105_D311_0000..+0x57AC000 with geometry 3024x1964, stride 3024*4, x2r10g10b10, painting ONLY inside that region (bounded). Record which tier was used on screen.
2. Big font, print: the boot_args raw hex (first 0x180 bytes), every candidate layout decode, physBase/memSize/memSizeActual, the ADT ptr/len and whether it parsed, the vram reg from the ADT, EL/SCTLR, the image load address (adr of _start), and the WDT before/after.
3. Keep everything else (VBAR, WDT, no other writes). Tests: host + QEMU (fake vram region). Publish the hash. End with DONE 09.
