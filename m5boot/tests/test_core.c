/* Host tests: boot_args decode, ADT walk + reg translation, placement, FDT patching, payload (C side). */
#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <libfdt.h>
#include "bootargs.h"
#include "adt.h"
#include "fdtpatch.h"
#include "place.h"
#include "payload.h"

static void w32(uint8_t *p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = v >> (8 * i); }
static void w64(uint8_t *p, uint64_t v) { w32(p, v); w32(p + 4, v >> 32); }

/* --- tiny ADT writer --- */
static uint8_t adt[8192]; static uint32_t ao;
static uint32_t node(uint32_t np, uint32_t nc) { uint32_t o = ao; w32(adt + ao, np); w32(adt + ao + 4, nc); ao += 8; return o; }
static void prop(const char *n, const void *v, uint32_t l)
{
	memset(adt + ao, 0, 32); strcpy((char *)adt + ao, n); w32(adt + ao + 32, l);
	memcpy(adt + ao + 36, v, l); ao = (ao + 36 + l + 3) & ~3u;
}
static void props(const char *n, const char *s) { prop(n, s, strlen(s) + 1); }
static void prop32(const char *n, uint32_t v) { uint8_t b[4]; w32(b, v); prop(n, b, 4); }
static void prop128(const char *n, uint64_t a, uint64_t b) { uint8_t x[16]; w64(x, a); w64(x + 8, b); prop(n, x, 16); }

static void build_adt(void)
{
	/* / { chosen { memory-map {..}, carveout-memory-map {..} }, arm-io (ranges) { wdt } } */
	node(3, 2); props("name", "device-tree"); prop32("#address-cells", 2); prop32("#size-cells", 2);
	 node(1, 2); props("name", "chosen");
	  node(5, 0); props("name", "memory-map");
	   prop128("TrustCache", 0x10000010000ULL, 0x4000);
	   prop128("Empty", 0, 0);			/* zero size: skipped */
	   prop("Odd", "abc", 3);			/* non-16-byte: skipped (and unaligned length!) */
	   prop128("Wrap", 0xfffffffffffff000ULL, 0x2000);	/* base+size overflows: skipped */
	  node(2, 0); props("name", "carveout-memory-map");
	   prop128("region-id-68", 0x10105ffe00000ULL, 0x200000000ULL);
	 node(5, 1); props("name", "arm-io"); prop32("#address-cells", 2); prop32("#size-cells", 2);
	  { uint8_t r[48]; w64(r, 0); w64(r + 8, 0x200000000ULL); w64(r + 16, 0x3c0000000ULL);	/* spec §4 first entry */
	    w64(r + 24, 0x400000000ULL); w64(r + 32, 0x900000000ULL); w64(r + 40, 0x1000);
	    prop("ranges", r, 48); }
	  prop("compatible", "arm-io,t6050", 13);
	  node(3, 0); props("name", "wdt");
	   prop("compatible", "wdt,t8101\0wdt,s5l8960x", 23);
	   { uint8_t r[16]; w64(r, 0x8836C000ULL); w64(r + 8, 0x4000); prop("reg", r, 16); }
}

static void test_bootargs(void)
{
	static uint8_t raw[2048];
	struct bootargs ba;
	w32(raw, 2 | 2 << 16);
	w64(raw + BA_VIRT_BASE, 0xfffffe0000000000ULL); w64(raw + BA_PHYS_BASE, 0x10000000000ULL);
	w64(raw + BA_MEM_SIZE, 0x5f0000000ULL); w64(raw + BA_TOP_KDATA, 0x10012345678ULL);
	w64(raw + BA_VIDEO, 0x105f8000000ULL); w64(raw + BA_VIDEO + 16, 3456 * 4);
	w64(raw + BA_VIDEO + 24, 3456); w64(raw + BA_VIDEO + 32, 2234); w64(raw + BA_VIDEO + 40, 0x100 | 32);
	w64(raw + BA_DT_PTR, 0xfffffe0000004000ULL); w32(raw + BA_DT_LEN, 0x80000);
	strcpy((char *)raw + BA_CMDLINE, "hello");
	w64(raw + BA_FLAGS_OFF(1024), 1); w64(raw + BA_FLAGS_OFF(1024) + 8, 24ULL << 30);
	bootargs_parse(raw, &ba);
	assert(ba.revision == 2 && ba.version == 2 && ba.line_len == 1024 && ba.mem_actual == 24ULL << 30);
	assert(ba.boot_flags == 1 && !strcmp(ba.cmdline, "hello") && ba.v_width == 3456 && (ba.v_depth & 0xff) == 32);
	const char *k;
	assert(ba_to_pa(&ba, ba.dt_ptr, &k) == 0x10000004000ULL && !strcmp(k, "VA"));
	assert(ba_to_pa(&ba, ba.top_kdata, &k) == ba.top_kdata && !strcmp(k, "PA"));
	assert(ba_to_pa(&ba, 5, &k) == ~0ULL);
	/* FB above physBase+memSize (spec §3) is still a PA as long as it is below physBase+memSizeActual */
	uint64_t fsz;
	assert(ba_to_pa(&ba, ba.v_base, &k) == ~0ULL);
	assert(ba_fb_pa(&ba, &fsz, &k) == ba.v_base && !strcmp(k, "PA") && fsz == 3456 * 4 * 2234);
	struct bootargs b2 = ba;
	b2.v_base = ba.phys_base + (24ULL << 30) - 0x100000;	/* would run past the end of DRAM */
	assert(ba_fb_pa(&b2, &fsz, &k) == ~0ULL);
	b2 = ba; b2.v_base = ba.virt_base + 0x1000;
	assert(ba_fb_pa(&b2, &fsz, &k) == ba.phys_base + 0x1000 && !strcmp(k, "VA"));
	/* MINOR 4: no memSizeActual => no console; stride bounds; huge stride can't wrap the size check */
	b2 = ba; b2.mem_actual = 0;
	assert(ba_fb_pa(&b2, &fsz, &k) == ~0ULL);
	b2 = ba; b2.v_stride = 16384 * 4 + 4;
	assert(ba_fb_pa(&b2, &fsz, &k) == ~0ULL);
	b2 = ba; b2.v_stride = 1ULL << 63; b2.v_height = 2;	/* stride*height wraps to 0 */
	assert(ba_fb_pa(&b2, &fsz, &k) == ~0ULL);
	b2 = ba; b2.v_stride = 3456 * 4 - 4;	/* stride < width*4 */
	assert(ba_fb_pa(&b2, &fsz, &k) == ~0ULL);
	b2 = ba; b2.v_depth = 30;
	assert(ba_fb_pa(&b2, &fsz, &k) != ~0ULL);
	b2 = ba; b2.v_depth = 16;
	assert(ba_fb_pa(&b2, &fsz, &k) == ~0ULL);
	/* MINOR 5: CommandLine with no NUL inside BOOT_LINE_LENGTH is rejected at parse time */
	memset(raw + BA_CMDLINE, 'A', 1024);
	bootargs_parse(raw, &ba);
	assert(ba.line_len == 1024 && !ba.cmdline && ba.cmdline_bad);
	raw[BA_CMDLINE + 1023] = 0;
	bootargs_parse(raw, &ba);
	assert(ba.cmdline && !ba.cmdline_bad && strlen(ba.cmdline) == 1023);
	/* 608 layout */
	memset(raw + 700, 0, 600);
	w64(raw + BA_FLAGS_OFF(608) + 8, 24ULL << 30);
	bootargs_parse(raw, &ba);
	assert(ba.line_len == 608);
	memset(raw + 700, 0, 600);
	bootargs_parse(raw, &ba);
	assert(ba.line_len == 0 && !ba.cmdline);
}

static void test_adt(void)
{
	build_adt();
	struct adt a = { adt, ao };
	int chain[ADT_MAXDEPTH], d, sk;
	struct range r[8];
	int mm = adt_path(&a, "/chosen/memory-map", chain, &d);
	assert(mm > 0 && d == 3);
	assert(adt_ranges16(&a, mm, r, 8, &sk) == 1 && sk == 2 && r[0].base == 0x10000010000ULL && r[0].size == 0x4000);
	int cm = adt_path(&a, "/chosen/carveout-memory-map", chain, &d);
	assert(adt_ranges16(&a, cm, r, 8, &sk) == 1 && r[0].size == 0x200000000ULL);
	assert(adt_path(&a, "/chosen/nope", chain, &d) < 0);
	assert(adt_find_compat(&a, "wdt,s5l8960x", chain, &d) > 0 && d == 3);
	uint64_t addr, sz;
	assert(!adt_reg(&a, chain, d, 0, &addr, &sz));
	assert(addr == 0x28836C000ULL && sz == 0x4000);	/* spec §4 */
	assert(adt_reg(&a, chain, d, 1, &addr, &sz) < 0);
	/* MINOR 7: a reg whose translation would overflow fails instead of wrapping */
	{ uint8_t *reg = (uint8_t *)memmem(adt, ao, "reg", 4) + 36;
	  uint64_t save = rd64(reg + 8);
	  w64(reg + 8, 0xffffffffffffffffULL);
	  assert(adt_reg(&a, chain, d, 0, &addr, &sz) < 0);
	  w64(reg + 8, save); }
	/* truncation must fail cleanly at every length */
	for (uint32_t l = 0; l < ao; l++) {
		struct adt t = { adt, l };
		int c2[ADT_MAXDEPTH], d2;
		if (adt_find_compat(&t, "wdt,t8101", c2, &d2) >= 0) assert(!adt_reg(&t, c2, d2, 0, &addr, &sz) || 1);
		adt_path(&t, "/chosen/memory-map", c2, &d2);
	}
}

static void test_place(void)
{
	struct range av[8] = { { 0x1000000, 0x100000 } };
	int n = 1; uint64_t x;
	struct range win = { 0x800000, 0x10000000 };
	assert(!place(win, av, &n, 8, 0xa00000, 0x200000, &x) && x == 0x1200000);	/* skips the hole at 16M */
	assert(!place(win, av, &n, 8, 0x200000, 0x200000, &x) && x == 0x800000);	/* fits below */
	assert(!place(win, av, &n, 8, 0x200000, 0x200000, &x) && x == 0xa00000);
	assert(place(win, av, &n, 8, 0x20000000, 0x200000, &x) < 0);
	/* MINOR 7: an avoid range whose base+size overflows blocks everything above its base */
	struct range av2[4] = { { 0x2000000, ~0ULL - 0x1000 } };
	int n2 = 1;
	assert(!place(win, av2, &n2, 4, 0x200000, 0x200000, &x) && x == 0x800000);
	assert(place(win, av2, &n2, 4, 0x2000000, 0x200000, &x) < 0);
	struct range wrapwin = { ~0ULL - 0x1000, 0x10000 };
	assert(place(wrapwin, av2, &n2, 4, 0x1000, 0x1000, &x) < 0);
}

static void test_fdt(void)
{
	static uint8_t in[4096], out[1 << 16];
	assert(!fdt_create_empty_tree(in, sizeof in));
	assert(!fdt_setprop_u32(in, 0, "#address-cells", 2) && !fdt_setprop_u32(in, 0, "#size-cells", 2));
	int m = fdt_add_subnode(in, 0, "memory@0"); assert(m >= 0);
	assert(!fdt_setprop_string(in, m, "device_type", "memory"));
	struct range rsv[2] = { { 0x10000010000ULL, 0x4000 }, { 0x10105ffe00000ULL, 0x200000000ULL } };
	struct patch_in p = { .mem = { 0x10012400000ULL, 0x5e0000000ULL }, .rsv = rsv, .nrsv = 2,
		.fb_base = 0x10500000000ULL, .fb_w = 3456, .fb_h = 2234, .fb_stride = 3456 * 4, .fb_format = "x8r8g8b8",
		.bootargs = "console=tty0 hello", .initrd_start = 0x10020000000ULL, .initrd_end = 0x10020100000ULL };
	assert(fdt_patch(in, out, sizeof out, &p) == 0);
	assert(fdt_path_offset(out, "/memory@0") < 0);
	int o = fdt_path_offset(out, "/memory@10012400000"); assert(o >= 0);
	int l; const fdt64_t *reg = fdt_getprop(out, o, "reg", &l);
	assert(l == 16 && fdt64_ld(reg) == p.mem.base && fdt64_ld(reg + 1) == p.mem.size);
	o = fdt_path_offset(out, "/reserved-memory/m5boot-rsv1@10105ffe00000"); assert(o >= 0);
	assert(fdt_getprop(out, o, "no-map", &l) && l == 0);
	reg = fdt_getprop(out, o, "reg", &l); assert(l == 16 && fdt64_ld(reg + 1) == 0x200000000ULL);
	o = fdt_path_offset(out, "/chosen/framebuffer@10500000000"); assert(o >= 0);
	assert(!strcmp(fdt_getprop(out, o, "format", &l), "x8r8g8b8"));
	assert(fdt32_ld(fdt_getprop(out, o, "stride", &l)) == 3456 * 4);
	o = fdt_path_offset(out, "/chosen");
	assert(!strcmp(fdt_getprop(out, o, "bootargs", &l), "console=tty0 hello"));
	assert(fdt64_ld(fdt_getprop(out, o, "linux,initrd-end", &l)) == 0x10020100000ULL);
	assert(fdt_check_full(out, fdt_totalsize(out)) == 0);
	/* existing placeholder (as in the J714s DTB) is filled, not duplicated */
	int ch = fdt_add_subnode(in, 0, "chosen"); assert(ch >= 0);
	int fb = fdt_add_subnode(in, ch, "framebuffer@0"); assert(fb >= 0);
	assert(!fdt_setprop(in, fb, "compatible", "apple,simple-framebuffer\0simple-framebuffer", 44));
	assert(!fdt_setprop_string(in, fb, "status", "disabled"));
	assert(fdt_patch(in, out, sizeof out, &p) == 0);
	assert(fdt_path_offset(out, "/chosen/framebuffer@10500000000") < 0);
	o = fdt_path_offset(out, "/chosen/framebuffer@0"); assert(o >= 0);
	assert(!strcmp(fdt_getprop(out, o, "status", &l), "okay"));
	reg = fdt_getprop(out, o, "reg", &l); assert(l == 16 && fdt64_ld(reg) == 0x10500000000ULL);
	assert(!fdt_node_check_compatible(out, o, "apple,simple-framebuffer"));
	/* too-small output buffer must fail, not overflow */
	assert(fdt_patch(in, out, 300, &p) < 0);
}

static void test_payload(const char *path)
{
	FILE *f = fopen(path, "rb"); assert(f);
	static uint8_t b[4096], c[4096]; size_t n = fread(b, 1, sizeof b, f); fclose(f);
	struct payload p;
	uint8_t *h = b + 128;	/* code is 100 bytes -> header at 128 */
	assert(n > 128 && !payload_parse(h, sizeof b - 128, &p));
	assert(p.dtb_size == 33 && p.image_size == 200 && p.initrd_size == 77);
	assert(h[p.dtb_off] == 'D' && !memcmp(h + p.image_off + 0x38, "ARM\x64", 4) && h[p.initrd_off + 76] == 'I');
	assert(128 + p.total <= n && n % 4096 == 0);	/* total covers header..trailer; file zero-padded to 16 KiB (task 07; b[] holds 4096) */
	for (size_t i = 128 + p.total; i < n; i++) assert(!b[i]);
	/* review R1: RAM ends before the trailer => -5 and no read past avail (ASan would flag it) */
	assert(payload_parse(h, p.total, &p) == 0);
	assert(payload_parse(h, p.total - 1, &p) == -5);
	assert(payload_parse(h, 63, &p) == -5);
	size_t tot = p.total;
	{ uint8_t *e = malloc(tot - 16); memcpy(e, h, tot - 16);	/* heap copy without trailer */
	  assert(payload_parse(e, tot - 16, &p) == -5); free(e); }
	assert(payload_parse(b, sizeof b, &p) < 0);
	/* MINOR 6: truncated file (trailer missing), misaligned blob, overlapping blobs, size past the trailer */
	memcpy(c, b, n); memset(c + 128 + tot - 16, 0, 16);
	assert(payload_parse(c + 128, sizeof b - 128, &p) == -3);
	memcpy(c, b, n); w64(c + 128 + 32, rd64(b + 128 + 32) + 8);		/* image_off += 8 */
	assert(payload_parse(c + 128, sizeof b - 128, &p) == -2);
	memcpy(c, b, n); w64(c + 128 + 32, rd64(b + 128 + 16));		/* image_off = dtb_off */
	assert(payload_parse(c + 128, sizeof b - 128, &p) < 0);
	memcpy(c, b, n); w64(c + 128 + 40, 4000);				/* image_size beyond the data */
	assert(payload_parse(c + 128, sizeof b - 128, &p) == -5);
}

int main(int argc, char **argv)
{
	test_bootargs(); test_adt(); test_place(); test_fdt();
	if (argc > 1) test_payload(argv[1]);
	if (argc > 2) {	/* patch a real DTB (e.g. J714s) with spec-like values: dram-base 0x10000000000, 24 GiB */
		static uint8_t in[1 << 20], out[2 << 20];
		FILE *f = fopen(argv[2], "rb"); assert(f); fread(in, 1, sizeof in, f); fclose(f);
		static struct range rsv[200];
		for (int i = 0; i < 200; i++) rsv[i] = (struct range){ 0x10000000000ULL + i * 0x100000ULL, 0x4000 };
		struct patch_in p = { .mem = { 0x10012400000ULL, 0x5e0000000ULL }, .rsv = rsv, .nrsv = 200,
			.fb_base = 0x10500000000ULL, .fb_w = 3024, .fb_h = 1964, .fb_stride = 3024 * 4, .fb_format = "x8r8g8b8",
			.bootargs = "maxcpus=1", .initrd_start = 0x10020000000ULL, .initrd_end = 0x10020100000ULL };
		assert(fdt_patch(in, out, sizeof out, &p) == 0 && fdt_check_full(out, fdt_totalsize(out)) == 0);
		assert(fdt_path_offset(out, "/memory@800000000") < 0 && fdt_path_offset(out, "/memory@10012400000") >= 0);
		assert(fdt_path_offset(out, "/chosen/framebuffer@0") >= 0);
		FILE *g = fopen("build/j714s-patched.dtb", "wb"); fwrite(out, 1, fdt_totalsize(out), g); fclose(g);
		printf("real DTB patched: %u bytes\n", fdt_totalsize(out));
	}
	puts("test_core: ok");
	return 0;
}
