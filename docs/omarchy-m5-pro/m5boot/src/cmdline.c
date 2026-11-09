/* Task 14/17: the kernel command line m5boot builds itself (gz5+):
 *   <base args>[ <iBoot cmdline>] earlycon=m5fb,0x<fb base>,<w>,<h>,<stride>,<bpp>[,<xoff>] panic=0 initcall_debug
 *   ignore_loglevel[ <extra>]
 * Format = spec/inputs.md (task 23 driver; slim v3 adds the optional x-offset field: draw only right of it).
 * No FB (fb == 0): the earlycon argument is left out, the rest is kept. Never truncates silently. */
#include "cmdline.h"

int build_cmdline(char *buf, size_t n, const char *base, const char *iboot,
		  uint64_t fb, uint32_t w, uint32_t h, uint32_t stride, uint32_t bpp, uint32_t xoff, const char *extra)
{
	char ec[112] = "", xo[16] = "";
	if (xoff) m5_snprintf(xo, sizeof xo, ",%u", xoff);
	if (fb) m5_snprintf(ec, sizeof ec, " earlycon=m5fb,0x%llx,%u,%u,%u,%u%s", (unsigned long long)fb, w, h, stride, bpp, xo);
	int l = m5_snprintf(buf, n, "%s%s%s%s panic=0 initcall_debug ignore_loglevel%s%s", base,
			    iboot && iboot[0] ? " " : "", iboot ? iboot : "", ec, extra && extra[0] ? " " : "", extra ? extra : "");
	return l < 0 || (size_t)l >= n ? -1 : l;
}
