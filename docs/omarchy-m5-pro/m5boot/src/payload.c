#include "payload.h"
#include <string.h>

int payload_parse(const uint8_t *h, uint64_t avail, struct payload *p)
{
	if (avail < PAYLOAD_HDR_SIZE) return -5;
	if (memcmp(h, PAYLOAD_MAGIC, 8) || rd32(h + 8) != PAYLOAD_VERSION || rd32(h + 12) != PAYLOAD_HDR_SIZE) return -1;
	uint64_t *f = &p->dtb_off, end = PAYLOAD_HDR_SIZE;
	for (int i = 0; i < 6; i += 2) {
		f[i] = rd64(h + 16 + i * 8); f[i + 1] = rd64(h + 24 + i * 8);
		if (!f[i + 1]) { f[i] = 0; continue; }
		/* caps keep every sum below 2^34: no overflow */
		if (f[i + 1] > PAYLOAD_MAX_BLOB || f[i] < PAYLOAD_HDR_SIZE || f[i] > 4 * PAYLOAD_MAX_BLOB || (f[i] & 63)) return -2;
		if (f[i] + f[i + 1] > end) end = f[i] + f[i + 1];
	}
	if (!p->dtb_size || !p->image_size) return -4;
	uint64_t t = align_up(end, 64);
	if (t + 16 > avail) return -5;	/* review R1: never read the trailer past the end of RAM */
	if (memcmp(h + t, PAYLOAD_TRAILER, 8) || rd64(h + t + 8) != t) return -3;
	/* blobs must not overlap each other */
	for (int i = 0; i < 6; i += 2)
		for (int j = i + 2; j < 6; j += 2)
			if (f[i + 1] && f[j + 1] && f[i] < f[j] + f[j + 1] && f[j] < f[i] + f[i + 1]) return -2;
	p->total = t + 16;
	return 0;
}
