# test vectors for tests/test_inflate.c: stored (level 0), fixed/dynamic (1, 9) blocks
import gzip, random
random.seed(1)
d = b"m5boot " * 5000 + bytes(random.getrandbits(8) for _ in range(70000)) + open('src/main.c', 'rb').read() * 3
open('build/t.raw', 'wb').write(d)
for l in (0, 1, 9): open(f'build/t{l}.gz', 'wb').write(gzip.compress(d, l))
