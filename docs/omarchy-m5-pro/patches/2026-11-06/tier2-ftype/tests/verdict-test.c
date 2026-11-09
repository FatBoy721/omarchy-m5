/* Host check of m5_kbdlight fpwm0_verdict(): extracted verbatim between M5_VERDICT_BEGIN/END by run.sh <tree>. */
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
typedef uint32_t u32;
#define BIT(n) (1u << (n))
#define PS_ACT(w) (((w) >> 4) & 0xf)
#define PS_TGT(w) ((w) & 0xf)
#define PS_NOT_PLAIN (BIT(31) | BIT(28) | BIT(12) | BIT(11) | BIT(10))
#define PS_BAD 0xffffffffu
enum { V_ON, V_FORCE, V_REFUSE };
#include "verdict.inc"
int main(void)
{
	u32 sio_on = 0xff;
	assert(fpwm0_verdict(0x000000ff, sio_on) == V_ON);
	assert(fpwm0_verdict(0x100000ff, sio_on) == V_ON);           /* on under auto-PM: mode 1, no store */
	assert(fpwm0_verdict(0x00000000, sio_on) == V_FORCE);        /* plainly power-gated */
	assert(fpwm0_verdict(0x00000344, sio_on) == V_FORCE);        /* clock-gated, W1C flags set: ok */
	assert(fpwm0_verdict(0x1000000f, sio_on) == V_REFUSE);       /* auto-gated (target on, auto): hang class */
	assert(fpwm0_verdict(0x00000800, sio_on) == V_REFUSE);       /* busy */
	assert(fpwm0_verdict(0x80000000, sio_on) == V_REFUSE);       /* reset */
	assert(fpwm0_verdict(0x00001000, sio_on) == V_REFUSE);       /* ps reset */
	assert(fpwm0_verdict(0x00000400, sio_on) == V_REFUSE);       /* dev disable */
	assert(fpwm0_verdict(0x00000000, 0x0) == V_REFUSE);          /* parent off */
	assert(fpwm0_verdict(0x00000000, PS_BAD) == V_REFUSE);
	assert(fpwm0_verdict(PS_BAD, sio_on) == V_REFUSE);
	puts("verdict-test: PASS");
	return 0;
}
