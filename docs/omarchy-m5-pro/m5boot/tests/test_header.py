#!/usr/bin/env python3
"""Task 07 host test: every 32-bit word in [0, 0x800) of each image is an A64 `B imm26` landing on 0x800,
the word at 0x800 is not a branch-to-self/zero, and the file size is a multiple of 16 KiB."""
import struct, sys
for path in sys.argv[1:]:
    b = open(path, 'rb').read()
    assert len(b) % 0x4000 == 0, f'{path}: size {len(b)} not a multiple of 16 KiB'
    for off in range(0, 0x800, 4):
        w, = struct.unpack_from('<I', b, off)
        assert w >> 26 == 0b000101, f'{path}: word at {off:#x} = {w:#010x} is not B'
        imm = w & 0x3ffffff
        imm = imm - (1 << 26) if imm & (1 << 25) else imm
        assert off + imm * 4 == 0x800, f'{path}: B at {off:#x} lands at {off + imm * 4:#x}'
    first, = struct.unpack_from('<I', b, 0x800)
    assert first == 0xd5034fdf, f'{path}: entry word {first:#010x} is not msr daifset,#0xf'
    print(f'test_header: ok {path} ({len(b)} bytes)')
