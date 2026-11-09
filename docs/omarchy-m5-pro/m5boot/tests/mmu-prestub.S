/* VM-only test pre-stub: turn on an identity-mapped MMU with D/I caches (EL1 or EL2), dirty some
 * cache lines, then enter m5boot at 0x40200800 like iBoot would — exercises start.S's MMU-on path.
 * Identity map, 4K granule, T0SZ=25 (starts at level 1, 1 GiB blocks):
 *   [0,1G) Device-nGnRnE (UART), [1G,3G) Normal WB inner-shareable. */
	.text
	.global _start
/* -DDRAM_ONLY (task 11): map ONLY [1G,2G) (QEMU RAM holding m5boot, boot_args, ADT); leave [0,1G) (UART) and
 * [2G,3G) (the fake WDT 0xbef00000 and FB 0xb8000000) UNMAPPED, and enter at file offset 0 like iBoot does.
 * Reproduces "MMU on at entry, MMIO not mapped": the first MMIO store faults unless m5boot turns the MMU off first. */
_start:
	adr	x0, l1
#ifdef DRAM_ONLY
	str	xzr, [x0]
	ldr	x1, =0x40000705
	str	x1, [x0, #8]
	str	xzr, [x0, #16]
#else
	mov	x1, #0x401			/* block 0 -> 0x0, AttrIdx 0 (device), AF */
	str	x1, [x0]
	ldr	x1, =0x40000705			/* block 1 -> 1G, AttrIdx 1 (normal WB), SH=inner, AF */
	str	x1, [x0, #8]
	ldr	x1, =0x80000705
	str	x1, [x0, #16]
#endif
	dsb	sy
	mov	x1, #0xff00			/* MAIR: attr0 = 0x00 device, attr1 = 0xff normal WB */
	mrs	x2, CurrentEL
	cmp	x2, #8
	b.eq	el2
	msr	mair_el1, x1
	ldr	x1, =(25 | 1 << 8 | 1 << 10 | 3 << 12 | 1 << 23 | 2 << 32)	/* TCR_EL1, EPD1 */
	msr	tcr_el1, x1
	msr	ttbr0_el1, x0
	isb
	tlbi	vmalle1
	dsb	sy
	isb
	mrs	x1, sctlr_el1
	mov	x2, #0x1005			/* M | C | I */
	orr	x1, x1, x2
	msr	sctlr_el1, x1
	isb
	b	go
el2:
	msr	mair_el2, x1
	ldr	x1, =(25 | 1 << 8 | 1 << 10 | 3 << 12 | 2 << 16 | 1 << 23 | 1 << 31)	/* TCR_EL2 (non-VHE), RES1 */
	msr	tcr_el2, x1
	msr	ttbr0_el2, x0
	isb
	tlbi	alle2
	dsb	sy
	isb
	mrs	x1, sctlr_el2
	mov	x2, #0x1005
	orr	x1, x1, x2
	msr	sctlr_el2, x1
	isb
go:
	ldr	x1, =0x46000000			/* dirty some lines in RAM m5boot will later use */
	mov	x2, #0x1000
1:	str	x2, [x1], #8
	subs	x2, x2, #1
	b.ne	1b
	ldr	x0, =0x44000000			/* boot_args */
#ifdef DRAM_ONLY
	ldr	x1, =0x40200000			/* file offset 0 (H-ENTRY) */
#else
	ldr	x1, =0x40200800			/* m5boot entry */
#endif
	br	x1
	.ltorg
	.balign 4096
l1:	.space 4096
