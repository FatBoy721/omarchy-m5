/* m5boot entry. iBoot enters at image offset 2048 (kmutil --entry-point 2048) with x0 = boot_args,
 * MMU off (AsahiLinux/docs fw/macho-boot-protocol.md; spec H1 for --raw). EL1 or EL2 (spec H2).
 * Code is position-independent (load address unknown, spec §1). */
#ifdef PROBE
#include "early.inc"
#endif
/* Task 11 addendum (beacon3): stage word in .data (NOT bss: the bss clear comes after stage 4). Clobbers x9/x10. */
#ifdef BEACON
	.macro STAGE n
	adr	x9, beacon_stage
	mov	w10, #\n
	str	w10, [x9]
	.endm
	.section .data
	.balign 4
	.global beacon_stage
beacon_stage:
	.word 0
#else
	.macro STAGE n
	.endm
#endif
	/* Task 07 H-ENTRY: every word of the 0x800 header is a PC-relative `b _start`, so execution starting at
	 * offset 0 (or anywhere in the pad) still reaches the real entry at 0x800. */
	.section .header, "ax"
	.rept 512
	b	_start
	.endr

	.section .stackmem, "aw", %progbits
	.balign 16
	.space 0x10000

	.section .text.start, "ax"
	.global _start
_start:
	/* Task 11: MMU-off FIRST. Nothing here touches MMIO, the FB or memory until M/C are clear: iBoot may enter
	 * with the MMU on and MMIO unmapped (PM hypothesis for the silent black halt). x21 keeps the entry SCTLR. */
	msr	daifset, #0xf		/* mask all interrupts (booting.rst) */
	mov	x19, x0			/* boot_args */
	STAGE	0			/* offset-0 branch landed */
	adr	x22, _start		/* entry PC */
	STAGE	1			/* SCTLR/CurrentEL read */
	mrs	x20, CurrentEL
	lsr	x20, x20, #2
	cmp	x20, #2
	b.eq	1f
	mrs	x21, sctlr_el1
	b	2f
1:	mrs	x21, sctlr_el2
2:	STAGE	2			/* MMU-off sequence */
	mov	x23, #5			/* test: M (bit0) | C (bit2); x23 is callee-saved and unused by the cache routine */
	tst	x21, x23
	b.eq	3f
	/* MMU/D-cache on: clean+invalidate the D-cache by set/way (all levels from CLIDR), then clear M, C and I,
	 * keeping every other bit (RES1, EE, ...) as found. I is cleared too (task 11) and the I-cache invalidated.
	 * Set/way is BEST-EFFORT: it covers the PE's architected caches only, not system-level caches
	 * beyond them (ARMv8 ARM: set/way ops are not for coherency with other agents / PoC beyond the PE).
	 * HYPOTHESIS H-ID: the mapping is identity (otherwise turning the MMU off moves PC). */
	bl	dcache_clean_inv_all	/* uses x0-x11 only; ends with dsb sy; isb */
	mov	x24, #0x1005		/* M | C | I */
	bic	x0, x21, x24
	cmp	x20, #2
	b.eq	4f
	msr	sctlr_el1, x0
	b	5f
4:	msr	sctlr_el2, x0
5:	isb
	ic	iallu
	dsb	sy
	isb
3:
#ifdef PROBE
	/* Task 05 probe, now AFTER the MMU is off: (1) our own vectors, so a fault reports instead of going to
	 * iBoot's; (2) the one allowed WDT write at the hard-coded PA (spec §4/§5 [OURS], our ADT dump). */
	STAGE	3			/* VBAR set */
	adr	x9, probe_vectors
	cmp	x20, #2
	b.eq	1f
	msr	vbar_el1, x9
	b	2f
1:	msr	vbar_el2, x9
2:	isb
	STAGE	4			/* WDT disable */
	EARLY_WDT			/* the one WDT write (src/early.inc) */
	msr	daifclr, #4		/* unmask SError so a bad access is reported, not left pending */
#endif
#ifdef VM
	ldr	x19, =VM_BOOTARGS
#endif
	adr	x1, _stack_top
	mov	sp, x1
	adr	x1, _bss_start
	adr	x2, _bss_end
6:	cmp	x1, x2
	b.hs	7f
	str	xzr, [x1], #8
	b	6b
7:	mov	x0, x19
	mov	x1, x20
	mov	x2, x21
	mov	x3, x22
#ifdef PROBE
	mov	x4, x24
	mov	x5, x25
#endif
	bl	main
8:	wfe
	b	8b

/* Clean+invalidate every data/unified cache level to PoC by set/way (ARMv8 ARM, CLIDR/CCSIDR walk). */
	.global dcache_clean_inv_all
dcache_clean_inv_all:
	mrs	x0, clidr_el1
	ubfx	x3, x0, #24, #3		/* LoC */
	cbz	x3, 9f
	mov	x10, #0			/* level << 1 */
1:	add	x2, x10, x10, lsr #1	/* 3 * level */
	lsr	x1, x0, x2
	and	x1, x1, #7		/* cache type at this level */
	cmp	x1, #2
	b.lt	8f			/* no data cache */
	msr	csselr_el1, x10
	isb
	mrs	x1, ccsidr_el1
	and	x2, x1, #7
	add	x2, x2, #4		/* log2(line bytes) */
	ubfx	x4, x1, #3, #10		/* max way */
	clz	w5, w4			/* way shift */
	ubfx	x7, x1, #13, #15	/* max set */
2:	mov	x9, x4
3:	lsl	x6, x9, x5
	orr	x11, x10, x6
	lsl	x6, x7, x2
	orr	x11, x11, x6
	dc	cisw, x11
	subs	x9, x9, #1
	b.ge	3b
	subs	x7, x7, #1
	b.ge	2b
8:	add	x10, x10, #2
	cmp	x3, x10, lsr #1
	b.gt	1b
9:	dsb	sy
	isb
	ret

/* dcache_civac_range(start, len): clean+invalidate by VA to PoC (booting.rst: "by VA"). */
	.global dcache_civac_range
dcache_civac_range:
	mrs	x3, ctr_el0
	ubfx	x3, x3, #16, #4
	mov	x2, #4
	lsl	x2, x2, x3		/* DminLine bytes */
	add	x1, x0, x1
	sub	x3, x2, #1
	bic	x0, x0, x3
1:	dc	civac, x0
	add	x0, x0, x2
	cmp	x0, x1
	b.lo	1b
	dsb	sy
	ret

/* jump_kernel(entry, dtb): I-cache invalidate, then x0=dtb, x1-x3=0 (booting.rst). Never returns. */
	.global jump_kernel
jump_kernel:
	msr	daifset, #0xf		/* booting.rst: DAIF masked (the probe unmasked SError) */
	ic	iallu
	dsb	sy
	isb
	mov	x4, x0
	mov	x0, x1
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	br	x4

/* dcache_ivac_range(start, len): invalidate by VA to PoC, discarding any stale (dirty) lines BEFORE we
 * write the range with the MMU off, so a later clean can't overwrite our data with old contents.
 * Callers pass cache-line-aligned starts; the last partial line is invalidated whole. */
	.global dcache_ivac_range
dcache_ivac_range:
	mrs	x3, ctr_el0
	ubfx	x3, x3, #16, #4
	mov	x2, #4
	lsl	x2, x2, x3
	add	x1, x0, x1
	sub	x3, x2, #1
	bic	x0, x0, x3
1:	dc	ivac, x0
	add	x0, x0, x2
	cmp	x0, x1
	b.lo	1b
	dsb	sy
	ret

	.global read_sctlr
read_sctlr:
	mrs	x0, CurrentEL
	cmp	x0, #8
	b.eq	1f
	mrs	x0, sctlr_el1
	ret
1:	mrs	x0, sctlr_el2
	ret

	.global read_cntfrq
read_cntfrq:
	mrs	x0, cntfrq_el0
	ret

#ifdef PROBE
/* 16 entries x 0x80, table 2 KiB aligned (ARMv8 VBAR). Every entry -> probe_exc_entry(kind). Never eret. */
	.balign	2048
probe_vectors:
	.irp	k, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
	.balign	0x80
	mov	x0, #\k
	b	probe_exc_entry
	.endr
probe_exc_entry:
	msr	daifset, #0xf
	/* Task 11: make sure M/C/I are clear before the handler touches MMIO or the FB (already true after entry). */
	mov	x5, #0x1005
	mrs	x4, CurrentEL
	cmp	x4, #8
	b.eq	6f
	mrs	x6, sctlr_el1
	bic	x6, x6, x5
	msr	sctlr_el1, x6
	b	7f
6:	mrs	x6, sctlr_el2
	bic	x6, x6, x5
	msr	sctlr_el2, x6
7:	isb
	cmp	x4, #8
	b.eq	1f
	mrs	x1, esr_el1
	mrs	x2, elr_el1
	mrs	x3, far_el1
	b	2f
1:	mrs	x1, esr_el2
	mrs	x2, elr_el2
	mrs	x3, far_el2
2:	adr	x5, _stack_top		/* fresh stack: covers SP faults */
	mov	sp, x5
	bl	probe_exception		/* paints + halts; never returns */
3:	wfe
	b	3b

	.global read_vbar
read_vbar:
	mrs	x0, CurrentEL
	cmp	x0, #8
	b.eq	1f
	mrs	x0, vbar_el1
	ret
1:	mrs	x0, vbar_el2
	ret
#endif
