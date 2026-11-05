#pragma once
#include <stdint.h>
struct fb {
	volatile uint32_t *base;	/* linear 32bpp */
	uint32_t width, height, stride;	/* stride in bytes */
	uint32_t col, row;		/* cursor, in cells */
};
void fb_init(struct fb *fb, uintptr_t base, uint32_t w, uint32_t h, uint32_t stride);
void fb_putc(struct fb *fb, char c);
void fb_puts(struct fb *fb, const char *s);
void fb_rect(struct fb *fb, uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t c);
