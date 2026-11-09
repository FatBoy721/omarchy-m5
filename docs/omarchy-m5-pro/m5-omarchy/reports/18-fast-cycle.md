# 18 — Fast test cycle: re-arm the stub with a new boot object, without boot loops

**Deliverable:** `tools/step2-fast.sh` (MIT, derived from betizzel/omarchy-m5 `scripts/finish-install.sh` @15cd70c1, the embedded step2.sh; the SPDX header is kept). It runs in the stub's paired 1TR. Nothing here has run yet (NATIVE untested). Every step marked [HYPOTHESIS] needs confirming on the first cycle.

## What step2-fast.sh does (vs step2.sh)
| Step | step2.sh | step2-fast.sh |
|---|---|---|
| Paired + 1TR checks | yes; if not paired it runs `bless --setBoot` + shutdown | same checks; **no re-bless**, it just shuts down with instructions |
| `bputil -nc -v VGID` | always | **skipped** if `bputil -d -v VGID` output contains "Permissive" (case-insensitive) [HYPOTHESIS: the exact wording on 26.6.2; if the grep misses, it just runs bputil again, which is harmless] |
| `kmutil configure-boot -c boot.bin --raw --entry-point 2048 --lowest-virtual-address 0 -v <stub>` | yes | identical, with the same retry loop |
| Install-media marker | `.IAPhysicalMedia` → `IAPhysicalMedia-disabled.plist`; `SystemVersion-disabled.plist` → `SystemVersion.plist` | identical (existence-guarded) |
| Next boot | none (the stub is already the default) | `bless --mount <stub> --setBoot --nextonly`. On failure it shuts down; the owner then uses Startup Options → Continue |

`bless(8)` (man page, keith.github.io/xcode-man-pages/bless.8.html): `--nextonly` "Only change the boot device selection for the next boot"; `--setBoot` "Set the system to boot off the specified volume"; `--mount` is used "in conjunction with --setBoot"; "Admin credentials may be prompted when running bless on an Apple silicon platform". [HYPOTHESIS] that `--nextonly` is honoured from 1TR on Apple silicon: not documented either way. The fallback is the Apple Startup Options one-shot (hold power → Omarchy → Continue), which is a one-time choice per Apple (report 15).

## macOS-side commands (PM, `ssh -tt macbook`, run with expect for the sudo password)
Set once per session:
```sh
STUB=/Volumes/Omarchy                         # the stub System volume mount point; check with: diskutil info Omarchy | grep 'Mount Point'
APP="$STUB/Finish Installation.app/Contents"
VG=$(diskutil apfs list | awk '/Name:.*Omarchy/{f=1} f&&/Volume Group/{print $NF; exit}'); echo "VG=$VG"
PB=<stub Preboot device, e.g. disk3s3 per report 16>
```
**(a) Drop in the new boot.bin + step2-fast.sh** (first copy both to `/tmp` on the Mac with scp from ush):
```sh
sudo mount -u -w "$STUB"
sudo cp /tmp/boot.bin "$APP/Resources/boot.bin"
sed -e "s|##DISTRO##|Omarchy|" -e "s|##VGID##|$VG|" -e "s|##PREBOOT##|$PB|" /tmp/step2-fast.sh \
  | sudo tee "$APP/Resources/step2-fast.sh" >/dev/null
sudo chmod 755 "$APP/Resources/step2-fast.sh"
printf '#!/bin/sh\nexec /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal "${0%%/*}/../Resources/step2-fast.sh"\n' \
  | sudo tee "$APP/MacOS/step2_launcher.sh" >/dev/null       # same launcher as betizzel's, pointed at step2-fast.sh
sudo chmod 755 "$APP/MacOS/step2_launcher.sh"
shasum -a 256 "$APP/Resources/boot.bin"; grep -E '^(VGID|PREBOOT)=' "$APP/Resources/step2-fast.sh"
```
[HYPOTHESIS] the Terminal path in 1TR. Copy whatever path the existing `step2_launcher.sh` uses (`sudo cat "$APP/MacOS/step2_launcher.sh"` first) and keep it.

**(b) Re-arm `.IAPhysicalMedia`, no bless** (this reverses step 4 so 1TR offers "Finish Installation" again):
```sh
CS="$STUB/System/Library/CoreServices"
[ -e "$CS/SystemVersion.plist" ] && sudo mv "$CS/SystemVersion.plist" "$CS/SystemVersion-disabled.plist"
if [ -e "$STUB/IAPhysicalMedia-disabled.plist" ]; then
  sudo mv "$STUB/IAPhysicalMedia-disabled.plist" "$STUB/.IAPhysicalMedia"
else
  sudo tee "$STUB/.IAPhysicalMedia" >/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>AppName</key><string>Finish Installation.app</string>
<key>ProductBuildVersion</key><string>00A191</string>
<key>ProductVersion</key><string>12.1</string>
</dict></plist>
EOF
fi
ls -la "$STUB/.IAPhysicalMedia" "$CS"/SystemVersion*.plist
bless --getBoot                                 # must still show Macintosh HD's volume; do NOT run bless --setBoot on the stub
```
If `--getBoot` doesn't show Macintosh HD: System Settings → General → Startup Disk → Macintosh HD (owner), or `sudo bless --mount / --setBoot` (a boot-setting change, so it needs PM/owner approval under rule 1).

## Per-cycle owner steps (expected prompts)
1. Shut down. **Press and hold** power until "Loading startup options".
2. Select **Omarchy** → **Continue**. This enters the stub's paired 1TR; the "Finish Installation" app opens because of `.IAPhysicalMedia`. [HYPOTHESIS] there may be a user-select/FileVault unlock step: enter the **macOS admin/FileVault password** if asked.
3. Terminal shows `Omarchy fast re-arm (step2-fast)` with the VGID and the boot.bin size. Check the size matches.
4. If the policy isn't Permissive yet: **Enter**, then credentials twice (bputil). Normally skipped.
5. **kmutil**: one admin username/password prompt.
6. bless `--nextonly` may ask for admin credentials (man page). Then **Enter** to reboot.
7. The boot object runs once. If it fails or powers off, the next normal power-on boots **macOS** (the default didn't change). One panic per test, so PanicMedic's 5-strike limit isn't reached.

If step 6 fails, the script shuts down. Hold power → Omarchy → Continue boots the new object once.

## Open points
- The Permissive grep string, `--nextonly` from 1TR, and the 1TR Terminal path: confirm on cycle 1 and record the outcome here (NATIVE).
- Re-arm (b) is needed before **every** cycle, because step2-fast disables the marker each time.

## CORRECTION 2026-11-04: why every fast cycle failed pairing, and the fix
**Observed (NATIVE, owner photo):** every cycle printed "This is not the recoveryOS paired with Omarchy … Press enter to shut down". kmutil never ran, so nothing was installed. That cycle 1 would confirm the 1TR behaviour (Open points above) turned out to be the key unknown, and the answer is no.

**Why:**
- 1TR (hold power) boots the recoveryOS paired with the **current default startup volume**. betizzel's `finish-install.sh` and Asahi's step2 both rely on this: the macOS side runs `bless --setBoot` on the stub first, and step2's own not-paired branch does `bless --setBoot --mount "$system_dir"` + shutdown so the next hold reaches the stub's 1TR.
- My design kept **Macintosh HD as the default** (to avoid a PanicMedic loop), and my not-paired branch **removed step2's re-bless**. Picking Omarchy in Startup Options therefore ran Finish Installation inside **macOS's** 1TR: `bputil` didn't report ": Paired", and the script shut down every time.
- [HYPOTHESIS, consistent with the evidence] Startup Options → Omarchy → Continue doesn't switch which recoveryOS is "one true" for the stub; only the default does.

**Fix (tools/step2-fast.sh, this commit):**
1. Not paired → `bless --setBoot --mount <stub>` (exactly as step2), shut down; the owner holds power again → Omarchy → now in the stub's paired 1TR.
2. Paired → bputil skip/run → kmutil → marker disable, as before.
3. Then restore the default to macOS (`bless --mount "/Volumes/Macintosh HD" --setBoot`; override the path with `M5_MACOS_VOL`), and only if that worked, `bless --mount <stub> --setBoot --nextonly`. [HYPOTHESIS] both are untested from 1TR, and the macOS volume may not be mounted (FileVault). On failure the script says so and the **stub stays the default**: a failing object can then loop ≤5× into Recovery (seen before, recoverable). Then set Startup Disk → Macintosh HD from macOS.

**Per-cycle owner steps (revised):** power-hold → Omarchy → Continue → (first time per cycle) the script blesses the stub and asks for credentials → Enter → shut down → **power-hold again** → Omarchy → Continue → kmutil password → the restore/nextonly messages → Enter → reboot. Expect 2 holds per cycle. Equivalent documented route: arm with `finish-install.sh`, which blesses the stub on the macOS side, so the first hold is already paired. Either way, **read the printed default-restore line** before trusting a result.

**Verify a real install before calling a result NATIVE:** the PM checks over SSH that the stub's `kernelcache.custom.*` changed (mtime/size/hash, report 16 commands) after each cycle.
