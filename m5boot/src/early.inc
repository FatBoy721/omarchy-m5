/* Task 05/06: first instructions of the probe/gz/spin images, before ANY boot_args parsing: the one allowed WDT
 * write at the hard-coded PA (spec §4/§5 [OURS]). w24/w25 = WD1_CTRL before/after. Clobbers x9. No relocations.
 * No paint here (review G1): the FB is painted only after src/probefb.c validates it. */
#ifndef WDT_PA
#define WDT_PA 0x28836C000
#endif
.macro EARLY_WDT
	ldr	x9, =WDT_PA + 0x1c
	ldr	w24, [x9]
	str	wzr, [x9]		/* apple_wdt_stop(): the only WDT write */
	dsb	sy
	ldr	w25, [x9]
.endm
