#!/usr/bin/env python3
"""Decode a raw 32bpp FB dump back to text using our own font (src/font8x16.c). Usage: fbtext.py raw W H"""
import re, sys
glyphs = [bytes(int(x, 16) for x in m.split(',')) for m in re.findall(r'\{(0x[^}]*)\}', open('src/font8x16.c').read())]
lut = {g: chr(32 + i) for i, g in reversed(list(enumerate(glyphs)))}
d = open(sys.argv[1], 'rb').read(); W, H = int(sys.argv[2]), int(sys.argv[3])
for r in range(H // 16):
    line = ''
    for c in range(W // 8):
        g = bytes(sum(0x80 >> x for x in range(8) if d[((r*16+y)*W + c*8+x)*4:((r*16+y)*W + c*8+x)*4+3] == b'\xff\xff\xff') for y in range(16))
        line += lut.get(g, '#')
    if line.strip(): print(line.rstrip())
