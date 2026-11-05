/* Task 14/17 host test: gz5/gz8 kernel command line (native J714s FB values), x offset + extra token, no-FB case,
 * iBoot cmdline join, overflow; plus the fmt.c truncated-%s regression. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "cmdline.h"

int main(void)
{
	char b[512];
	int l = build_cmdline(b, sizeof b, "maxcpus=1 console=tty0", "", 0x105d3110000ULL, 3024, 1964, 12096, 30, 0, 0);
	assert(l == (int)strlen(b));
	assert(!strcmp(b, "maxcpus=1 console=tty0 earlycon=m5fb,0x105d3110000,3024,1964,12096,30 panic=0 initcall_debug ignore_loglevel"));
	/* gz8: x offset 1512 + m5.esplog=1 */
	build_cmdline(b, sizeof b, "a", "", 0x105d3110000ULL, 3024, 1964, 12096, 30, 1512, "m5.esplog=1");
	assert(!strcmp(b, "a earlycon=m5fb,0x105d3110000,3024,1964,12096,30,1512 panic=0 initcall_debug ignore_loglevel m5.esplog=1"));
	build_cmdline(b, sizeof b, "a", "x=1", 0x105d3110000ULL, 3024, 1964, 12096, 30, 0, "");
	assert(!strcmp(b, "a x=1 earlycon=m5fb,0x105d3110000,3024,1964,12096,30 panic=0 initcall_debug ignore_loglevel"));
	build_cmdline(b, sizeof b, "a", 0, 0, 0, 0, 0, 0, 1512, 0);	/* no FB: no earlycon (x offset ignored) */
	assert(!strcmp(b, "a panic=0 initcall_debug ignore_loglevel"));
	assert(build_cmdline(b, 40, "a", 0, 0x105d3110000ULL, 3024, 1964, 12096, 30, 0, 0) == -1);	/* never truncated */
	char s[8];
	assert(m5_snprintf(s, sizeof s, "%s", "0123456789") == 10 && !strcmp(s, "0123456"));
	puts("test_cmdline: ok");
	return 0;
}
