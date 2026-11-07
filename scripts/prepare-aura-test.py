#!/usr/bin/env python3
"""Prepare the J714s RAM-only Aura bundle, or verify an existing bundle offline.

Build with make aura-test. No serial connection or boot-policy command is run.
The saved raw m1n1 rollback image must be identified on the Mac before enrollment.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tarfile


BOOT_LINUX = r'''#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
if [ "$#" -gt 1 ]; then echo "Usage: $0 [--single|--smp]" >&2; exit 2; fi
case "${1:---single}" in
    --single) cpus="maxcpus=1" ;;
    --smp) cpus="" ;;
    --help|-h) echo "Usage: $0 [--single|--smp] (RAM-only, no SSD root)"; exit 0 ;;
    *) echo "Usage: $0 [--single|--smp]" >&2; exit 2 ;;
esac
: "${AURADEVICE:?Set AURADEVICE to the target Aura serial device}"
PYTHON="${PYTHON:-python3}"
"$PYTHON" "$here/tools/bundle.py" --verify "$here"
# idle=nop is the arm64 option; idle=poll is not. Do not enable NV2/TSO here.
args="$cpus idle=nop arm64.nowfxt console=tty0 loglevel=8 keep_bootcon pd_ignore_unused clk_ignore_unused no_console_suspend rdinit=/init panic=0"
echo "RAM-only Linux diagnostic: $args"
echo "Aura linux.py also attempts secondary startup, even with maxcpus=1."
exec "$PYTHON" "$here/proxyclient/tools/linux.py" \
    "$here/boot/Image.gz" "$here/boot/t6050-j714s.dtb" \
    "$here/boot/initramfs.cpio.gz" -b "$args"
'''

PROBE_SMP = r'''#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
PYTHON="${PYTHON:-python3}"
if [ "${1:-}" != --help ] && [ "${1:-}" != -h ]; then
    : "${AURADEVICE:?Set AURADEVICE to the target Aura serial device}"
    "$PYTHON" "$here/tools/bundle.py" --verify "$here"
fi
export PYTHONPATH="$here/proxyclient"
exec "$PYTHON" "$here/tools/aura-smp.py" "$@"
'''


def wrapper(bundle):
    spec = importlib.util.spec_from_file_location(
        "macho_boot_object", bundle / "tools/macho_boot_object.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check_images(bundle):
    raw = (bundle / "boot/aura-stage1.bin").read_bytes()
    macho = (bundle / "boot/aura-boot.macho").read_bytes()
    # Compare the whole deterministic upstream encoding, not just its magic.
    # This checks the member, entry, x16 vectors, zero padding and absent BOOT_EXEC.
    if wrapper(bundle).wrap(raw) != macho:
        raise ValueError("Mach-O does not exactly wrap the paired raw Aura image")
    config = struct.pack("<16sII40s192sI", b"AURORA-S1-CFG01", 1, 0, b"", b"", 0)
    if raw.count(config[:16]) != 1 or config not in raw:
        raise ValueError("Aura Stage 1 is not an unconfigured proxy-only image")
    expected = {"#define CHAINLOADING", "#define BUILTIN_LOGO aurora"}
    if set((bundle / "aura-build-config.h").read_text().splitlines()) != expected:
        raise ValueError("unexpected Aura build flags (NV2/release/ESP Stage 2 must be off)")
    config_lines = (bundle / "kernel.config").read_text().splitlines()
    if "# CONFIG_OMARCHY_FB_MARKERS is not set" not in config_lines:
        raise ValueError("kernel still has fixed-address framebuffer markers")
    for symbol in ("ARM64", "SMP", "ARM_PSCI_FW", "BLK_DEV_INITRD", "RD_GZIP"):
        if f"CONFIG_{symbol}=y" not in config_lines:
            raise ValueError(f"kernel requires CONFIG_{symbol}=y")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify(bundle):
    for line in (bundle / "SHA256SUMS").read_text().splitlines():
        expected, name = line.split("  ", 1)
        path = Path(name)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError(f"invalid checksum path: {name}")
        if digest(bundle / path) != expected:
            raise ValueError(f"checksum mismatch: {name}")
    check_images(bundle)
    print("Verified bundle checksums and exact proxy-only Mach-O/raw pairing.")
    print("Native macOS kmutil inspect and hardware validation are still required.")


def prepare(repo, rollback):
    bundle = repo / "build/aura-test"
    aura = repo / "vendor/aura"
    required = [rollback, bundle / "boot/aura-stage1.bin", bundle / "boot/aura-boot.macho",
                bundle / "boot/Image.gz", bundle / "boot/t6050-j714s.dtb",
                bundle / "kernel.config", bundle / "aura-revision", bundle / "aura-build-config.h"]
    for path in required:
        if not path.is_file():
            raise ValueError(f"missing {path}; run make aura-test with a saved raw rollback image")
    revision = (bundle / "aura-revision").read_text().strip()
    actual = subprocess.check_output(["git", "-C", str(aura), "rev-parse", "HEAD"], text=True).strip()
    if revision != actual:
        raise ValueError("Aura checkout changed since building the image")
    compatible = subprocess.check_output(
        ["fdtget", "-t", "s", str(bundle / "boot/t6050-j714s.dtb"), "/", "compatible"], text=True)
    if "apple,j714s" not in compatible.split():
        raise ValueError("DTB is not the J714s board tree")

    (bundle / "tools").mkdir(exist_ok=True)
    (bundle / "rollback").mkdir(exist_ok=True)
    shutil.copy2(aura / "tools/macho_boot_object.py", bundle / "tools/macho_boot_object.py")
    check_images(bundle)
    shutil.copy2(rollback, bundle / "rollback/m1n1-stage1.bin")
    shutil.copy2(__file__, bundle / "tools/bundle.py")
    shutil.copy2(repo / "scripts/probes/aura-smp.py", bundle / "tools/aura-smp.py")
    shutil.copy2(aura / "requirements.txt", bundle / "requirements.txt")
    shutil.copytree(aura / "proxyclient", bundle / "proxyclient", dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    subprocess.run([sys.executable, str(repo / "scripts/mkinitramfs.py"), "--diagnostic",
                    "--out", str(bundle / "boot/initramfs.cpio.gz")], cwd=repo, check=True)
    for name, content in (("boot-linux.sh", BOOT_LINUX), ("probe-smp.sh", PROBE_SMP)):
        path = bundle / name
        path.write_text(content)
        path.chmod(0o755)
    (bundle / "manifest.json").write_text(json.dumps({
        "board": "J714s", "model": "Mac17,9", "chip_id": "0x6050", "board_id": "0x8",
        "aura_repository": "https://github.com/aurora-silicon/aura",
        "aura_revision": revision,
        "stage1": "unconfigured proxy-only Mach-O; no ESP target; NV2 off",
        "kernel": "isolated copy of our patched kernel/DT; fixed framebuffer markers disabled",
        "userspace": "RAM-only diagnostics; no root handoff or automatic USB gadget",
        "rollback_source": str(rollback.relative_to(repo) if rollback.is_relative_to(repo) else rollback),
        "rollback_status": "saved local raw image; verify it is the known-good Stage 1 before enrollment",
        "hardware_validation": "not performed by this builder",
    }, indent=2) + "\n")

    files = [bundle / name for name in ("manifest.json", "requirements.txt", "aura-revision",
              "aura-build-config.h", "kernel.config", "boot-linux.sh", "probe-smp.sh")]
    for name in ("boot", "rollback", "tools", "proxyclient"):
        files.extend(path for path in (bundle / name).rglob("*") if path.is_file()
                     and "__pycache__" not in path.parts and path.suffix != ".pyc")
    files.sort()
    (bundle / "SHA256SUMS").write_text("".join(
        f"{digest(path)}  {path.relative_to(bundle).as_posix()}\n" for path in files))
    verify(bundle)
    archive = repo / "build/aura-test.tar.gz"
    with tarfile.open(archive, "w:gz") as tf:
        for path in files + [bundle / "SHA256SUMS"]:
            tf.add(path, arcname=Path("aura-test") / path.relative_to(bundle), recursive=False)
    print(f"Prepared {bundle} and {archive}. Nothing enrolled or sent to the target.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rollback", type=Path,
                        help="enrolled raw Stage 1 to package for recovery (required when preparing)")
    parser.add_argument("--verify", type=Path, metavar="BUNDLE", help="verify only; never connect to hardware")
    args = parser.parse_args()
    if args.verify is None and args.rollback is None:
        parser.error("--rollback must identify the saved enrolled raw Stage 1")
    try:
        if args.verify is not None:
            verify(args.verify.resolve())
        else:
            repo = Path(__file__).resolve().parents[1]
            rollback = args.rollback if args.rollback.is_absolute() else repo / args.rollback
            prepare(repo, rollback.resolve())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"ERROR: {error}\n")


if __name__ == "__main__":
    main()
