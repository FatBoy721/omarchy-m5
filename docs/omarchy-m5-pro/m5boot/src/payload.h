#pragma once
#include "util.h"
/* Payload appended after the m5boot code, at the 64-byte aligned end of m5boot.bin.
 * All fields little-endian; offsets relative to the header start. Built by tools/mkpayload.py.
 *   header (64 B): magic "M5BOOTPL", version u32 = 2, hdr_size u32 = 64,
 *                  u64 dtb_off, dtb_size, image_off, image_size, initrd_off, initrd_size
 *   blobs, each at a 64-byte aligned offset
 *   trailer (16 B) at align64(end of last blob): magic "M5PLEND!", u64 trailer offset.
 * The trailer proves the appended data really extends as far as the header claims. */
#define PAYLOAD_MAGIC	"M5BOOTPL"
#define PAYLOAD_TRAILER	"M5PLEND!"
#define PAYLOAD_VERSION	2
#define PAYLOAD_HDR_SIZE 64
#define PAYLOAD_MAX_BLOB (512ULL << 20)

struct payload { uint64_t dtb_off, dtb_size, image_off, image_size, initrd_off, initrd_size, total; };
/* avail = bytes readable from hdr (m5boot: up to physBase+memSize); nothing past it is read.
 * 0 ok; <0: -1 header, -2 blob field, -3 trailer, -4 missing dtb/image, -5 exceeds avail */
int payload_parse(const uint8_t *hdr, uint64_t avail, struct payload *p);
