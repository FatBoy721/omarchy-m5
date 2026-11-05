/* 8x16 text console on a linear 32bpp framebuffer. White on black.
 * HYPOTHESIS: pixel format is x8r8g8b8; 0xffffffff/0 are white/black in any 32bpp order. */
#include "fb.h"
#include <string.h>

#ifndef FB_SCALE
#define FB_SCALE 1	/* pixel replication; the probe build uses 2 (8x16 is ~0.8 mm tall on a 3024 px panel) */
#endif
#define CW (8 * FB_SCALE)
#define CH (16 * FB_SCALE)

extern const unsigned char font8x16[95][16];

static void clear_row(struct fb *fb)
{
	for (uint32_t y = 0; y < CH; y++)
		memset((char *)fb->base + (size_t)(fb->row * CH + y) * fb->stride, 0, fb->width * 4);
}

void fb_init(struct fb *fb, uintptr_t base, uint32_t w, uint32_t h, uint32_t stride)
{
	fb->base = (volatile uint32_t *)base;
	fb->width = w; fb->height = h; fb->stride = stride;
	fb->col = fb->row = 0;
	if (h >= CH) clear_row(fb);
}

static void glyph(struct fb *fb, char c, uint32_t cx, uint32_t cy)
{
	const unsigned char *g = font8x16[(c < 0x20 || c > 0x7e) ? '?' - 0x20 : c - 0x20];
	for (int y = 0; y < CH; y++) {
		volatile uint32_t *p = (volatile uint32_t *)((uintptr_t)fb->base + (size_t)(cy * CH + y) * fb->stride) + cx * CW;
		for (int x = 0; x < CW; x++)
			p[x] = (g[y / FB_SCALE] & (0x80 >> (x / FB_SCALE))) ? 0xffffffff : 0;
	}
}

void fb_putc(struct fb *fb, char c)
{
	uint32_t cols = fb->width / CW, rows = fb->height / CH;
	if (!cols || !rows) return;
	if (c == '\n') { fb->col = 0; fb->row++; }
	else {
		glyph(fb, c, fb->col, fb->row);
		if (++fb->col >= cols) { fb->col = 0; fb->row++; }
	}
	if (fb->row >= rows) fb->row = 0;	/* wrap, no scroll: scrolling MBs of uncached FB is slow */
	if (fb->col == 0) clear_row(fb);	/* clear the line we're about to write */
}

void fb_puts(struct fb *fb, const char *s) { while (*s) fb_putc(fb, *s++); }

void fb_rect(struct fb *fb, uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t c)
{
	for (uint32_t j = y; j < y + h && j < fb->height; j++)
		for (uint32_t i = x; i < x + w && i < fb->width; i++)
			((volatile uint32_t *)((uintptr_t)fb->base + j * fb->stride))[i] = c;
}
