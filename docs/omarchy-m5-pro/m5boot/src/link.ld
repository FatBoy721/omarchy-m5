/* Position-independent; PC-relative addressing only. bss and stack live INSIDE the file image
 * (as zeros) so the payload appended at _payload never overlaps them. */
ENTRY(_start)
SECTIONS
{
	. = 0;
	_image_start = .;
	.header : { KEEP(*(.header)) }
	.text : { KEEP(*(.text.start)) *(.text .text.*) }
	.rodata : { *(.rodata .rodata.*) }
	.data : {
		*(.data .data.*)
		_bss_start = ALIGN(16);
		*(.bss .bss.* COMMON)
		_bss_end = ALIGN(16);
		KEEP(*(.stackmem))
		_stack_top = .;
	}
	. = ALIGN(64);
	_payload = .;
	/DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) *(.dynamic) *(.dynsym) *(.dynstr) *(.hash) *(.gnu.hash) }
}
