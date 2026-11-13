#!/usr/bin/env python3
"""Write the release-inputs directory for a J714s developer build of the installer app.

The app trusts one Ed25519 key, ours, and reads one sealed catalog that lists
only apple,j714s (a `developer` board of the installer tree's
scripts/supported-models.json). This writes what Packaging/build-app.sh needs:

  OUTPUT/release.json            scripts/make-release-descriptor --adhoc
  OUTPUT/trust-root.ed25519.pub  our 32-byte public key
  OUTPUT/catalog.json            scripts/make-unsigned-catalog.py --developer-only
  OUTPUT/catalog.json.sig        64-byte Ed25519 signature of catalog.json
  OUTPUT/offline-artifacts/      offline mode only: engine, metadata, payload

Two modes:

  offline  the engine, installer_data.json and the whole OS package are
           embedded in the app (OMARCHY_OFFLINE_BUILD=1); the catalog's URLs
           are informational.
  online   only the engine is in the app; the catalog points the metadata and
           the split OS package (.part0, .part1, ...) at the image release, and
           the app downloads and checks every part, then the whole file.

The signing key is a 32-byte Ed25519 seed, raw or base64, read from
--key-file or from the environment variable named by --key-env (CI:
J714S_CATALOG_KEY). It is never written anywhere by this script, except to a
0600 temporary file that is removed at once when the swift signer is used.
`--generate-throwaway-key` makes a key nobody keeps, for dry runs.

Signing uses the Python `cryptography` package when it imports; otherwise
the installer tree's scripts/catalog-signing.swift (macOS only).
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

BOARD = "apple,j714s"
DEVICE_CLASS = "j714sap"
READ_BLOCK = 8 * 1024 * 1024
VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
EVIDENCE = re.compile(r"^[0-9a-z.-]+$")
PART = re.compile(r"\.part([0-9]+)$")


def fail(message: str) -> None:
    raise SystemExit(f"make-release-inputs: {message}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(READ_BLOCK):
            digest.update(block)
    return digest.hexdigest()


def regular(path: Path, what: str) -> Path:
    if path.is_symlink() or not path.is_file() or path.stat().st_size <= 0:
        fail(f"{what} is missing, empty or a symlink: {path}")
    return path


def https_base(value: str, what: str) -> str:
    if not re.fullmatch(r"https://[^/\s]+(/[^\s]*)?", value) or value.endswith("/"):
        fail(f"{what} must be an https URL without a trailing slash: {value}")
    return value


# --- keys -------------------------------------------------------------------

def read_seed(arguments: argparse.Namespace) -> bytes:
    if arguments.generate_throwaway_key:
        return os.urandom(32)
    if arguments.key_file:
        raw = Path(arguments.key_file).read_bytes()
    elif arguments.key_env:
        text = os.environ.get(arguments.key_env, "")
        if not text:
            fail(f"environment variable {arguments.key_env} is empty")
        raw = text.encode()
    else:
        fail("give --key-file, --key-env or --generate-throwaway-key")
    if len(raw) != 32:
        try:
            raw = base64.b64decode(raw.strip(), validate=True)
        except ValueError:
            fail("the key is neither 32 raw bytes nor base64")
    if len(raw) != 32:
        fail("the key must be a 32-byte Ed25519 seed")
    return raw


class Signer:
    """Ed25519 with `cryptography`, or the installer tree's swift tool."""

    def __init__(self, seed: bytes, tree: Path):
        self.seed = seed
        self.tree = tree
        try:
            from cryptography.hazmat.primitives.asymmetric import ed25519
            from cryptography.hazmat.primitives import serialization
        except ImportError:
            self.key = None
            if not shutil.which("xcrun"):
                fail("no Ed25519 signer: install the Python cryptography package, or run on macOS")
            self.public = self._swift_public()
        else:
            self.key = ed25519.Ed25519PrivateKey.from_private_bytes(seed)
            self.public = self.key.public_key().public_bytes(
                serialization.Encoding.Raw, serialization.PublicFormat.Raw
            )
        if len(self.public) != 32:
            fail("public key is not 32 bytes")

    def _swift(self, *arguments: str) -> None:
        subprocess.run(
            ["xcrun", "swift", str(self.tree / "scripts/catalog-signing.swift"), *arguments],
            check=True, stdout=sys.stderr,
        )

    def _with_key_file(self, action):
        with tempfile.TemporaryDirectory(prefix="j714s-sign-") as temporary:
            key = Path(temporary) / "key"
            descriptor = os.open(key, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            try:
                os.write(descriptor, self.seed)
            finally:
                os.close(descriptor)
            try:
                return action(key, Path(temporary))
            finally:
                key.unlink()

    def _swift_public(self) -> bytes:
        # catalog-signing.swift has no "public key of this seed" command, so
        # derive it with a three-line CryptoKit program.
        def run(key: Path, temporary: Path) -> bytes:
            program = temporary / "public.swift"
            program.write_text(
                "import CryptoKit\nimport Foundation\n"
                "let a = CommandLine.arguments\n"
                "let k = try Curve25519.Signing.PrivateKey(rawRepresentation: try Data(contentsOf: URL(fileURLWithPath: a[1])))\n"
                "try k.publicKey.rawRepresentation.write(to: URL(fileURLWithPath: a[2]))\n"
            )
            output = temporary / "public"
            subprocess.run(["xcrun", "swift", str(program), str(key), str(output)], check=True, stdout=sys.stderr)
            return output.read_bytes()

        return self._with_key_file(run)

    def sign(self, message: Path, signature: Path) -> None:
        if self.key is not None:
            signature.write_bytes(self.key.sign(message.read_bytes()))
        else:
            self._with_key_file(lambda key, _: self._swift("sign", str(key), str(message), str(signature)))
        if signature.stat().st_size != 64:
            fail("catalog signature is not 64 bytes")

    def verify(self, public: Path, message: Path, signature: Path) -> None:
        if self.key is not None:
            from cryptography.hazmat.primitives.asymmetric import ed25519
            from cryptography.exceptions import InvalidSignature
            try:
                ed25519.Ed25519PublicKey.from_public_bytes(public.read_bytes()).verify(
                    signature.read_bytes(), message.read_bytes()
                )
            except InvalidSignature:
                fail("catalog signature does not verify against the trust root")
        else:
            self._swift("verify", str(public), str(message), str(signature))


# --- inputs -----------------------------------------------------------------

def check_tree(tree: Path) -> dict:
    manifest = json.loads((tree / "scripts/supported-models.json").read_text())
    if BOARD not in manifest.get("developer", {}):
        fail(f"{tree} does not list {BOARD} as a developer board (apply installer/patches-j714s)")
    for name in ("scripts/make-unsigned-catalog.py", "scripts/make-release-descriptor"):
        regular(tree / name, name)
    if "--developer-only" not in (tree / "scripts/make-unsigned-catalog.py").read_text():
        fail("the tree's make-unsigned-catalog.py has no --developer-only")
    return json.loads((tree / "Engine/source-lock.json").read_text())


def check_engine(engine: Path, lock: dict) -> None:
    pinned = lock["validation_artifact"]
    if engine.name != pinned["filename"]:
        fail(f"engine must be named {pinned['filename']}, not {engine.name}")
    if engine.stat().st_size != pinned["size_bytes"] or sha256(engine) != pinned["sha256"]:
        fail("engine archive is not the one Engine/source-lock.json pins")


def check_metadata(metadata: Path, payload_name: str) -> None:
    if metadata.name != "installer_data.json":
        fail("metadata must be named installer_data.json")
    os_list = json.loads(metadata.read_text()).get("os_list")
    if not isinstance(os_list, list) or len(os_list) != 1:
        fail("installer_data.json must describe exactly one OS")
    entry = os_list[0]
    if entry.get("allowed_device_classes") != [DEVICE_CLASS]:
        fail(f"installer_data.json is not a {DEVICE_CLASS}-only image")
    if entry.get("package") != payload_name:
        fail(f"installer_data.json names the package {entry.get('package')!r}, not {payload_name!r}")


def check_parts(payload: Path, parts: list[Path]) -> list[dict]:
    """Prove the parts concatenate into the payload; return their records."""
    if not 2 <= len(parts) <= 16:
        fail("the app accepts 2 to 16 payload parts")
    indices = []
    for part in parts:
        match = PART.search(part.name)
        if not match:
            fail(f"not a .partN file: {part.name}")
        indices.append(int(match.group(1)))
    if indices != list(range(len(parts))):
        fail("payload parts must be given in order, .part0 first, with no gaps")
    whole = hashlib.sha256()
    records = []
    for part in parts:
        regular(part, "payload part")
        digest = hashlib.sha256()
        with part.open("rb") as stream:
            while block := stream.read(READ_BLOCK):
                digest.update(block)
                whole.update(block)
        records.append({"fileName": part.name, "sizeBytes": part.stat().st_size,
                        "sha256": "sha256:" + digest.hexdigest()})
    if sum(record["sizeBytes"] for record in records) != payload.stat().st_size:
        fail("payload parts do not add up to the payload size")
    if whole.hexdigest() != sha256(payload):
        fail("payload parts do not concatenate into the payload")
    return records


def place(source: Path, target: Path, link: bool) -> None:
    if link:
        try:
            os.link(source, target)
            return
        except OSError:
            pass
    shutil.copyfile(source, target)


# --- main -------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tree", type=Path, required=True, help="patched installer tree (with patches-j714s)")
    parser.add_argument("--mode", choices=("offline", "online"), required=True)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True, help="the image's installer_data.json")
    parser.add_argument("--payload", type=Path, required=True, help="the whole, reassembled OS package zip")
    parser.add_argument("--payload-part", type=Path, action="append", default=[],
                        help="online: each published part, in order (repeat)")
    parser.add_argument("--image-base-url", help="online: download base of the image release (parts, installer_data.json)")
    parser.add_argument("--download-base-url", required=True,
                        help="download base of the app release: engine URL, installer.downloadURL")
    parser.add_argument("--catalog-base-url", required=True,
                        help="release.json channel base (never fetched: the catalog is sealed)")
    parser.add_argument("--app-version", required=True, help="the app's CFBundleShortVersionString")
    parser.add_argument("--evidence-revision", required=True)
    parser.add_argument("--downstream-revision", help="40-hex commit; default: the tree's HEAD")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--link", action="store_true", help="hard-link offline artifacts instead of copying")
    parser.add_argument("--now", help="catalog issue time YYYY-MM-DDTHH:MM:SSZ (tests)")
    key = parser.add_mutually_exclusive_group(required=True)
    key.add_argument("--key-file", help="32-byte seed, raw or base64")
    key.add_argument("--key-env", help="environment variable holding the base64 seed")
    key.add_argument("--generate-throwaway-key", action="store_true")
    arguments = parser.parse_args()

    tree = arguments.tree.resolve()
    lock = check_tree(tree)
    engine = regular(arguments.engine, "engine")
    metadata = regular(arguments.metadata, "installer_data.json")
    payload = regular(arguments.payload, "payload")
    check_engine(engine, lock)
    check_metadata(metadata, payload.name)
    download_base = https_base(arguments.download_base_url, "--download-base-url")
    https_base(arguments.catalog_base_url, "--catalog-base-url")
    if not VERSION.match(arguments.app_version):
        fail("--app-version must look like X.Y.Z")
    minimum = lock["downstream_overlay"].get("minimum_app_version", "2.1.0")
    if tuple(map(int, arguments.app_version.split("."))) < tuple(map(int, minimum.split("."))):
        fail(f"the pinned engine needs app {minimum} or later; --app-version is {arguments.app_version}")
    if not EVIDENCE.match(arguments.evidence_revision):
        fail("--evidence-revision must be lowercase [0-9a-z.-]")
    downstream = arguments.downstream_revision or subprocess.run(
        ["git", "-C", str(tree), "rev-parse", "HEAD"], check=True, capture_output=True, text=True
    ).stdout.strip()
    if not re.fullmatch(r"[0-9a-f]{40}", downstream):
        fail("--downstream-revision must be a 40-hex commit")
    parts = []
    if arguments.mode == "online":
        if not arguments.payload_part or not arguments.image_base_url:
            fail("online mode needs --payload-part (each part) and --image-base-url")
        image_base = https_base(arguments.image_base_url, "--image-base-url")
        parts = check_parts(payload, arguments.payload_part)
    elif arguments.payload_part or arguments.image_base_url:
        fail("offline mode embeds the whole payload: no --payload-part or --image-base-url")

    output = arguments.output
    if output.exists() or output.is_symlink():
        fail(f"refusing to overwrite {output}")
    signer = Signer(read_seed(arguments), tree)
    output.mkdir(parents=True)
    trust_root = output / "trust-root.ed25519.pub"
    trust_root.write_bytes(signer.public)

    subprocess.run(
        ["bash", str(tree / "scripts/make-release-descriptor"), "--public-key", str(trust_root),
         "--output", str(output / "release.json"), "--base-url", arguments.catalog_base_url, "--adhoc"],
        check=True, stdout=subprocess.DEVNULL,
    )

    # make-unsigned-catalog reads every artifact from one directory: in
    # offline mode that is the directory build-app.sh embeds.
    assets = output / "offline-artifacts" if arguments.mode == "offline" else Path(
        tempfile.mkdtemp(prefix="j714s-assets-", dir=output.parent))
    assets.mkdir(exist_ok=True)
    try:
        place(engine, assets / engine.name, arguments.link)
        place(metadata, assets / metadata.name, arguments.link)
        # The online catalog still pins the whole file's digest; link it in
        # (or copy) only long enough to digest it.
        place(payload, assets / payload.name, arguments.link)
        inputs = {
            "payload_name": payload.name,
            "metadata_name": metadata.name,
            "evidence_revision": arguments.evidence_revision,
            "asahi_installer_tag": lock["upstream_installer"]["tag"],
            "asahi_installer_revision": lock["upstream_installer"]["commit"],
            "asahi_installer_data_revision": lock["upstream_metadata"]["commit"],
            "downstream_revision": downstream,
            "device_identifiers": [BOARD],
            "installer": {
                "minimum_version": minimum,
                "latest_version": arguments.app_version,
                "download_url": f"{download_base}/",
            },
        }
        with tempfile.TemporaryDirectory(prefix="j714s-inputs-") as temporary:
            inputs_file = Path(temporary) / "inputs.json"
            inputs_file.write_text(json.dumps(inputs, indent=2))
            command = [sys.executable, str(tree / "scripts/make-unsigned-catalog.py"), "--developer-only",
                       "--base-url", download_base, "--assets-dir", str(assets),
                       "--inputs", str(inputs_file), "--output", str(output / "catalog.json")]
            if arguments.now:
                command += ["--now", arguments.now]
            subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
    finally:
        if arguments.mode == "online":
            shutil.rmtree(assets)

    catalog_path = output / "catalog.json"
    catalog = json.loads(catalog_path.read_text())
    if [model["deviceIdentifier"] for model in catalog["models"]] != [BOARD]:
        fail("the catalog must list exactly " + BOARD)
    if arguments.mode == "online":
        model = catalog["models"][0]
        model["metadataArtifact"]["sourceURL"] = f"{image_base}/{metadata.name}"
        # The whole file is not hosted; with parts its URL is informational.
        model["payloadArtifact"]["sourceURL"] = f"{image_base}/{payload.name}"
        model["payloadArtifact"]["parts"] = [
            {"sourceURL": f"{image_base}/{part['fileName']}", **part} for part in parts
        ]
        catalog_path.write_text(json.dumps(catalog, indent=2) + "\n")
    if catalog_path.stat().st_size > 1048576:
        fail("catalog.json exceeds 1 MiB")

    signature = output / "catalog.json.sig"
    signer.sign(catalog_path, signature)
    signer.verify(trust_root, catalog_path, signature)
    descriptor = json.loads((output / "release.json").read_text())
    fingerprint = "sha256:" + hashlib.sha256(signer.public).hexdigest()
    if descriptor["trust_root_fingerprint"] != fingerprint:
        fail("release.json does not pin this trust root")
    print(json.dumps({
        "mode": arguments.mode,
        "output": str(output),
        "trust_root_fingerprint": fingerprint,
        "catalog_sha256": "sha256:" + sha256(catalog_path),
        "sequence": catalog["sequence"],
        "payload": payload.name,
        "payload_parts": len(parts),
        "helper_code_signing_requirement": descriptor["helper_code_signing_requirement"],
    }, indent=2))


if __name__ == "__main__":
    main()
