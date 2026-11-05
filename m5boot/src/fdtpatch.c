#include "fdtpatch.h"
#include <libfdt.h>

#define TRY(x) do { int _r = (x); if (_r < 0) return _r; } while (0)

static int subnode(void *fdt, int parent, const char *name)
{
	int o = fdt_subnode_offset(fdt, parent, name);
	return o >= 0 ? o : fdt_add_subnode(fdt, parent, name);
}

int fdt_patch(const void *in, void *out, int outsize, const struct patch_in *p)
{
	char name[48];
	int o;
	TRY(fdt_open_into(in, out, outsize));
	void *fdt = out;

	/* /memory: drop every existing memory node, add ours */
	while ((o = fdt_node_offset_by_prop_value(fdt, -1, "device_type", "memory", 7)) >= 0)
		TRY(fdt_del_node(fdt, o));
	m5_snprintf(name, sizeof name, "memory@%llx", (unsigned long long)p->mem.base);
	TRY(o = fdt_add_subnode(fdt, 0, name));
	TRY(fdt_setprop_string(fdt, o, "device_type", "memory"));
	TRY(fdt_appendprop_addrrange(fdt, 0, o, "reg", p->mem.base, p->mem.size));

	/* /reserved-memory */
	int rm = fdt_path_offset(fdt, "/reserved-memory");
	if (rm < 0) {
		TRY(rm = fdt_add_subnode(fdt, 0, "reserved-memory"));
		TRY(fdt_setprop_u32(fdt, rm, "#address-cells", fdt_address_cells(fdt, 0)));
		TRY(fdt_setprop_u32(fdt, rm, "#size-cells", fdt_size_cells(fdt, 0)));
		TRY(fdt_setprop(fdt, rm, "ranges", 0, 0));
	}
	for (int i = 0; i < p->nrsv; i++) {
		m5_snprintf(name, sizeof name, "m5boot-rsv%d@%llx", i, (unsigned long long)p->rsv[i].base);
		TRY(o = fdt_add_subnode(fdt, rm, name));
		TRY(fdt_appendprop_addrrange(fdt, rm, o, "reg", p->rsv[i].base, p->rsv[i].size));
		TRY(fdt_setprop(fdt, o, "no-map", 0, 0));
	}

	/* /chosen */
	int ch;
	TRY(ch = subnode(fdt, 0, "chosen"));
	TRY(fdt_setprop_string(fdt, ch, "bootargs", p->bootargs));
	fdt_delprop(fdt, ch, "linux,initrd-start");
	fdt_delprop(fdt, ch, "linux,initrd-end");
	if (p->initrd_end > p->initrd_start) {
		TRY(fdt_setprop_u64(fdt, ch, "linux,initrd-start", p->initrd_start));
		TRY(fdt_setprop_u64(fdt, ch, "linux,initrd-end", p->initrd_end));
	}
	if (p->fb_base) {
		/* chosen has no #address-cells: ranges/cells inherited from root per simple-framebuffer
		 * binding examples; set them explicitly so reg is unambiguous. */
		TRY(fdt_setprop_u32(fdt, ch, "#address-cells", fdt_address_cells(fdt, 0)));
		TRY(fdt_setprop_u32(fdt, ch, "#size-cells", fdt_size_cells(fdt, 0)));
		TRY(fdt_setprop(fdt, ch, "ranges", 0, 0));
		/* Fill an existing simple-framebuffer placeholder under /chosen (the J714s DTB has a
		 * disabled framebuffer@0), else add one: never two framebuffer nodes on the same memory. */
		int found = -1;
		fdt_for_each_subnode(o, fdt, ch)
			if (!fdt_node_check_compatible(fdt, o, "simple-framebuffer")) { found = o; break; }
		if ((o = found) < 0) {
			m5_snprintf(name, sizeof name, "framebuffer@%llx", (unsigned long long)p->fb_base);
			TRY(o = fdt_add_subnode(fdt, ch, name));
			TRY(fdt_setprop_string(fdt, o, "compatible", "simple-framebuffer"));
		}
		fdt_delprop(fdt, o, "reg");
		TRY(fdt_appendprop_addrrange(fdt, ch, o, "reg", p->fb_base, (uint64_t)p->fb_stride * p->fb_h));
		TRY(fdt_setprop_u32(fdt, o, "width", p->fb_w));
		TRY(fdt_setprop_u32(fdt, o, "height", p->fb_h));
		TRY(fdt_setprop_u32(fdt, o, "stride", p->fb_stride));
		TRY(fdt_setprop_string(fdt, o, "format", p->fb_format));
		TRY(fdt_setprop_string(fdt, o, "status", "okay"));
	}
	return fdt_pack(fdt);
}
