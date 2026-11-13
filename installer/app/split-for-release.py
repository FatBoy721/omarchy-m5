#!/usr/bin/env python3
"""Split a file for a GitHub release (2 GiB asset cap) the way the image releases are split.

usage: split-for-release.py FILE [CHUNK_MIB]

Writes FILE.part0, FILE.part1, ... (CHUNK_MIB MiB each, default 1900, the
last one shorter) and appends `<sha256>  <name>` lines for every part and for
FILE itself to SHA256SUMS beside FILE, the format `shasum -a 256 -c` reads
(run it to check the parts on disk). A file no larger than one chunk is not
split; only its line is written. FILE is left in place.
"""
import hashlib
from pathlib import Path
import sys

BLOCK = 8 * 1024 * 1024


def main() -> None:
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__.strip().splitlines()[2])
    path = Path(sys.argv[1])
    chunk = int(sys.argv[2] if len(sys.argv) == 3 else 1900) * 1024 * 1024
    if path.is_symlink() or not path.is_file() or chunk <= 0:
        raise SystemExit("split-for-release: need a regular file and a positive chunk size")
    size = path.stat().st_size
    whole = hashlib.sha256()
    lines = []
    if size > chunk:
        index = 0
        with path.open("rb") as source:
            while True:
                part = path.with_name(f"{path.name}.part{index}")
                if part.exists():
                    raise SystemExit(f"split-for-release: {part} exists")
                digest = hashlib.sha256()
                written = 0
                with part.open("xb") as target:
                    while written < chunk and (block := source.read(min(BLOCK, chunk - written))):
                        target.write(block)
                        digest.update(block)
                        whole.update(block)
                        written += len(block)
                if written == 0:
                    part.unlink()
                    break
                lines.append(f"{digest.hexdigest()}  {part.name}")
                print(part)
                index += 1
    else:
        with path.open("rb") as source:
            while block := source.read(BLOCK):
                whole.update(block)
    lines.append(f"{whole.hexdigest()}  {path.name}")
    with path.with_name("SHA256SUMS").open("a") as sums:
        sums.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
