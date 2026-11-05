#include "adt.h"
#include <string.h>

static int ok(const struct adt *a, uint64_t off, uint64_t n) { return off <= a->len && n <= a->len - off; }

/* offset of first child node, or <0 */
static int skip_props(const struct adt *a, int node)
{
	if (node < 0 || !ok(a, node, 8)) return -1;
	uint32_t np = rd32(a->base + node);
	uint64_t off = node + 8;
	for (uint32_t i = 0; i < np; i++) {
		if (!ok(a, off, 36)) return -1;
		uint32_t l = rd32(a->base + off + 32);
		if (!ok(a, off + 36, l)) return -1;
		off = (off + 36 + l + 3) & ~3ULL;
	}
	return off <= a->len ? (int)off : -1;
}

/* offset just past node (and its subtree), or <0 */
static int node_end(const struct adt *a, int node, int depth)
{
	if (depth > ADT_MAXDEPTH) return -1;
	int off = skip_props(a, node);
	if (off < 0) return -1;
	uint32_t nc = rd32(a->base + node + 4);
	for (uint32_t i = 0; i < nc && off >= 0; i++) off = node_end(a, off, depth + 1);
	return off;
}

int adt_prop_next(const struct adt *a, int node, int *it, const char **name, const uint8_t **val, uint32_t *len)
{
	if (node < 0 || !ok(a, node, 8)) return 0;
	uint32_t np = rd32(a->base + node);
	uint64_t off = node + 8;
	for (int i = 0; i < *it; i++) off = (off + 36 + rd32(a->base + off + 32) + 3) & ~3ULL;
	if ((uint32_t)*it >= np || !ok(a, off, 36)) return 0;
	uint32_t l = rd32(a->base + off + 32);
	if (!ok(a, off + 36, l) || !memchr(a->base + off, 0, 32)) return 0;
	*name = (const char *)a->base + off; *val = a->base + off + 36; *len = l;
	(*it)++;
	return 1;
}

int adt_prop(const struct adt *a, int node, const char *name, const uint8_t **val, uint32_t *len)
{
	int it = 0; const char *n;
	while (adt_prop_next(a, node, &it, &n, val, len))
		if (!strcmp(n, name)) return 0;
	return -1;
}

static int name_is(const struct adt *a, int node, const char *s, size_t sl)
{
	const uint8_t *v; uint32_t l;
	return !adt_prop(a, node, "name", &v, &l) && strnlen((const char *)v, l) == sl && !memcmp(v, s, sl);
}

static int child_n(const struct adt *a, int node, const char *s, size_t sl)
{
	int off = skip_props(a, node);
	if (off < 0) return -1;
	uint32_t nc = rd32(a->base + node + 4);
	for (uint32_t i = 0; i < nc && off >= 0; i++) {
		if (name_is(a, off, s, sl)) return off;
		off = node_end(a, off, 1);
	}
	return -1;
}

int adt_child(const struct adt *a, int node, const char *name) { return child_n(a, node, name, strlen(name)); }

int adt_path(const struct adt *a, const char *path, int *chain, int *depth)
{
	int node = 0, d = 0;
	chain[d++] = 0;
	while (*path) {
		while (*path == '/') path++;
		if (!*path) break;
		const char *e = path;
		while (*e && *e != '/') e++;
		if (d >= ADT_MAXDEPTH || (node = child_n(a, node, path, e - path)) < 0) return -1;
		chain[d++] = node;
		path = e;
	}
	*depth = d;
	return node;
}

static int has_compat(const struct adt *a, int node, const char *c)
{
	const uint8_t *v; uint32_t l;
	if (adt_prop(a, node, "compatible", &v, &l)) return 0;
	size_t cl = strlen(c);
	for (uint32_t o = 0; o < l;) {
		size_t sl = strnlen((const char *)v + o, l - o);
		if (sl == cl && !memcmp(v + o, c, cl)) return 1;
		o += sl + 1;
	}
	return 0;
}

static int find_rec(const struct adt *a, int node, const char *c, int *chain, int d, int *depth)
{
	if (d >= ADT_MAXDEPTH) return -1;
	chain[d] = node;
	if (has_compat(a, node, c)) { *depth = d + 1; return node; }
	int off = skip_props(a, node);
	if (off < 0) return -1;
	uint32_t nc = rd32(a->base + node + 4);
	for (uint32_t i = 0; i < nc && off >= 0; i++) {
		int r = find_rec(a, off, c, chain, d + 1, depth);
		if (r >= 0) return r;
		off = node_end(a, off, d + 1);
	}
	return -1;
}

int adt_find_compat(const struct adt *a, const char *c, int *chain, int *depth)
{
	return find_rec(a, 0, c, chain, 0, depth);
}

static int cells(const struct adt *a, int node, const char *name, uint32_t *out)
{
	const uint8_t *v; uint32_t l;
	if (adt_prop(a, node, name, &v, &l) || l != 4) return -1;	/* missing => error, never guess */
	*out = rd32(v);
	return (*out == 1 || *out == 2) ? 0 : -1;
}

static uint64_t rdcells(const uint8_t *p, uint32_t n) { return n == 2 ? rd64(p) : rd32(p); }

int adt_reg(const struct adt *a, const int *chain, int depth, int idx, uint64_t *addr, uint64_t *size)
{
	if (depth < 2) return -1;
	uint32_t ac, sc;
	if (cells(a, chain[depth - 2], "#address-cells", &ac) || cells(a, chain[depth - 2], "#size-cells", &sc)) return -1;
	const uint8_t *v; uint32_t l;
	if (adt_prop(a, chain[depth - 1], "reg", &v, &l)) return -1;
	uint32_t es = (ac + sc) * 4;
	if ((uint64_t)(idx + 1) * es > l) return -1;
	uint64_t x = rdcells(v + idx * es, ac), sz = rdcells(v + idx * es + ac * 4, sc);
	if (x + sz < x) return -1;
	/* Walk up: bus chain[k] (k >= 1) maps its child space to chain[k-1]'s space via "ranges". */
	for (int k = depth - 2; k >= 1; k--) {
		uint32_t cac, csc, pac;
		if (cells(a, chain[k], "#address-cells", &cac) || cells(a, chain[k], "#size-cells", &csc) ||
		    cells(a, chain[k - 1], "#address-cells", &pac)) return -1;
		if (adt_prop(a, chain[k], "ranges", &v, &l)) return -1;	/* no ranges below root: untranslatable */
		if (!l) continue;	/* empty ranges = identity */
		uint32_t rs = (cac + pac + csc) * 4;
		int hit = 0;
		for (uint32_t o = 0; o + rs <= l; o += rs) {
			uint64_t cb = rdcells(v + o, cac), pb = rdcells(v + o + cac * 4, pac);
			uint64_t rsz = rdcells(v + o + (cac + pac) * 4, csc);
			if (x - cb < rsz && sz <= rsz - (x - cb)) {
				uint64_t nx = x - cb + pb;
				if (nx < pb || nx + sz < nx) return -1;	/* overflow */
				x = nx; hit = 1; break;
			}
		}
		if (!hit) return -1;
	}
	*addr = x; *size = sz;
	return 0;
}

int adt_ranges16(const struct adt *a, int node, struct range *out, int max, int *skipped)
{
	int it = 0, n = 0; const char *name; const uint8_t *v; uint32_t l;
	*skipped = 0;
	while (adt_prop_next(a, node, &it, &name, &v, &l)) {
		if (!strcmp(name, "name")) continue;
		if (l != 16) { (*skipped)++; continue; }
		uint64_t b = rd64(v), s = rd64(v + 8);
		if (!s) continue;
		if (b + s < b) { (*skipped)++; continue; }	/* base+size overflows: malformed */
		if (n >= max) return -1;
		out[n].base = b; out[n].size = s; n++;
	}
	return n;
}
