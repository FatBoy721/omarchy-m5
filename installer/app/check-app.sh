#!/bin/bash
# Check a J714s developer app built by Packaging/build-app.sh (macOS only).
#
# usage: check-app.sh APP offline|online RELEASE_INPUTS
#
# The app must be an ad hoc signed developer build whose sealed catalog and
# trust root are exactly the release inputs', listing only apple,j714s; an
# offline app must also carry every catalog artifact, byte for byte. Nothing
# here installs, registers or runs anything.
set -euo pipefail

fail() { echo "check-app: $*" >&2; exit 1; }
(( $# == 3 )) || fail "usage: check-app.sh APP offline|online RELEASE_INPUTS"
app=$1 mode=$2 inputs=$3
[[ $mode == offline || $mode == online ]] || fail "mode must be offline or online"
info=$app/Contents/Info.plist
release=$app/Contents/Resources/Release

[[ $(/usr/bin/plutil -extract OmarchyDeveloperBuild raw -o - "$info") == true ]] || fail "not a developer build"
if [[ $mode == offline ]]; then
  [[ $(/usr/bin/plutil -extract OmarchyOfflineBundle raw -o - "$info") == true ]] || fail "not an offline build"
else
  ! /usr/bin/plutil -extract OmarchyOfflineBundle raw -o - "$info" >/dev/null 2>&1 || fail "online build is marked offline"
fi
for key in OmarchyPrivatePlainTest OmarchyPrivateLimineTest SMPrivilegedExecutables; do
  ! /usr/bin/plutil -extract "$key" raw -o - "$info" >/dev/null 2>&1 || fail "unexpected $key in Info.plist"
done
for name in release.json trust-root.ed25519.pub catalog.json catalog.json.sig; do
  cmp -s "$inputs/$name" "$release/$name" || fail "$name differs from the release inputs"
done

/usr/bin/codesign --verify --deep --strict "$app"
# Ad hoc: no team, no certificate chain.
details=$(/usr/bin/codesign --display --verbose=4 "$app" 2>&1)
grep -q '^Signature=adhoc' <<<"$details" || fail "app is not ad hoc signed"
helper=$app/Contents/Library/LaunchServices/org.omarchy.installer.helper
decoder=$app/Contents/Helpers/omarchy-restore-image
/usr/bin/codesign --verify --strict -R='identifier "org.omarchy.installer.helper"' "$helper"
/usr/bin/codesign --verify --strict -R='identifier "org.omarchy.installer.restore-image"' "$decoder"
[[ $(/usr/bin/lipo -archs "$app/Contents/MacOS/OmarchyAppleInstallerApp") == arm64* ]] || fail "app is not arm64"

python3 - "$release/catalog.json" "$app/Contents/Resources" "$mode" <<'PY'
import hashlib, json, pathlib, sys
catalog, resources, mode = json.load(open(sys.argv[1])), pathlib.Path(sys.argv[2]), sys.argv[3]
models = catalog["models"]
if [m["deviceIdentifier"] for m in models] != ["apple,j714s"] or models[0]["status"] != "enabled":
    raise SystemExit("check-app: the sealed catalog must enable exactly apple,j714s")
model = models[0]
def check(path, digest, size):
    if not path.is_file() or path.stat().st_size != size:
        raise SystemExit(f"check-app: {path.name} is missing or the wrong size")
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(8 << 20), b""):
            h.update(block)
    if "sha256:" + h.hexdigest() != digest:
        raise SystemExit(f"check-app: {path.name} differs from the catalog")
engine = model["engineArtifact"]
check(resources / "Engine/artifacts" / engine["fileName"], model["engineDigest"], engine["sizeBytes"])
if mode == "offline":
    for role in ("engine", "metadata", "payload"):
        artifact = model[role + "Artifact"]
        check(resources / "Artifacts" / artifact["fileName"], model[role + "Digest"], artifact["sizeBytes"])
else:
    if (resources / "Artifacts").exists():
        raise SystemExit("check-app: an online build carries embedded artifacts")
    if len(model["payloadArtifact"].get("parts", [])) < 2:
        raise SystemExit("check-app: the online catalog has no payload parts")
print("check-app:", mode, "catalog sequence", catalog["sequence"], "payload", model["payloadArtifact"]["fileName"])
PY
echo "check-app: $mode app passed"
