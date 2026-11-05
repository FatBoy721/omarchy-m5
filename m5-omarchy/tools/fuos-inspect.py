#!/usr/bin/env python3
"""fuos-inspect.py — identify the container format of the fuOS object kmutil stored, and compare it with our raw file.
Usage: fuos-inspect.py STORED_FILE [OUR_RAW_BOOT_BIN]
Handles: IMG4 (SEQUENCE 'IMG4' { IM4P, [0] IM4M, [1] IM4R }), bare IM4P (SEQUENCE 'IM4P', type, desc, OCTET STRING payload,
[opt] SEQUENCE{algo, size} compression), LZFSE/LZVN 'bvx' payloads (reports only), 'complzss', and Mach-O 64 (load commands).
Stdlib only. Read-only. Prints no ECID/nonce values (IM4M/IM4R are reported by size only)."""
import hashlib, struct, sys

def der(b, i):
    """parse one DER TLV at i -> (tag, value_start, value_end)"""
    tag = b[i]; i += 1
    n = b[i]; i += 1
    if n & 0x80:
        k = n & 0x7f; n = int.from_bytes(b[i:i+k], 'big'); i += k
    return tag, i, i + n

def children(b, s, e):
    out, i = [], s
    while i < e:
        t, vs, ve = der(b, i); out.append((t, vs, ve)); i = ve
    return out

def macho(p, label):
    magic = struct.unpack_from('<I', p, 0)[0]
    if magic != 0xfeedfacf:
        print(f"  {label}: not Mach-O 64 (first u32 0x{magic:08x})"); return
    cpu, sub, ftype, ncmds, sizeofcmds, flags = struct.unpack_from('<iiIIII', p, 4)
    print(f"  {label}: Mach-O 64 cputype=0x{cpu & 0xffffffff:x} filetype={ftype} ncmds={ncmds} sizeofcmds={sizeofcmds} flags=0x{flags:x}")
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', p, off)
        if cmd == 0x19:   # LC_SEGMENT_64
            name = p[off+8:off+24].split(b'\0')[0].decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', p, off+24)
            maxp, initp, nsects, fl = struct.unpack_from('<iiII', p, off+56)
            print(f"    LC_SEGMENT_64 {name:16s} vmaddr=0x{vmaddr:x} vmsize=0x{vmsize:x} fileoff=0x{fileoff:x} filesize=0x{filesize:x} prot={initp}/{maxp} nsects={nsects}")
        elif cmd == 0x5:  # LC_UNIXTHREAD: flavor, count, then arm64 thread state; pc is x[0..28],fp,lr,sp,pc
            flavor, count = struct.unpack_from('<II', p, off+8)
            pc = struct.unpack_from('<Q', p, off+16+32*8)[0] if count >= 68 else None
            print(f"    LC_UNIXTHREAD flavor={flavor} count={count} pc=0x{pc:x}" if pc is not None else f"    LC_UNIXTHREAD flavor={flavor} count={count}")
        elif cmd == 0x80000028:
            eo, ss = struct.unpack_from('<QQ', p, off+8); print(f"    LC_MAIN entryoff=0x{eo:x} stacksize=0x{ss:x}")
        else:
            print(f"    cmd 0x{cmd:x} size {size}")
        off += size

def payload_info(pl, comp, ours):
    print(f"  payload: {len(pl)} B sha256 {hashlib.sha256(pl).hexdigest()}")
    head = pl[:4]
    if head in (b'bvx2', b'bvx1', b'bvxn', b'bvx-'):
        print(f"  payload is LZFSE/LZVN-compressed ({head.decode()}); decompress on macOS (compression_tool) to inspect further")
    elif pl[:8] == b'complzss':
        print("  payload is LZSS-compressed ('complzss')")
    else:
        macho(pl, 'payload')
    if comp:
        print(f"  IM4P compression info: algo={comp[0]} uncompressed_size={comp[1]}")
    if ours is not None:
        print(f"  ours: {len(ours)} B sha256 {hashlib.sha256(ours).hexdigest()}")
        print(f"  payload == our raw file: {pl == ours}")
        if pl != ours:
            idx = pl.find(ours[0x800:0x800+256])
            print(f"  our bytes at our offset 0x800 found in payload at offset: {hex(idx) if idx >= 0 else 'not found (compressed or wrapped)'}")

def im4p(b, s, e, ours):
    kids = children(b, s, e)
    strs = [b[vs:ve].decode('ascii', 'replace') for t, vs, ve in kids if t == 0x16]
    print(f"  IM4P fields: {strs}")
    octets = [(vs, ve) for t, vs, ve in kids if t == 0x04]
    comp = None
    for t, vs, ve in kids:
        if t == 0x30:
            ints = [int.from_bytes(b[a:z], 'big') for tt, a, z in children(b, vs, ve) if tt == 0x02]
            if len(ints) >= 2: comp = ints[:2]
    if octets:
        vs, ve = octets[0]; payload_info(b[vs:ve], comp, ours)

def main():
    b = open(sys.argv[1], 'rb').read()
    ours = open(sys.argv[2], 'rb').read() if len(sys.argv) > 2 else None
    print(f"stored: {sys.argv[1]}  {len(b)} B  sha256 {hashlib.sha256(b).hexdigest()}")
    print(f"  first 16 bytes: {b[:16].hex()}")
    if b[0] == 0x30:
        t, vs, ve = der(b, 0); kids = children(b, vs, ve)
        first = b[kids[0][1]:kids[0][2]] if kids and kids[0][0] == 0x16 else b''
        print(f"  DER SEQUENCE, first IA5String = {first!r}, {len(kids)} elements, DER length {ve} of {len(b)} B")
        if first == b'IMG4':
            for t, a, z in kids[1:]:
                if t == 0x30 and b[a:a+20].find(b'IM4P') >= 0:
                    print("  IMG4 contains IM4P:"); im4p(b, a, z, ours)
                else:
                    print(f"  IMG4 element tag 0x{t:x} ({z - a} B; IM4M/IM4R content not printed)")
        elif first == b'IM4P':
            im4p(b, vs, ve, ours)
        elif first == b'IM4M':
            print("  this is an IM4M manifest (content not printed)")
    else:
        macho(b, 'stored')
        if ours is not None:
            print(f"  stored == our raw file: {b == ours}")

if __name__ == '__main__':
    main()
