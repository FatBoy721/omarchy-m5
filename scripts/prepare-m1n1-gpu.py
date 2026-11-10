#!/usr/bin/env python3
"""Prepare the local GPU loader without modifying vendor/m1n1 or known-good binaries.

The first six baseline patches reproduce the tracked vendor snapshot used for this
trial; 0009 then repairs its native boot-argument layout without changing vendor.
0005/0006 target a different (newer C USB/HV) source layout and are not applicable
to this pinned source. The GPU delta is MIT-licensed PR37 adaptation.
--simpledrm adds the explicit DCP handoff opt-out in a separate source tree.
--standalone additionally embeds the existing validated profile from --adt in a
private native-loader tree; no raw ADT or second hand-edited profile is published.
Existing destinations are accepted only when their tracked files equal the recipe;
unrelated edits are never reset. Builds and hardware access are deliberately absent.
"""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
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


def profile_header(root, source, capture):
    """Generate byte-exact native checks only after the existing SHA256 gate passes."""
    spec = importlib.util.spec_from_file_location(
        "gpu_preflight", root / "scripts/probes/gpu-preflight.py")
    preflight = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(source / "proxyclient"))
    try:
        spec.loader.exec_module(preflight)
        tree = preflight.validate(capture.read_bytes())
    finally:
        sys.path.pop(0)
    chosen = preflight.properties(preflight.child(tree, "chosen"))
    sgx = preflight.properties(preflight.child(preflight.child(tree, "arm-io"), "sgx"))
    entries = [(0, "model", preflight.properties(tree)["model"])]
    entries += [(1, name, chosen[name])
                for name in ("firmware-version", "system-firmware-version")]
    entries += [(2, name, sgx[name]) for name in preflight.PERF_SHA256]
    lines = [
        "/* Generated from an ADT accepted by scripts/probes/gpu-preflight.py. */",
        "/* Private build input: never hand-edit or publish the raw ADT. */",
        "struct t6050_gpu_profile_property {",
        "    unsigned node;",
        "    const char *name;",
        "    const unsigned char *value;",
        "    u32 length;",
        "};",
    ]
    for index, (_, _, value) in enumerate(entries):
        lines.append(f"static const unsigned char gpu_profile_{index}[] = {{")
        for start in range(0, len(value), 16):
            lines.append("    " + ", ".join(f"0x{byte:02x}" for byte in value[start:start + 16]) + ",")
        lines.append("};")
    lines.append("static const struct t6050_gpu_profile_property t6050_gpu_profile[] = {")
    for index, (node, name, value) in enumerate(entries):
        lines.append(f'    {{{node}, "{name}", gpu_profile_{index}, {len(value)}}},')
    lines.append("};")
    return "\n".join(lines) + "\n"


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--simpledrm", action="store_true",
                        help="include the DCP opt-out in build/m1n1-gpu-simpledrm")
    parser.add_argument("--n1", action="store_true",
                        help="add the DT-only N1 kernel-train hand-off in build/m1n1-gpu-n1 "
                             "(build/m1n1-gpu-n1-standalone with --standalone)")
    parser.add_argument("--standalone", action="store_true",
                        help="prepare the calibrated self-contained GPU simpledrm loader")
    parser.add_argument("--adt", type=Path, help="private saved runtime ADT for --standalone")
    parser.add_argument("--storage", action="store_true",
                        help="with --standalone: read the kernel payload from a file on storage "
                             "(payload=...) in build/m1n1-gpu-n1-esp; build it with CHAINLOADING=1")
    parser.add_argument("--stage1", action="store_true",
                        help="only the baseline, no GPU hand-off, in build/m1n1-stage1: the small "
                             "object to enroll, which chainloads the real loader from storage")
    parser.add_argument("--chainload", metavar="SPEC",
                        help="with --stage1: the '<partition uuid>;<path>' it chainloads, compiled "
                             "into the image (nothing may be appended to an enrolled object)")
    args = parser.parse_args()
    if args.stage1 and (args.simpledrm or args.n1 or args.standalone or args.storage):
        parser.error("--stage1 is the plain baseline and takes no other variant")
    if bool(args.stage1) != bool(args.chainload):
        parser.error("--stage1 and --chainload go together")
    if args.chainload and not re.fullmatch(r"[0-9a-fA-F-]{36};[\w./-]+", args.chainload):
        parser.error("--chainload is <partition uuid>;<path>")
    if args.standalone and (not args.simpledrm or args.adt is None):
        parser.error("--standalone requires --simpledrm and --adt")
    if args.adt is not None and not args.standalone:
        parser.error("--adt is only used with --standalone")
    if args.n1 and not args.simpledrm:
        parser.error("--n1 requires --simpledrm")
    if args.storage and not args.standalone:
        parser.error("--storage requires --standalone")
    default = ("m1n1-stage1" if args.stage1 else
               "m1n1-gpu-n1-esp" if args.storage and args.n1 else
               "m1n1-gpu-esp" if args.storage else
               "m1n1-gpu-n1-standalone" if args.standalone and args.n1 else
               "m1n1-gpu-standalone" if args.standalone else
               "m1n1-gpu-n1" if args.n1 else
               "m1n1-gpu-simpledrm" if args.simpledrm else "m1n1-gpu")
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
        target_path = Path("src/stage1_chainload.h")
        if args.stage1:
            git(prepared, "apply", "--binary",
                str(root / "patches/m1n1-stage1/0001-payload-built-in-chainload-target.patch"))
            (prepared / target_path).write_text(
                "/* Written by scripts/prepare-m1n1-gpu.py --stage1 --chainload. */\n"
                f'#define STAGE1_CHAINLOAD "{args.chainload}"\n')
        else:
            git(prepared, "apply", "--binary", str(root / "patches/m1n1-gpu/0001-t6050-g17s-adt-handoff.patch"))
        if args.simpledrm:
            git(prepared, "apply", "--binary", str(root / "patches/m1n1-gpu/0002-kboot-t6050-simpledrm-only.patch"))
        if args.n1:
            git(prepared, "apply", "--binary",
                str(root / "patches/m1n1-gpu/0004-kboot-t6050-n1-kernel-train-handoff.patch"))
            # Track the two added sources so an existing tree is compared in full.
            git(prepared, "add", "src/kboot_n1.c", "src/kboot_n1.h")
        profile_path = Path("src/t6050_gpu_profile.h")
        if args.standalone:
            git(prepared, "apply", "--binary",
                str(root / "patches/m1n1-gpu/0003-t6050-standalone-gpu-profile.patch"))
            (prepared / profile_path).write_text(profile_header(root, prepared, args.adt))
        if args.storage:
            git(prepared, "apply", "--binary",
                str(root / "patches/m1n1-gpu/0005-payload-load-the-kernel-payload-from-storage.patch"))
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
            generated = ([(profile_path, "native calibration")] if args.standalone else []) + \
                        ([(target_path, "chainload target")] if args.stage1 else [])
            for path, what in generated:
                existing = dest / path
                if (existing.is_symlink() or not existing.is_file() or
                        existing.read_bytes() != (prepared / path).read_bytes()):
                    raise SystemExit(f"Refusing missing/changed {what}: {existing}")
            print(f"Existing isolated loader matches pinned recipe: {dest}")
        else:
            prepared.rename(dest)
            print(f"Prepared isolated loader: {dest}")
        if args.stage1:
            print(f"Base: {BASE}; baseline patches only (no GPU, display or N1 hand-off changes)")
            print(f"Chainload target, inside the image: {args.chainload}")
            return
        print(f"Base: {BASE}; GPU source: omacom/m1n1 PR37 2bebfe7708c7077377ecc0d80d29bfb458335c0d")
        print("Display handoff: explicit simpledrm opt-out supported" if args.simpledrm
              else "Display handoff: original DCP behavior")
        if args.standalone:
            print("Native GPU admission: seven byte-exact properties from the validated private ADT")
        if args.storage:
            print("Kernel payload: payload=<partition uuid>;<path> on storage (CHAINLOADING=1 build)")


if __name__ == "__main__":
    main()
