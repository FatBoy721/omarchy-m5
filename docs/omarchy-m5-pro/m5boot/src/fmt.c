#include "util.h"

int m5_vsnprintf(char *buf, size_t n, const char *fmt, va_list ap)
{
	size_t o = 0;
	/* c is evaluated exactly once, even when the buffer is full: the %s loop passes *s++ (task 14 fix: the
	 * old form skipped the side effect on truncation, so a too-long %s looped forever). */
#define PUT(c) do { char c_ = (c); if (o + 1 < n) buf[o] = c_; o++; } while (0)
	for (; *fmt; fmt++) {
		if (*fmt != '%') { PUT(*fmt); continue; }
		fmt++;
		int width = 0, lng = 0;
		while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');
		while (*fmt == 'l') { lng++; fmt++; }
		char tmp[24]; int t = 0;
		unsigned long long v;
		switch (*fmt) {
		case 's': { const char *s = va_arg(ap, const char *); if (!s) s = "(null)"; while (*s) PUT(*s++); continue; }
		case 'c': PUT((char)va_arg(ap, int)); continue;
		case '%': PUT('%'); continue;
		case 'd': {
			long long sv = lng ? va_arg(ap, long long) : va_arg(ap, int);
			if (sv < 0) { PUT('-'); v = -(unsigned long long)sv; } else v = sv;
			do tmp[t++] = '0' + v % 10; while (v /= 10);
			break;
		}
		case 'u': case 'x':
			v = lng ? va_arg(ap, unsigned long long) : va_arg(ap, unsigned int);
			if (*fmt == 'u') do tmp[t++] = '0' + v % 10; while (v /= 10);
			else do tmp[t++] = "0123456789abcdef"[v & 15]; while (v >>= 4);
			break;
		default: PUT('%'); PUT(*fmt); continue;
		}
		while (t < width) tmp[t++] = '0';
		while (t) PUT(tmp[--t]);
	}
	if (n) buf[o < n ? o : n - 1] = 0;
	return (int)o;
#undef PUT
}

int m5_snprintf(char *buf, size_t n, const char *fmt, ...)
{
	va_list ap; va_start(ap, fmt);
	int r = m5_vsnprintf(buf, n, fmt, ap);
	va_end(ap);
	return r;
}
