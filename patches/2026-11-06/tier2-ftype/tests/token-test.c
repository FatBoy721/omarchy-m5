/* Host check of pmgr-pwrstate fpwm0 token (M5_TOK_BEGIN..END extracted verbatim by run.sh). Single-threaded model:
 * proves the state transitions and the close() return value, not SMP atomicity (that is the kernel atomics). */
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef uint32_t u32;
typedef struct { int v; } atomic_t;
#define ATOMIC_INIT(x) { (x) }
static int atomic_cmpxchg(atomic_t *a, int o, int n) { int r = a->v; if (r == o) a->v = n; return r; }
static int atomic_xchg(atomic_t *a, int n) { int r = a->v; a->v = n; return r; }
static void atomic_set(atomic_t *a, int n) { a->v = n; }
enum { SYSTEM_BOOTING, SYSTEM_RUNNING };
static int system_state;
#define pr_warn(...) printf(__VA_ARGS__)
#define APPLE_PMGR_PS_ACTIVE 0xf
#include "token.inc"
static void reset(void) { m5_fpwm0_tok.v = 0; }
int main(void)
{
	system_state = SYSTEM_BOOTING;  reset();
	assert(m5_pmgr_fpwm0_arm() == -EPERM);              /* boot: never armed */
	assert(!m5_fpwm0_take("fpwm0", 0xf));               /* boot store -> SKIP(ro) */
	system_state = SYSTEM_RUNNING;
	assert(!m5_fpwm0_take("fpwm0", 0xf));               /* runtime, not armed */
	assert(m5_pmgr_fpwm0_arm() == 0 && m5_pmgr_fpwm0_arm() == -EALREADY);
	assert(!m5_fpwm0_take("fpwm0", 0x0));               /* power-off never takes it */
	assert(!m5_fpwm0_take("sio", 0xf) && !m5_fpwm0_take(NULL, 0xf) && !m5_fpwm0_take("fpwm", 0xf));
	assert(m5_fpwm0_take("fpwm0", 0xf));                /* the one store */
	assert(!m5_fpwm0_take("fpwm0", 0xf));               /* deferred retry: SKIP */
	assert(m5_pmgr_fpwm0_close() == true);              /* stored */
	assert(!m5_fpwm0_take("fpwm0", 0xf) && m5_pmgr_fpwm0_arm() == -EALREADY); /* closed for the boot */
	reset(); assert(m5_pmgr_fpwm0_arm() == 0 && m5_fpwm0_take("fpwm0", 0xf));
	m5_fpwm0_nostore();                                 /* recheck refused / already active / read error */
	assert(!m5_fpwm0_take("fpwm0", 0xf) && m5_pmgr_fpwm0_close() == false);
	reset(); assert(m5_pmgr_fpwm0_arm() == 0 && m5_pmgr_fpwm0_close() == false); /* armed, unused */
	assert(!m5_fpwm0_take("fpwm0", 0xf));
	puts("token-test: PASS");
	return 0;
}
