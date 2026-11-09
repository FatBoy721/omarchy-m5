#!/usr/bin/env python3
"""Payload round-trip: mkpayload.build -> parse; writes build/test_payload.bin for test_core (C parser)."""
import sys, os, struct
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import mkpayload
code = b'\x11' * 100
dtb = b'D' * 33
image = bytearray(200); image[0x38:0x3c] = b'ARM\x64'; image = bytes(image)
initrd = b'I' * 77
blob = mkpayload.build(code, dtb, image, initrd)
got = mkpayload.parse(blob, len(code))
assert got == {'dtb': dtb, 'image': image, 'initrd': initrd}, got
assert blob[:100] == code
assert mkpayload.parse(mkpayload.build(code, dtb, image), len(code))['initrd'] == b''
open('build/test_payload.bin', 'wb').write(blob)
print('test_payload: ok')
