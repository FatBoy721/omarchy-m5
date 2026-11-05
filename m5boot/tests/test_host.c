/* Host test for the fb console (pure C). Build: make test */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "fb.h"

static uint32_t pix[32 * 32];	/* 4x2 cells */

int main(void)
{
	struct fb fb;
	fb_init(&fb, (uintptr_t)pix, 32, 32, 32 * 4);
	fb_puts(&fb, "A");
	/* 'A' row 2 = 0x10: only pixel x=3 set */
	assert(pix[2 * 32 + 3] == 0xffffffff && pix[2 * 32 + 2] == 0);
	assert(fb.col == 1 && fb.row == 0);
	fb_puts(&fb, "BCD");		/* wraps to row 1 */
	assert(fb.col == 0 && fb.row == 1);
	fb_puts(&fb, "\n");		/* wrap to row 0, which is cleared */
	assert(fb.row == 0);
	assert(pix[2 * 32 + 3] == 0);	/* old 'A' cleared */
	fb_puts(&fb, "\x01");		/* non-printable -> '?' */
	assert(fb.col == 1);
	puts("test_host: ok");
	return 0;
}
