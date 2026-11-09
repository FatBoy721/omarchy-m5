#!/usr/bin/env python3
"""Prepare the local GPU loader without modifying vendor/m1n1 or known-good binaries.

The first six baseline patches reproduce the tracked vendor snapshot used for this
trial; 0009 then repairs its native boot-argument layout without changing vendor.
0005/0006 target a different (newer C USB/HV) source layout and are not applicable
to this pinned source. The GPU delta is MIT-licensed PR37 adaptation.
--simpledrm adds the explicit DCP handoff opt-out in a separate source tree.
Existing destinations are accepted only when their tracked files equal the recipe;
unrelated edits are never reset. Builds and hardware access are deliberately absent.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

BASE = "4184923ffb2dff079b384d6a32cc02142aa14572"
BASELINE = (
    "0001-t6050-kboot-bringup.patch",
    "0002-hv-gate-guest-timers-via-imask-when-vm-tmr-fiq-ena-is-locked.patch",
    "0003-string-provide-wcslen-for-llvm-loop-idioms.patch",
    "0004-chainload-ctrr-window-and-wdt-keep.patch",
    "0007-kboot-reserve-coprocessor-oslog-buffers-in-ram.patch",
    "0008-kboot-t6050-internal-dcp-handoff.patch",
    "0009-xnuboot-preserve-flat-commandline-layout.patch",
)


def git(path, *args):
    return subprocess.check_output(["git", "-C", str(path), *args])


def tracked_files(path):
    entries = {}
    for entry in git(path, "ls-files", "--stage", "-z").split(b"\0")[:-1]:
        info, name = entry.split(b"\t", 1)
        mode, oid, stage = info.split()
        if stage != b"0":
            raise SystemExit(f"Refusing unresolved index entries in {path}")
        entries[name] = (mode, oid)
    return entries


def signature(path):
    if path.is_symlink():
        return ("symlink", os.readlink(path))
    return (bool(path.stat().st_mode & 0o111), path.read_bytes())


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--simpledrm", action="store_true",
                        help="include the DCP opt-out in build/m1n1-gpu-simpledrm")
    args = parser.parse_args()
    default = "m1n1-gpu-simpledrm" if args.simpledrm else "m1n1-gpu"
    dest = (args.output or root / "build" / default).resolve()
    vendor = root / "vendor/m1n1"
    if dest == vendor.resolve() or vendor.resolve() in dest.parents:
        parser.error("output must not be vendor/m1n1 or inside it")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".m1n1-gpu-prepare-", dir=dest.parent) as tmp:
        prepared = Path(tmp) / "source"
        subprocess.run(["git", "clone", "--no-hardlinks", "--no-checkout", str(vendor), str(prepared)], check=True)
        git(prepared, "checkout", "--detach", BASE)
        for patch in BASELINE:
            git(prepared, "apply", "--binary", str(root / "patches/m1n1" / patch))
        git(prepared, "add", "-u")
        git(prepared, "-c", "user.name=Local GPU Trial", "-c", "user.email=local@localhost",
            "commit", "-m", "Snapshot reproducible local J714s loader baseline")
        git(prepared, "apply", "--binary", str(root / "patches/m1n1-gpu/0001-t6050-g17s-adt-handoff.patch"))
        if args.simpledrm:
            git(prepared, "apply", "--binary", str(root / "patches/m1n1-gpu/0002-kboot-t6050-simpledrm-only.patch"))
        if dest.exists():
            expected = tracked_files(prepared)
            actual = tracked_files(dest)
            if actual.keys() != expected.keys():
                raise SystemExit(f"Refusing changed tracked file set in {dest}; choose a fresh --output")
            for raw in expected:
                if expected[raw][0] == b"160000":
                    if actual[raw] != expected[raw]:
                        raise SystemExit(f"Refusing changed submodule pin: {os.fsdecode(raw)}")
                    continue
                name = os.fsdecode(raw)
                existing = dest / name
                if not existing.exists() and not existing.is_symlink():
                    raise SystemExit(f"Refusing missing tracked file: {existing}")
                if signature(existing) != signature(prepared / name):
                    raise SystemExit(f"Refusing unrelated/stale source changes: {existing}; choose a fresh --output")
            print(f"Existing isolated loader matches pinned recipe: {dest}")
        else:
            prepared.rename(dest)
            print(f"Prepared isolated loader: {dest}")
        print(f"Base: {BASE}; GPU source: omacom/m1n1 PR37 2bebfe7708c7077377ecc0d80d29bfb458335c0d")
        print("Display handoff: explicit simpledrm opt-out supported" if args.simpledrm
              else "Display handoff: original DCP behavior")


if __name__ == "__main__":
    main()
