/* m5_ps_ro() allow-list matching, copied from patch 0002 (keep in sync). cc -o t m5-pmgr-allow-test.c && ./t */
#define _GNU_SOURCE
#include <string.h>
#include <assert.h>
#include <stdbool.h>
static char m5_pmgr_allow[256]; static bool m5_pmgr_ro = true;
static bool ro(const char *n){ const char *p = m5_pmgr_allow; size_t len;
	if (!m5_pmgr_ro) return false; if (!n) return true; len = strlen(n);
	while (*p) { if (!strncmp(p, n, len) && (p[len] == ',' || p[len] == '\0')) return false;
		p = strchrnul(p, ','); if (*p) p++; } return true; }
int main(void){ strcpy(m5_pmgr_allow, "atc0_common,atc0_usb_aon,atc0_usb,atc0_phymxwrap");
	assert(!ro("atc0_usb")); assert(!ro("atc0_usb_aon")); assert(!ro("atc0_common")); assert(!ro("atc0_phymxwrap"));
	assert(ro("atc0")); assert(ro("atc0_us")); assert(ro("atc1_usb")); assert(ro("ans")); assert(ro(NULL));
	m5_pmgr_allow[0] = 0; assert(ro("atc0_usb")); return 0; }
