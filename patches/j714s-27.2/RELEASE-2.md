# omarchy-j714s 2: what is left

Release 2 of the one J714s image (27.2 non-beta stub, Mach-O Stage 1). Prepared offline on
2026-11-13 while release 1 was being installed. Not published.

## Ready now

- **Kernel** `linux-aurora 7.3.0.aurora17.v272-2`: integration/aurora `a34d26c255c2` + 15 patches
  (`linux/`). Cross-built on ush. ANE on 27.2 stays refused until step 2 below.
- **Aura** `m1n1-aurora 1.6.1.aurora24.v272-2`: main `22b71758` + 6 patches (`aura/`). Built on
  ush; Stage 1 fill byte-identical to the engine's, padded object kcrz 153141248.
- **Speakers** `speakerguardd-v2 1.0.0alpha.1-41.1`, `aurora-speaker-upgrade 0.1-16` (v2
  `04169c44`), new support roles. They switch the speakers to v2 at boot on their own once v2's
  own checks pass (see "Speakers" below).
- **omarchy-aurora-firmware 20261014.j714s8**: one speaker path (the old kernel's speakersafetyd
  profile and software-dsp speaker graph removed), the J714 UCM's laptop verb with upstream's
  speakerguardd v2 condition, VRR range on, the speaker auto-switch, and the first-boot camera
  setfile collection.
- **Installer patch set** `installer/patches-j714s-r2/` 0001 (on top of `patches`,
  `upstream-27.3`, `j714s` 0001-0009): the two speaker roles (20 roles), the five rebuilt
  packages in the manifest (set `j714s-dev-runtime-ac7e940e5bf9`), the kernel qualification pin
  v272-2. Tests: `test_candidate_set` (20 roles), `test_stage1_qualification`, inspection,
  mac-image-check, image-profile, verify-installed-system and `prepare.sh` pass; in `test/all`
  only `test_the_template_is_the_one_build_mac_image_reads` fails, as it already does on
  release 1.

Package sha256s are in `README.md` ("Packages, release 2").

## The release-1 boot failure, and what release 2 carries for it

`docs/install-failure-2026-11-13.md`: the new stub was Not Paired, Security Mode Full, with no
custom kernel collection and no Recovery log, so "Finish setup" never ran; the power-off was an
unenrolled stub, not `--compress` or Aura. Already in `patches-j714s` (other session, on main):
- **0008** (f93d03b): the J714s Stage 1 proxy window is 15000 ms (a failing boot shows on the PC
  cable), and a `compress` switch in the Mach-O Recovery manifest that stays **true** (upstream's
  `--compress`). Engine `v0.9.2-omarchy.20261113.9360b4de398f`, 17912715 bytes, sha256
  `5caff1af…a333a2` (two identical repacks).
- **0009** (c3d1e0c): the app's last screen and the stub Recovery's first screen say: pick the
  highlighted Omarchy, sign in, click Install in Omarchy's Finish setup, don't use Startup
  Security Utility.

`patches-j714s-r2` is based on that tree (`ea290c11`); its TREE is `72be086a`. If more
installer patches land in `patches-j714s`, rebase it:
```sh
installer/app/rebuild-installer-tree.sh /tmp/t upstream-27.3 j714s
git -C /tmp/t am --3way installer/patches-j714s-r2/*.patch
git -C /tmp/t format-patch --zero-commit -o installer/patches-j714s-r2 HEAD~1   # replace the old 0001
git -C /tmp/t rev-parse 'HEAD^{tree}' > installer/patches-j714s-r2/TREE
```

0008 and 0009 change the Recovery app, which has only partly compiled (on Linux). Before an image:
1. Run the macOS CI checks (`checks.yml` macOS job or `installer-app.yml`, unpublished): Xcode's
   swift-format, the UXCore and Recovery tests, `Recovery/build-app.sh` fixtures, and look at the
   Recovery first screen (the new introduction must fit the 780x440 window above the password).
2. Put that run's Recovery app into `build-input-provenance.json`'s recovery block (run, artifact,
   zip sha256, inventory sha256, tree, commit; first set in patches-j714s 0007) as a patch in
   `patches-j714s-r2`.
3. `installer-app.yml` defaults to release 1's engine (`b25a51d6df57`); pass the 0008 engine.

## After the first 27.2 boot

Collect what `README.md` "What the first 27.2 boot must collect" lists, then:

1. **Check the boot log** for the eight items there. A failure in 1 (EL2, 15 CPUs) or 7 (NVMe,
   Wi-Fi) stops the release.

2. **ANE pin (always needed).** The driver logs `H17 ANE: preloaded TEXT sha256 <64 hex>`. On ush:
   ```sh
   cd ~/m5-build/up272-2/src            # branch up-2722 = patches/j714s-27.2/linux
   PIN=<64 hex from the log>
   python3 - "$PIN" <<'EOF'
   import sys, re
   pin = bytes.fromhex(sys.argv[1]); assert len(pin) == 32
   p = 'drivers/accel/ane/ane_fw_platform.c'; s = open(p).read()
   rows = ',\n\t'.join(', '.join(f'0x{b:02x}' for b in pin[i:i + 8]) for i in range(0, 32, 8))
   old = 'static const u8 ane_t6050_text_pin_27_2[32];'
   assert s.count(old) == 1
   open(p, 'w').write(s.replace(old, 'static const u8 ane_t6050_text_pin_27_2[32] = {\n\t' + rows + ',\n};'))
   EOF
   git commit -am "accel/ane: T6050: pin the macOS 27.2 (26B123) ANE TEXT" \
     -m "Read from the first J714s 27.2 boot: H17 ANE: preloaded TEXT sha256 $PIN." \
     -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
   rm -rf ../patches && git format-patch -q -o ../patches a34d26c255c2..up-2722
   cat ../patches/*.patch > ~/m5-build/pkg272-2/linux-aurora-j714s/linux-j714s-27.2.patch
   ```
   Also update the comment above the pin (it still says "refused until"). Copy `../patches/*` to
   `patches/j714s-27.2/linux/` and the concatenation to `installer/recipes/linux-aurora-j714s/`,
   set `pkgrel=3` and the patch's sha256 in its PKGBUILD, and rebuild on ush:
   `cd ~/m5-build/pkg272-2/linux-aurora-j714s && ./run.sh` (about 45 min; `MAKEPKG-RC=0` at
   the end of `build.log`).

3. **DCP UUID (only if Aura refused it).** If Aura logged `DCP image <uuid> is not C51FB0C8-...`,
   put `<uuid>` in `T6050_DCP_UUID_272` (Aura 0005, `src/kboot_display_handoff.c`) on ush in
   `~/m5-build/aura272-2/aura` (branch `up-2722`), commit, `git format-patch -o ../out
   origin/main..up-2722`, copy to `patches/j714s-27.2/aura/`, regenerate
   `installer/recipes/m1n1-aurora-j714s/aura-j714s-27.2.patch`, `pkgrel=3` and its sha256, and
   rebuild in `~/m5-build/pkg272-2/m1n1-aurora-j714s` with
   `makepkg --config ../makepkg-aarch64.conf -d -f` (check() must print `kcrz 153141248`).
   Matching UUID: m1n1-aurora v272-2 is final.

4. **Optional, from the same boot:** if H.264 and HEVC encode cleanly with
   `apple_ave.ave_t6050_27_2_layout=1`, flip its default to true in kernel 0015 before step 2's
   rebuild. If the camera streams at all eight sizes, nothing changes; drop 0010 if 2560x1440
   fails.

5. **The installer patch** (one new patch in `patches-j714s-r2`, on the tree it makes; it can
   carry step 2 of the section above too):
   - `Integration/M5/J714s-Normal-System/candidate-package-manifest.json`: the `linux-aurora`
     row (version `7.3.0.aurora17.v272-3`, filename, sha256, size, source commit = the
     betizzel/omarchy-m5 commit with step 2's recipe), and the `m1n1-aurora` row if step 3
     rebuilt it. Recompute `set_sha256` with `candidate_set.set_digest()` and the set name
     `j714s-dev-runtime-<first 12 hex>`.
   - `image-builder/builder/stage1_qualification.py`: `J714S_KERNEL_VERSION =
     "7.3.0.aurora17.v272-3"`, `J714S_KERNEL_RELEASE = "7.3.0-17.v272-3-ARCH"`.
   - Run `image-builder/test/all` (or at least `test_candidate_set.py` and
     `test_stage1_qualification.py`) and update `patches-j714s-r2/TREE`.

6. **Inputs and CI** (the release-1 flow, `installer/README.md`):
   - Upload the 20 package set archives and run `finish-inputs.py` on the tree
     `rebuild-installer-tree.sh DEST upstream-27.3 j714s j714s-r2` makes, with the 0008 engine,
     giving a new `installer-build-inputs-j714s-<sha>` release.
   - `installer-image.yml` with `patch-set: upstream-27.3 j714s j714s-r2`, `image-profile:
     j714s`, image number 2; then the `update-check` workflow (must change 0 packages and keep
     every J714s package, now including the two speaker packages); then `installer-app.yml`.
   - Write the run IDs and the payload sha256 into `installer/README.md`.

## Speakers

speakerguardd v2 and aurora-speaker-upgrade are in the image and wired to switch on their own:
omarchy-aurora-firmware enables `aurora-speaker-upgrade.service` with upstream's documented
opt-in (`run --at-boot --i-understand-preview`). At each boot until it succeeds or refuses it
collects this Mac's tuning from the macOS System volume (read only), compiles it, runs v2's
silent self-check and `speakerguardd-selfcheck verify`, and switches only if they pass. gate.json
and parity.json are upstream's, unedited.

Expected on 27.2: **a refusal.** parity.json at 04169c44 attests 25C56, 25G72, 25G83 and 26A428
only. A tuning from macOS 27.2 or 27.3 qualifies only if this Mac's speaker files for its AID are
byte-identical to 25G83's. On a refusal nothing is switched, the refusal is not retried until the
kernel, speakerguardd or parity.json changes, and the speakers stay at the kernel's floor:
- the kernel's J714 speaker volume lock holds them at the floor while no daemon owns them;
- speakersafetyd is stopped twice: the kernel's `60-linux-aurora-j714s-hold.conf` and v2's
  legacy gate;
- the old speaker path is gone from omarchy-aurora-firmware (no `j714.conf` profile, no
  software-dsp filter on `hw:AppleJ714,1`);
- once v2 owns the speakers, the J714 UCM offers no Speaker device (the marker
  `/run/speakerguardd-graph/speakerguardd-owns-speakers`), so v2's voicing sink is the only way
  to them.

Check on the first boot: `journalctl -u aurora-speaker-upgrade`, `speakerguardd-gate explain`
(exactly one stack, or none), `aurora-speaker-upgrade status`. If it qualifies, follow the
low-level test in `installer/recipes/speakerguardd-v2-upstream/README.md` (5 % then 10 %, with
telemetry) before trusting it at volume. `lzfse` is not in Arch Linux ARM: if this Mac's tuning
files are LZFSE-compressed, route 1 refuses and `aurora-speaker-upgrade guide` (route 3, a
collection made on macOS) is the way.

## Not in release 2, and why

- **ALS calibration:** macOS keeps it only in the IORegistry (`als` CalibrationData), so it must
  be read on macOS by the installer, which collects it for the MacBook Neo only. Adding the J714s
  is another engine change and re-pin (as 0008 did); not done here. Until then
  `tools/als-calibration/save-als-cal.py` (run on macOS) is the way.
- **The camera setfile in the installer:** the engine also collects the IMX958 setfiles for the
  Neo only. The image collects them itself at first boot instead (`aurora-j714s-camera-setfile`),
  so this needs no installer change; moving it into the engine can come with the ALS change.
- **ANE on 27.2:** needs step 2.
- **AVE encode on 27.2:** probe only until step 4's encode test passes (a wrong command layout
  can wedge the encoder).
- **Touch ID enrolment:** aurora-sep and libfprint-aurora are installed, read only
  (`xart_writes=0 provision_keybag=0`); provisioning writes the Secure Enclave store macOS
  shares, so the owner turns it on.
- **Deep sleep** (DjDeveloperr's #1772-#1785): closed upstream for rework.
- **HDMI:** no J714s DT port yet (J575c's #1565 is the reference).
- **ProRes:** no public T6050 init rows.
- **linux-aurora-headers:** the j714s profile has no headers role; the cross build cannot make it.
