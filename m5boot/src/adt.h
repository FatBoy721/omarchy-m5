#pragma once
#include "util.h"

/* Apple Device Tree reader. Format per XNU pexpert/pexpert/device_tree.h @f6217f89:
 * node = {u32 nProperties, u32 nChildren} + props + children;
 * prop = {char name[32], u32 length} + value, next at (prop+36+length+3)&~3. Little-endian.
 * Nodes are byte offsets into the blob; every access is bounds-checked (<0 = error). */
#define ADT_MAXDEPTH 16

struct adt { const uint8_t *base; uint32_t len; };

int adt_prop(const struct adt *a, int node, const char *name, const uint8_t **val, uint32_t *len);
/* Iterate props: start with *it = 0; returns 1 while there are more. */
int adt_prop_next(const struct adt *a, int node, int *it, const char **name, const uint8_t **val, uint32_t *len);
int adt_child(const struct adt *a, int node, const char *name);
/* Path like "/arm-io/wdt" from root (offset 0). Fills chain[0..*depth-1] = root..node. */
int adt_path(const struct adt *a, const char *path, int *chain, int *depth);
/* First node (DFS) whose compatible list contains compat. Fills chain like adt_path. */
int adt_find_compat(const struct adt *a, const char *compat, int *chain, int *depth);
/* reg[idx] of chain[depth-1], translated through every ancestor's "ranges" to a CPU PA. */
int adt_reg(const struct adt *a, const int *chain, int depth, int idx, uint64_t *addr, uint64_t *size);
/* Collect {u64 base,u64 size} values from all props of node (skips "name" and non-16-byte values,
 * and zero sizes). Returns count, or <0. */
int adt_ranges16(const struct adt *a, int node, struct range *out, int max, int *skipped);
