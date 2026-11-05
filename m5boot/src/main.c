#include "util.h"
#include "fb.h"
#include "bootargs.h"
#include "adt.h"
#include "fdtpatch.h"
#include "place.h"
#include "payload.h"
#include "inflate.h"
#include "probefb.h"
#include "cmdline.h"
#include <string.h>

/* Knobs (override with -D from the Makefile). */
#ifndef DEFAULT_BOOTARGS
/* spec/inputs.md suggested first-boot args, minus earlycon=efifb (needs EFI screen_info; we only give a DT simple-framebuffer) */
#define DEFAULT_BOOTARGS "maxcpus=1 keep_bootcon console=tty0 loglevel=8 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0"
#endif
#ifndef FB_FORMAT32
#define FB_FORMAT32 "x8r8g8b8"	/* task 02; spec H8 suspects x2r10g10b10: colour bars decide */
#endif
#ifndef WDT_COMPAT
#define WDT_COMPAT "wdt,t8101"	/* spec §4 [OURS] */
#endif
#ifndef WDT_EXPECT
#define WDT_EXPECT 0x28836C000ULL	/* spec §4 [OURS]; safety cross-check only, address comes from the ADT */
#endif
#define WDT_CTRL 0x1c	/* Linux apple_wdt.c APPLE_WDT_WD1_CTRL */
#define FDT_MAX (2u << 20)	/* booting.rst: dtb <= 2 MiB */
#define MAX_RSV 512

extern char _image_start[], _payload[];
void dcache_civac_range(uint64_t start, uint64_t len);
void dcache_ivac_range(uint64_t start, uint64_t len);
void jump_kernel(uint64_t entry, uint64_t dtb) __attribute__((noreturn));
uint64_t read_cntfrq(void);
uint64_t read_sctlr(void);

#ifdef PROBE
#define BAR_W 112	/* right-hand strip reserved for the per-step bars; the text console never touches it */
static struct fb bars;
static const void *g_x0;
static int in_exc;
uint64_t read_vbar(void);
#endif
static struct fb con;
static int have_con, step;
static const char *wdt_state;	/* set at runtime: a static initializer would need an ABS64 reloc */
static struct range rsv[MAX_RSV], avoid[MAX_RSV + 16];
static char bootargs[2048];

#ifdef GZ3
/* Task 12 gz3: beacon3's stage-coded WDT beacon for every step up to the Linux jump (table: NOTES.md "Task 12").
 * stage word in start.S .data (stages 0-4 set there). Exception or failed check at stage s -> bite after 10+10*s s. */
#include "beacon.h"
#ifndef WDT_PA
#define WDT_PA 0x28836C000
#endif
extern volatile uint32_t beacon_stage;
#ifdef VM	/* VM-only test hook: u32 at 0x44020000 == s+1 -> brk at stage s. Never on hardware. */
#define BSTAGE(n) do { beacon_stage = (n); if (*(volatile uint32_t *)0x44020000 == (n) + 1u) __asm__ volatile("brk #0x55"); } while (0)
#else
#define BSTAGE(n) do { beacon_stage = (n); } while (0)
#endif
static void beacon_now(void) { wdt_beacon((volatile uint32_t *)WDT_PA, beacon3_seconds(beacon_stage, 0)); }
#else
#define BSTAGE(n) do { } while (0)
#endif

static void pr(const char *fmt, ...)
{
	char b[512];	/* fits the gz5 bootargs line; longer output is truncated (fmt.c terminates since task 14) */
	va_list ap; va_start(ap, fmt);
	m5_vsnprintf(b, sizeof b, fmt, ap);
	va_end(ap);
	if (have_con) fb_puts(&con, b);
#ifdef VM
	/* VM only: mirror to QEMU virt's PL011 data register so tests can read step messages. Never on HW. */
	for (const char *c = b; *c; c++) *(volatile uint32_t *)0x09000000 = *c;
#endif
}

/* Halt for good: wfe with DAIF masked, no writes. Without a console this is a silent halt.
 * If the WDT was not disabled it will reset the Mac and iBoot relaunches us (possible loop):
 * recover with hold power -> Startup Options -> Macintosh HD (spec §10). */
static void __attribute__((noreturn)) panic(const char *msg)
{
#ifdef GZ3
	beacon_now();	/* arm first: a failed check beacons like an exception at this stage */
#endif
#ifdef PROBE
	pr("[m5boot] PROBE HALTED in step %d: %s\n[m5boot] watchdog: %s\n[m5boot] hold power to return to macOS.\n", step, msg, wdt_state);
	for (;;) __asm__ volatile("wfe");
#endif
	pr("[m5boot] PANIC in step %d: %s\n[m5boot] watchdog: %s\n[m5boot] halted.\n", step, msg, wdt_state);
	for (;;) __asm__ volatile("wfe");
}

#ifdef PROBE
/* One bar per step in a fixed slot of the right-hand strip: slot presence (not colour) shows how far we got. */
static void bar(int n)
{
	static const uint32_t c[4] = { 0x00ffffff, 0x00ff0000, 0x0000ff00, 0x000000ff };
	if (!have_con) return;
	uint32_t h = bars.height / 9;
	fb_rect(&bars, bars.width - BAR_W + 8, n * h + 8, BAR_W - 16, h - 16, c[n & 3]);
}

/* Console only inside a vram region (src/probefb.c, task 09 tiers a/b/c). None -> silent.
 * Paints the whole FB one solid colour first, so a photo shows the code ran. */
static struct fbsel sel;
static const char *probe_con(const struct bootargs *ba, uint64_t *fbpa, uint64_t *fbsz)
{
#ifdef GZ3
	/* Task 12: console AND the FDT simple-framebuffer = the boot_args FB if strictly sane (3024x1964, stride 12096,
	 * 30/32 bpp, inside the observed DRAM), else the OBSERVED vram region (where stage 5 painted green). */
	probe_fb(ba, &sel);	/* still fills sel.adt_ok/vram_* for the on-screen dump */
	uint64_t fx = beacon_fixed_fb(ba, DRAM_OBS_BASE, DRAM_OBS_SIZE);
	sel.w = fx != ~0ULL ? ba->v_width : VRAM_OBS_W; sel.h = fx != ~0ULL ? ba->v_height : VRAM_OBS_H;
	sel.stride = sel.w * 4; sel.size = sel.stride * sel.h;
	sel.fmt30 = fx != ~0ULL ? (ba->v_depth & 0xff) == 30 : 1;
	sel.pa = fx != ~0ULL ? fx : VRAM_OBS_PA;
	*fbpa = sel.pa; *fbsz = sel.size;
	fb_init(&bars, sel.pa, sel.w, sel.h, sel.stride);
	fb_init(&con, *fbpa, bars.width > BAR_W ? bars.width - BAR_W : bars.width, bars.height, bars.stride);
	have_con = 1;
	return fx != ~0ULL ? "gz3: boot_args FB (strict, fixed offsets)" : "gz3: OBSERVED vram 0x105_D311_0000 3024x1964 30bpp";
#endif
	probe_fb(ba, &sel);
	*fbpa = sel.pa; *fbsz = sel.size;
	if (sel.pa == ~0ULL) return "none";
	fb_init(&bars, sel.pa, sel.w, sel.h, sel.stride);
	fb_rect(&bars, 0, 0, bars.width, bars.height, 0x3ff003ff);
	fb_init(&con, *fbpa, bars.width > BAR_W ? bars.width - BAR_W : bars.width, bars.height, bars.stride);
	have_con = 1;
	return sel.tier == 'a' ? "tier a: boot_args FB inside ADT /vram" : sel.tier == 'b' ?
	       "tier b: ADT /vram base + boot_args geometry" : "tier c: OBSERVED vram 0x105_D311_0000 3024x1964 30bpp";
}

/* Called from the vectors (start.S) with a fresh stack. Paints the whole screen, prints ESR/ELR/FAR, halts. */
void __attribute__((noreturn)) probe_exception(uint64_t kind, uint64_t esr, uint64_t elr, uint64_t far)
{
	if (in_exc++) for (;;) __asm__ volatile("wfe");	/* fault inside the painter: just halt */
#ifdef GZ3
	beacon_now();	/* arm before any FB/console work, which could fault again */
#endif
	if (!have_con && g_x0) {
		struct bootargs b; uint64_t a, z;
		bootargs_parse(g_x0, &b);
		probe_con(&b, &a, &z);
	}
	if (have_con) { fb_rect(&bars, 0, 0, bars.width, bars.height, 0x00ff00ff); con.row = con.col = 0; }
	static const char kn[4][8] = { "sync", "IRQ", "FIQ", "SError" };	/* arrays, not pointers: no ABS64 relocs */
	static const char src[4][12] = { "cur EL SP0", "cur EL SPx", "lower A64", "lower A32" };
	pr("\n[m5boot] PROBE EXCEPTION in step %d: vector %llu (%s, %s)\n", step, (unsigned long long)kind,
	   kn[kind & 3], src[(kind >> 2) & 3]);
	pr("  ESR %llx  ELR %llx  FAR %llx  (EC %llx)\n", (unsigned long long)esr, (unsigned long long)elr,
	   (unsigned long long)far, (unsigned long long)(esr >> 26 & 0x3f));
	pr("  image base %llx (ELR offset %llx)\n  watchdog: %s\n  halted: hold power to return to macOS.\n",
	   (unsigned long long)(uintptr_t)_image_start, (unsigned long long)(elr - (uintptr_t)_image_start), wdt_state);
	for (;;) __asm__ volatile("wfe");
}
#define BAR(n) bar(n)
#else
#define BAR(n) do { } while (0)
#endif

#define STEP(n, ...) do { step = (n); BAR(n); pr("[m5boot] step %d: ", (n)); pr(__VA_ARGS__); pr("\n"); } while (0)
#define U(x) ((unsigned long long)(x))

#ifdef WDT_ALL	/* task 16 (gz7): every watchdog in the block + the 4 extra ADT wdt registers (read-only) */
#include "wdt.h"
static uint64_t wdt_extra[WDT_EXTRA_N];	/* validated PAs (0 = mismatch, not read) */
static int wdt_block_ok;			/* step 2 validated the block against the ADT */
static void wdt_report(uint64_t base, const char *when)
{
	struct wdt_snap s, a;
	wdt_read((volatile uint32_t *)base, &s);
	pr("  WDT %s: WD0 cur %x bite %x bark %x ctrl %x | WD1 cur %x bite %x ctrl %x | WD2 cur %x bite %x ctrl %x\n", when,
	   s.cur[0], s.bite[0], s.bark0, s.ctrl[0], s.cur[1], s.bite[1], s.ctrl[1], s.cur[2], s.bite[2], s.ctrl[2]);
	pr("  WDT extra regs (read-only):");
	for (int i = 0; i < WDT_EXTRA_N; i++)
		if (wdt_extra[i]) pr(" [%llx]=%x", (unsigned long long)wdt_extra[i], *(volatile uint32_t *)wdt_extra[i]);
		else pr(" [reg%d not read]", i + 1);
	pr("\n");
	int n = wdt_disable_armed((volatile uint32_t *)base, &a);
	pr("  WDT %s: disabled %d armed; ctrl now WD0 %x WD1 %x WD2 %x\n", when, n, a.ctrl[0], a.ctrl[1], a.ctrl[2]);
}
#endif

#ifdef SECWDT
/* Task 19 (gz10): the SECONDARY watchdog. Provenance (kept as the PM asked): a THIRD-PARTY report (Discord DM from
 * betizzel's agent, 2026-11-04 23:23) describing m1n1's BEHAVIOUR from their boot logs, not code (we read no m1n1):
 * "writes 0 to 0x288330008 whenever wdt-version is 2 or 3"; "Secondary WDT disabled" on every J714s boot.
 * Owner-authorised exception to the WDT-only write rule: exactly this one register (ADT wdt reg[2]), only if the
 * runtime ADT translates reg[2] to exactly 0x2_8833_0008 and wdt-version is 2 or 3. reg[1]/[3]/[4]: read only. */
#ifndef SECWDT_PA
#define SECWDT_PA 0x288330008ULL
#endif
static uint32_t secwdt_before = ~0u, secwdt_after = ~0u;	/* ~0 = not done (passed to Linux as m5.wdt2=) */
static int secwdt_ok;
static void secwdt_clear(const char *when)
{
	volatile uint32_t *r = (volatile uint32_t *)SECWDT_PA;
	uint32_t b = *r;
	*r = 0;
	__asm__ volatile("dsb sy" ::: "memory");
	uint32_t a = *r;
	pr("  SECWDT %s: [%llx] before %x, wrote 0, after %x\n", when, (unsigned long long)SECWDT_PA, b, a);
	if (secwdt_before == ~0u) { secwdt_before = b; secwdt_after = a; }
}
#endif

static void __attribute__((unused)) show_ranges(const char *what, const struct range *r, int n)
{
	for (int i = 0; i < n; i++) pr("  %s %d: %llx +%llx\n", what, i, U(r[i].base), U(r[i].size));
}

/* arm64 Image header checks (booting.rst). Returns an error string or NULL. */
static const char *kernel_hdr(const uint8_t *img, uint64_t size, uint64_t *text_off, uint64_t *isize, uint64_t *iflags)
{
	if (size < 64 || memcmp(img + 0x38, "ARM\x64", 4)) return "Image: bad arm64 magic";
	*text_off = rd64(img + 8); *isize = rd64(img + 16); *iflags = rd64(img + 24);
	if (!*isize) { *text_off = 0x80000; *isize = align_up(size, 1 << 21) + (64ULL << 20); }	/* booting.rst; ponytail: guess 64M headroom */
	if (*iflags & 1) return "Image is big-endian";
	if (size > *isize || *isize > PAYLOAD_MAX_BLOB || *text_off > PAYLOAD_MAX_BLOB) return "Image size fields invalid";
	return 0;
}

#ifdef PROBE
void main(uint64_t x0, uint64_t el, uint64_t sctlr, uint64_t pc, uint64_t wd_before, uint64_t wd_after)
#else
void main(uint64_t x0, uint64_t el, uint64_t sctlr, uint64_t pc)
#endif
{
	struct bootargs ba;
	const char *k;

	wdt_state = "NOT disabled (still armed if iBoot armed it)";
#ifdef PROBE
	g_x0 = (const void *)x0;
	wdt_state = wd_after & 4 ? "entry write done but RESET_EN still set" : "disabled at entry (hard-coded PA)";
#endif
#ifdef GZ3
	/* stage 5 (owner, as beacon3): bright GREEN over the OBSERVED vram region before touching boot_args, then clean */
	BSTAGE(5);
	{
		_Static_assert((uint64_t)VRAM_OBS_W * 4 * VRAM_OBS_H <= VRAM_OBS_SIZE, "green paint must stay inside vram");
		struct fb g;
		fb_init(&g, VRAM_OBS_PA, VRAM_OBS_W, 0, VRAM_OBS_W * 4);	/* h = 0: fb_init clears nothing */
		g.height = VRAM_OBS_H;
		fb_rect(&g, 0, 0, VRAM_OBS_W, VRAM_OBS_H, 0x000ffc00);
		dcache_civac_range(VRAM_OBS_PA, (uint64_t)VRAM_OBS_W * 4 * VRAM_OBS_H);
	}
#endif

	/* ---- step 1: boot_args + console (reads only) ---- */
	BSTAGE(6);
	bootargs_parse((const void *)x0, &ba);
	uint64_t fbsz;
	const char *fbfmt = (ba.v_depth & 0xff) == 30 ? "x2r10g10b10" : FB_FORMAT32;
#ifdef PROBE
	uint64_t fbpa;
	const char *fbkind = probe_con(&ba, &fbpa, &fbsz);
	if (have_con) fbfmt = sel.fmt30 ? "x2r10g10b10" : FB_FORMAT32;
	BAR(0);
#else
	uint64_t fbpa = ba_fb_pa(&ba, &fbsz, &k);
	const char *fbkind = k;
	if (fbpa != ~0ULL) { fb_init(&con, fbpa, ba.v_width, ba.v_height, ba.v_stride); have_con = 1; }
#endif
	STEP(1, "m5boot v0 entry: x0=%llx EL%llu SCTLR=%llx (now %llx) PC=%llx CNTFRQ=%llu", U(x0), U(el), U(sctlr),
	     U(read_sctlr()), U(pc), U(read_cntfrq()));
	pr("  boot_args rev %u ver %u%s, BOOT_LINE_LENGTH=%u%s%s\n", ba.revision, ba.version,
	   ba.revision == 1 || ba.revision == 2 ? "" : " (UNKNOWN revision)", ba.line_len,
	   ba.line_len ? "" : " (no plausible layout: cmdline ignored)",
	   ba.cmdline_bad ? " (cmdline not NUL-terminated: ignored)" : "");
	pr("  virtBase %llx physBase %llx memSize %llx topOfKernelData %llx memSizeActual %llx flags %llx\n",
	   U(ba.virt_base), U(ba.phys_base), U(ba.mem_size), U(ba.top_kdata), U(ba.mem_actual), U(ba.boot_flags));
	pr("  video %llx (%s) %llux%llu stride %llu depth %llx\n", U(ba.v_base), fbkind, U(ba.v_width),
	   U(ba.v_height), U(ba.v_stride), U(ba.v_depth));
	if (ba.cmdline) pr("  cmdline: \"%s\"\n", ba.cmdline);
#ifdef PROBE
	{
		uint64_t cel; __asm__ volatile("mrs %0, CurrentEL" : "=r"(cel));
		pr("  PROBE: console %s at %llx (%ux%u stride %u); CurrentEL %llx; image base %llx; VBAR %llx\n",
		   fbkind, U(fbpa), bars.width, bars.height, bars.stride, U(cel), U((uintptr_t)_image_start), U(read_vbar()));
		pr("  PROBE: ADT ptr %llx len %u %s; ADT /vram %s %llx +%llx\n", U(ba.dt_ptr), ba.dt_len,
		   sel.adt_ok ? "parsed" : "NOT parsed", sel.vram_ok ? "reg" : "NOT found", U(sel.vram_base), U(sel.vram_size));
		pr("  PROBE: WD1_CTRL at entry (PA %llx): before %llx after %llx -> %s\n", U(WDT_EXPECT + WDT_CTRL),
		   U(wd_before), U(wd_after), wdt_state);
		const uint8_t *b = (const uint8_t *)x0;
		for (int o = 0; o < 0x180; o += 32) {
			char l[100]; int n = m5_snprintf(l, sizeof l, "  %03x:", o);
			for (int i = 0; i < 32; i++) n += m5_snprintf(l + n, sizeof l - n, "%s%02x", i % 8 ? "" : " ", b[o + i]);
			pr("%s\n", l);
		}
		static const uint32_t lens[] = { 608, 1024 };	/* XNU tags, spec §2 */
		for (int i = 0; i < 2; i++) {
			uint32_t off = BA_FLAGS_OFF(lens[i]);
			pr("  layout BOOT_LINE_LENGTH=%u: bootFlags@%x=%llx memSizeActual@%x=%llx%s\n", lens[i], off,
			   U(rd64(b + off)), off + 8, U(rd64(b + off + 8)), ba.line_len == lens[i] ? "  <- plausible, used" : "");
		}
		pr("  (Video/machineType/deviceTree are at fixed offsets 40..107 under every layout)\n");
	}
#endif
	if (have_con) {	/* spec H8: R, G, B, white bars, encoded as x8r8g8b8 */
		static const uint32_t c[4] = { 0x00ff0000, 0x0000ff00, 0x000000ff, 0x00ffffff };
		for (int i = 0; i < 4; i++) fb_rect(&con, con.width - 4 * 48 + i * 48, con.height - 48, 40, 40, c[i]);
	}

	/* ---- step 2: watchdog, as early as possible (needs only the ADT pointer) ---- */
	BSTAGE(7);
	uint64_t dtpa = ba_to_pa(&ba, ba.dt_ptr, &k);
	STEP(2, "ADT at %llx (%s -> PA %llx), %u bytes", U(ba.dt_ptr), k, U(dtpa), ba.dt_len);
	if (dtpa == ~0ULL || !ba.dt_len || ba.dt_len > ba.mem_size - (dtpa - ba.phys_base)) panic("ADT pointer/length not in DRAM");
	struct adt adt = { (const uint8_t *)dtpa, ba.dt_len };
	int chain[ADT_MAXDEPTH], depth, nrsv = 0, skipped, n;
	uint64_t wdt, wsz;
	if (adt_find_compat(&adt, WDT_COMPAT, chain, &depth) < 0) panic("watchdog node (" WDT_COMPAT ") not found");
	if (adt_reg(&adt, chain, depth, 0, &wdt, &wsz)) panic("watchdog reg translation failed");
	pr("  watchdog at %llx size %llx (from ADT)\n", U(wdt), U(wsz));
#ifdef PROBE
	if (wdt != WDT_EXPECT) pr("  WARNING: ADT watchdog %llx != hard-coded %llx used at entry\n", U(wdt), U(WDT_EXPECT));
	else pr("  matches the entry PA; WD1_CTRL now %x (no second write)\n", *(volatile uint32_t *)(wdt + WDT_CTRL));
#ifdef WDT_ALL
	if (wdt == WDT_EXPECT && wsz >= 0x30) {
		static const uint64_t exp[WDT_EXTRA_N] = WDT_EXTRA_PAS;	/* our ADT dump; read only if the runtime ADT agrees */
		for (int i = 0; i < WDT_EXTRA_N; i++) {
			uint64_t pa, sz;
			wdt_extra[i] = !adt_reg(&adt, chain, depth, i + 1, &pa, &sz) && pa == exp[i] && sz >= 4 ? pa : 0;
		}
		wdt_block_ok = 1;
		wdt_report(wdt, "step 2");
#ifdef SECWDT
		{	/* extra regs twice, ~1 s apart (reads only), then the one authorised write */
			uint64_t t0, t; __asm__ volatile("isb; mrs %0, cntpct_el0" : "=r"(t0));
			do __asm__ volatile("isb; mrs %0, cntpct_el0" : "=r"(t)); while (t - t0 < read_cntfrq());
			pr("  WDT extra regs, +1 s:");
			for (int i = 0; i < WDT_EXTRA_N; i++)
				if (wdt_extra[i]) pr(" [%llx]=%x", U(wdt_extra[i]), *(volatile uint32_t *)wdt_extra[i]);
				else pr(" [reg%d not read]", i + 1);
			pr("\n");
			const uint8_t *v; uint32_t l;
			uint32_t ver = !adt_prop(&adt, chain[depth - 1], "wdt-version", &v, &l) && l == 4 ? rd32(v) : 0;
			secwdt_ok = (ver == 2 || ver == 3) && wdt_extra[1] == SECWDT_PA;
			pr("  SECWDT: wdt-version %u, reg[2] %llx -> %s\n", ver, U(wdt_extra[1]),
			   secwdt_ok ? "clearing" : "conditions not met: NOT written");
			if (secwdt_ok) secwdt_clear("step 2");
		}
#endif
	} else pr("  WDT: block not at the expected PA or too small: not touched\n");
#endif
	if (0) {
#else
	if (wdt != WDT_EXPECT || wsz < WDT_CTRL + 4 || wdt - ba.phys_base < ba.mem_size) {
#endif
		pr("  WARNING: address differs from spec (%llx) or is in DRAM: NOT writing\n", U(WDT_EXPECT));
		wdt_state = "NOT disabled (address interlock): a reset loop is possible";
	} else {
		volatile uint32_t *ctrl = (volatile uint32_t *)(wdt + WDT_CTRL);
		pr("  WD1_CTRL before: %x\n", *ctrl);
		*ctrl = 0;	/* apple_wdt_stop(): writel_relaxed(0, regs + APPLE_WDT_WD1_CTRL) */
		__asm__ volatile("dsb sy" ::: "memory");
		uint32_t after = *ctrl;
		pr("  WD1_CTRL after: %x\n", after);
		wdt_state = after & 4 ? "write done but RESET_EN still set" : "disabled";	/* CTRL_RESET_EN BIT(2) */
	}

	/* ---- step 3: remaining boot_args checks + ADT memory maps ---- */
	BSTAGE(8);
	STEP(3, "memory maps");
	if (!read_cntfrq()) panic("CNTFRQ is 0 (booting.rst requires it programmed)");
	if (!ba.mem_size || ba.phys_base + ba.mem_size < ba.phys_base) panic("boot_args memSize invalid");
	uint64_t top = ba_to_pa(&ba, ba.top_kdata, &k);
	pr("  topOfKernelData is %s\n", k);
	if (top == ~0ULL) panic("topOfKernelData outside DRAM");
	int mm = adt_path(&adt, "/chosen/memory-map", chain, &depth);
	if (mm < 0) panic("/chosen/memory-map not found");
	if ((n = adt_ranges16(&adt, mm, rsv, MAX_RSV, &skipped)) < 0) panic("memory-map: too many entries");
	pr("  /chosen/memory-map: %d ranges (%d skipped: not 16 bytes or base+size overflows)\n", n, skipped);
	{ int dropped; n = drop_ram_window(rsv, n, ba.phys_base, ba.mem_size, &dropped);
	  if (dropped) pr("  dropped %d memory-map range(s) equal to the kernel RAM window\n", dropped); }
	show_ranges("mm", rsv, n);	/* task 13: shown in every build (9 ranges natively) */
	nrsv = n;
	int cm = adt_path(&adt, "/chosen/carveout-memory-map", chain, &depth);
	if (cm < 0) pr("  WARNING: /chosen/carveout-memory-map not found\n");
	else {
		if ((n = adt_ranges16(&adt, cm, rsv + nrsv, MAX_RSV - nrsv, &skipped)) < 0) panic("carveouts: too many");
		pr("  /chosen/carveout-memory-map: %d ranges (%d skipped)\n", n, skipped);
		int dropped;
		n = drop_ram_window(rsv + nrsv, n, ba.phys_base, ba.mem_size, &dropped);
		if (dropped) pr("  dropped %d carveout(s) equal to the kernel RAM window %llx +%llx (not a reservation)\n",
				dropped, U(ba.phys_base), U(ba.mem_size));
#ifndef PROBE
		show_ranges("co", rsv + nrsv, n);
#endif
		nrsv += n;
	}

#if defined(PROBE) && defined(VM)
	if (ba.cmdline && !memcmp(ba.cmdline, "probefault", 10)) __asm__ volatile("brk #0x55");	/* VM test of the vectors */
#endif
	/* ---- step 4: payload ---- */
	BSTAGE(9);
	struct payload pl;
	const uint8_t *ph = (const uint8_t *)_payload;
	uint64_t ram_end = ba.phys_base + ba.mem_size;
	if ((uint64_t)ph < ba.phys_base || (uint64_t)ph >= ram_end) panic("payload not inside boot_args DRAM");
	int pr_err = payload_parse(ph, ram_end - (uint64_t)ph, &pl);
	if (pr_err) { pr("  payload error %d\n", pr_err); panic("payload header/trailer invalid"); }
	const uint8_t *img = ph + pl.image_off;
	uint64_t img_size = pl.image_size, text_off = 0, isize = 0, iflags = 0;
	int gz = img_size >= 18 && img[0] == 0x1f && img[1] == 0x8b;	/* RFC 1952 magic: Image.gz, inflated in step 5 */
	if (!gz && (k = kernel_hdr(img, img_size, &text_off, &isize, &iflags))) panic(k);
	STEP(4, "payload: dtb %llu, Image%s %llu (text_offset %llx image_size %llx flags %llx), initrd %llu",
	     U(pl.dtb_size), gz ? ".gz" : "", U(img_size), U(text_off), U(isize), U(iflags), U(pl.initrd_size));

	/* ---- step 5: memory plan (spec H5) ---- */
	BSTAGE(10);
	struct range win = { align_up(top, 2 << 20), 0 };
	uint64_t hi = align_down(ba.phys_base + ba.mem_size, 2 << 20);
	if (hi <= win.base) panic("no usable RAM above topOfKernelData");
	win.size = hi - win.base;
	uint64_t self = (uint64_t)_image_start, self_sz = align_up((uint64_t)_payload + pl.total - self, 1 << 14);
	if (have_con) rsv[nrsv++] = (struct range){ fbpa, align_up(fbsz, 1 << 14) };
	rsv[nrsv++] = (struct range){ self, self_sz };
	int na = nrsv;
	memcpy(avoid, rsv, nrsv * sizeof *rsv);
	avoid[na++] = (struct range){ align_down(x0, 1 << 14), 1 << 14 };	/* boot_args */
	avoid[na++] = (struct range){ dtpa, ba.dt_len };			/* ADT */
	uint64_t kbase, dtb, initrd = 0;
	if (gz) {	/* ponytail: inflate to scratch then copy (one extra pass); inflate in place once text_offset is known up front */
		uint64_t gsz = gz_isize(img, img_size), scr, out;
		if (place(win, avoid, &na, MAX_RSV + 16, gsz, 2 << 20, &scr)) panic("no room to inflate Image.gz");
		STEP(5, "inflating Image.gz %llu -> %llu bytes at %llx (slow: caches off)", U(img_size), U(gsz), U(scr));
		BSTAGE(11);
		dcache_ivac_range(scr, gsz);
		int e = gunzip(img, img_size, (uint8_t *)scr, gsz, &out);
		if (e) { pr("  gunzip error %d\n", e); panic("Image.gz inflate failed"); }
		img = (const uint8_t *)scr; img_size = out;
		if ((k = kernel_hdr(img, img_size, &text_off, &isize, &iflags))) panic(k);
		pr("  Image %llu bytes: text_offset %llx image_size %llx flags %llx\n", U(img_size), U(text_off), U(isize), U(iflags));
	}
	BSTAGE(12);
	if (place(win, avoid, &na, MAX_RSV + 16, text_off + isize, 2 << 20, &kbase)) panic("no room for kernel");
	if (place(win, avoid, &na, MAX_RSV + 16, FDT_MAX, 2 << 20, &dtb)) panic("no room for FDT");
	if (pl.initrd_size && place(win, avoid, &na, MAX_RSV + 16, pl.initrd_size, 1 << 16, &initrd)) panic("no room for initrd");
	STEP(5, "RAM window %llx-%llx; m5boot %llx +%llx", U(win.base), U(hi), U(self), U(self_sz));
	pr("  kernel %llx (entry %llx), FDT %llx, initrd %llx\n", U(kbase), U(kbase + text_off), U(dtb), U(initrd));

	/* ---- step 6: invalidate destinations, copy, patch FDT ---- */
	BSTAGE(13);
	STEP(6, "invalidating destinations, copying Image/initrd, patching FDT");
	/* Drop any stale (possibly dirty) lines first so the final clean can't write old data over our copy. */
	dcache_ivac_range(kbase, text_off + isize);
	dcache_ivac_range(dtb, FDT_MAX);
	if (initrd) dcache_ivac_range(initrd, pl.initrd_size);
#ifdef EARLYCON_M5FB	/* gz5 (task 14): + earlycon=m5fb,<fb>,<w>,<h>,<stride>,<bpp> panic=0 initcall_debug ignore_loglevel */
#ifndef EARLYCON_XOFF
#define EARLYCON_XOFF 0
#endif
#ifndef CMDLINE_EXTRA
#define CMDLINE_EXTRA ""
#endif
	/* gz8 (task 17): x offset = half the width (1512 on the native 3024 px panel, as inputs.md slim v3 shows),
	 * so the kernel earlycon draws on the right half and m5boot's log stays readable on the left. */
	const char *extra = CMDLINE_EXTRA;
#ifdef SECWDT	/* task 19: the step-2 before/after of the secondary WDT, so the Linux logger records them */
	char ex[160];
	if (secwdt_before != ~0u) m5_snprintf(ex, sizeof ex, "%s m5.wdt2=0x%x,0x%x", CMDLINE_EXTRA, secwdt_before, secwdt_after);
	else m5_snprintf(ex, sizeof ex, "%s m5.wdt2=none", CMDLINE_EXTRA);
	extra = ex;
#endif
	if (build_cmdline(bootargs, sizeof bootargs, DEFAULT_BOOTARGS, ba.cmdline, have_con ? fbpa : 0,
			  bars.width, bars.height, bars.stride, sel.fmt30 ? 30 : 32,
			  EARLYCON_XOFF ? bars.width / 2 : 0, extra) < 0) panic("kernel cmdline too long");
#else
	m5_snprintf(bootargs, sizeof bootargs, "%s%s%s", DEFAULT_BOOTARGS,
		    ba.cmdline && ba.cmdline[0] ? " " : "", ba.cmdline ? ba.cmdline : "");
#endif
	memcpy((void *)(kbase + text_off), img, img_size);
	if (initrd) memcpy((void *)initrd, ph + pl.initrd_off, pl.initrd_size);
	struct patch_in p = {
		.mem = win, .rsv = rsv, .nrsv = nrsv,
#ifdef PROBE	/* the full FB, not the console (which is narrower by the BAR_W strip) */
		.fb_base = have_con ? fbpa : 0, .fb_w = bars.width, .fb_h = bars.height, .fb_stride = bars.stride,
#else
		.fb_base = have_con ? fbpa : 0, .fb_w = con.width, .fb_h = con.height, .fb_stride = con.stride,
#endif
		.fb_format = fbfmt, .bootargs = bootargs,
		.initrd_start = initrd, .initrd_end = initrd + pl.initrd_size,
	};
	int r = fdt_patch(ph + pl.dtb_off, (void *)dtb, FDT_MAX, &p);
	if (r) { pr("  libfdt error %d\n", r); panic("FDT patch failed"); }
	pr("  bootargs: \"%s\"\n", bootargs);

#ifdef PROBE_HALT
	STEP(7, "PROBE COMPLETE (no jump; watchdog %s). Photograph this screen, then hold power to return to macOS.", wdt_state);
	for (;;) __asm__ volatile("wfe");
#endif
	/* ---- step 7: jump ---- */
#ifdef PROBE	/* gz build: 10 s on-screen summary before the jump, so a phone video captures everything */
	BSTAGE(14);
	pr("[m5boot] SUMMARY: steps 1-6 ok; watchdog %s; kernel %llx FDT %llx initrd %llx; console %llx\n",
	   wdt_state, U(kbase + text_off), U(dtb), U(initrd), U(fbpa));
	for (int sec = 10; sec > 0; sec--) {
		uint64_t t0, t; __asm__ volatile("isb; mrs %0, cntpct_el0" : "=r"(t0));
		pr("  jumping to Linux in %d s\n", sec);
		do __asm__ volatile("isb; mrs %0, cntpct_el0" : "=r"(t)); while (t - t0 < read_cntfrq());
	}
#endif
	BSTAGE(15);
#ifdef GZ3	/* disable the WDT again right before the jump (the beacon may never have armed it; harmless then) */
	*(volatile uint32_t *)(WDT_PA + WDT_CTRL) = 0;	/* apple_wdt_stop() */
	__asm__ volatile("dsb sy" ::: "memory");
	wdt_state = "disabled again before the jump";
#endif
#ifdef PMGR_PS
	/* Task 17 (gz8): READ ONLY, print raw PMGR power-state registers. Offsets + blocks from the slim-v3 Linux DT
	 * (spec/inputs.md): pmgr@2_8830_0000 power-controller@150 "atc0_usb", @148 "atc0_usb_aon";
	 * pmgr@2_8060_0000 @208 "atc0_common". The base must ALSO be one of the runtime ADT /arm-io/pmgr reg entries,
	 * else nothing is read. No PMGR writes. */
	{
#ifndef PMGR_ATC_BLK
#define PMGR_ATC_BLK 0x288300000ULL
#define PMGR_FAB_BLK 0x280600000ULL
#endif
		static const struct { uint64_t blk; uint32_t off; char name[16]; } ps[3] = {
			{ PMGR_ATC_BLK, 0x150, "atc0_usb" }, { PMGR_FAB_BLK, 0x208, "atc0_common" }, { PMGR_ATC_BLK, 0x148, "atc0_usb_aon" } };
		int pc[ADT_MAXDEPTH], pd;
		if (adt_path(&adt, "/arm-io/pmgr", pc, &pd) < 0) pr("  PMGR: /arm-io/pmgr not in the ADT: nothing read\n");
		else for (int i = 0; i < 3; i++) {
			int hit = 0;
			for (int r = 0; r < 64 && !hit; r++) {
				uint64_t b, s;
				if (adt_reg(&adt, pc, pd, r, &b, &s)) break;
				if (b == ps[i].blk && s >= ps[i].off + 4) {
					pr("  PMGR PS %s: ADT pmgr reg[%d] %llx + %x = %x\n", ps[i].name, r, U(b), ps[i].off,
					   *(volatile uint32_t *)(b + ps[i].off));
					hit = 1;
				}
			}
			if (!hit) pr("  PMGR PS %s: block %llx not among the ADT pmgr regs: not read\n", ps[i].name, U(ps[i].blk));
		}
	}
#endif
#ifdef WDT_ALL
	if (wdt_block_ok) wdt_report(WDT_EXPECT, "pre-jump");	/* re-read all, re-disable anything re-armed */
#ifdef SECWDT
	if (secwdt_ok) secwdt_clear("pre-jump");
#endif
#endif
	STEP(7, "cache clean to PoC, jumping to %llx with x0=%llx (watchdog %s)", U(kbase + text_off), U(dtb), wdt_state);
	dcache_civac_range(kbase, text_off + isize);
	dcache_civac_range(dtb, FDT_MAX);
	if (initrd) dcache_civac_range(initrd, pl.initrd_size);
	jump_kernel(kbase + text_off, dtb);
}
