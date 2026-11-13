# speakerguardd v2 for the J714s image

**Status (2026-11-13): both packages built on ush (speakerguardd-v2 in an Arch Linux ARM container
under qemu, `check()` passed; aurora-speaker-upgrade `any`, 37 upgrade tests passed) and in the
omarchy-j714s 2 package set (`installer/patches-j714s-r2`). Nothing installed on a Mac yet, no
tuning collected, speakers not played.**

Two recipes, both pinned to aurora-silicon/speakerguardd `v2` at
[`04169c44`](https://github.com/aurora-silicon/speakerguardd/commit/04169c4470650f8e2554db70d4072fb92e484138),
the pin aurora-silicon/alarm-aurora 282881f moved to:

| Recipe | From | Changes |
| --- | --- | --- |
| `speakerguardd-v2` 1.0.0alpha.1-41.1 (aarch64) | aurora-silicon/alarm-aurora `packages/speakerguardd-v2` at 282881f37c86 (pkgrel 41) | `pipewire-speaker-graph>=2` and `aurora-audio` dropped from depends (PKGBUILD says why; the image has aurora-audio 4.1.aurora3 anyway) |
| `aurora-speaker-upgrade` 0.1-16 (any) | the same repo's `packages/aurora-speaker-upgrade` (0.15) | same pin; not in Aurora's package group |

Since bd2b2099 (the previous pin): #169/#175 bind the LSID sense source over the engine page
(appended header words; `sgv2-telemetry.py` reads the earlier fields unchanged) and #173
re-attests parity.json at voicing law a8c2a491. The units and session scripts are unchanged.

## How the image runs it

omarchy-aurora-firmware j714s8 enables `aurora-speaker-upgrade.service` with upstream's
documented boot opt-in (`run --at-boot --i-understand-preview`, packaging/upgrade/README.md) and
gives apfs_ro a liblzfse. At boot it collects this Mac's tuning from the macOS System volume
(read only), compiles it, runs the silent self-check and `speakerguardd-selfcheck verify`, and
switches the kernel to v2 only if they pass; v2's own gate then decides every boot. gate.json
and parity.json are upstream's. A refusal is recorded and not retried until the kernel,
speakerguardd or the parity attestation changes, and the speakers stay at the kernel's floor.

## Why there are no J714 files to gather

v2 has no per-board files any more. The channel map, V/I order, card, amp count,
PipeWire/WirePlumber graph and voicing are all derived at runtime from the live
device tree, this Mac's own tuning and the silent self-check
(`docs/NEW-PLATFORM.md` in the source). DjDeveloperr's only J714s change to v2
is [#158](https://github.com/aurora-silicon/speakerguardd/pull/158), which adds
the `apple,t6050-aop-audio` transport to `wiring.py`. It is in this pin.
`packaging/pipewire/sgv2-*.conf` has no J714 file, and that is by design.

What the J714s needs from the rest of the stack:
- **The kernel:** linux-aurora-upstream has the dual interface (read in the up273-10 tree; the dev Linux boots up273-8, so check the live card)
  ("Speaker Protection Interface": "Speaker Volume Unlock" or "Speaker
  Protection") and the J714 macaudio entry with `safe_vol = -20` (#1554).
- **Aura:** it passes each amp's `apple,speaker-config` / `apple,amp-tx-zd-config`
  and `/chosen/asahi,speaker-id` (`src/kboot_audio.c`).
- **The tuning:** collected per Mac by `aurora-speaker-upgrade`. Route 1 is the
  macOS System volume, read only by its own `apfs_ro`. Route 2 is the IPSW, by
  HTTP ranges. The ADT comes from the `adt` MTD partition, or `--adt FILE`.
  Nothing from Apple goes in the package or the repo.

None of this is specific to 27.3 except the kernel and Aura already in the
image. The speaker DT and macaudio entry come from upstream #1554, which was
validated on DjDeveloperr's J714s.

## The speakersafetyd hold stays (one protected path)

`linux-aurora-upstream/speakersafetyd-hold.conf` keeps speakersafetyd off the
J714 speakers. It does not touch v2's units.

Upstream's legacy gate (`60-speakerguardd-v2-gate.conf`, installed by this
package) lets speakersafetyd run on a dual kernel whenever this Mac is *not*
switched to v2. On the J714s that would be our old-kernel `j714.conf` on the
new wiring, which is the unprotected path. So:
- With v2 switched and qualified: the gate stops speakersafetyd and v2 owns the speakers.
- Otherwise: the hold stops speakersafetyd and the kernel floor holds.

Removing the hold "only when v2 runs" would change nothing in the first case
and would reopen the unprotected path in the second. On the Mac,
`speakerguardd-gate explain` should show exactly one stack, or none.

## Collisions, resolved in omarchy-aurora-firmware j714s8

- **The old `j714-speakers.conf` filter** (software-dsp on `hw:AppleJ714,1`, asahi-audio's J314
  FIRs, made for the old kernel) and **speakersafetyd's `j714.conf` profile** are removed. The
  only route to the speakers that can make sound is v2's voicing sink.
- **The UCM:** alsa-ucm-conf-aurora 10.aurora3 (the image's, = edge) predates the v2 condition.
  The J714 profile now includes `conf.d/macaudio/omarchy-j714/HiFi.conf`, upstream
  alsa-ucm-conf-asahi 96b3206's `laptops/HiFi.conf` unchanged, which offers no Speaker device
  while `/run/speakerguardd-graph/speakerguardd-owns-speakers` exists. (alarm-aurora's
  alsa-ucm-conf-aurora 10.aurora2-5 sorts below edge's, so the package itself stays.)
- **speakersafetyd:** held twice (kernel hold, v2 legacy gate), see above.
- Still to confirm on the Mac: `cat /proc/asound/AppleJ714/id` and the longname match
  `MacBook Pro J714`; `pw-dump` shows no node other than sgv2's protect output on
  `hw:AppleJ714,1`; `speakerguardd-gate explain` names one stack or none.

## Will verify pass on 27.2? (the likely stop)

parity.json at 04169c44 attests 25C56, 25G72, 25G83 (26.6.2) and 26A428 (27.0) only. A tuning is
checked against its own build's block, or against 25G83's when its speaker files for its AID are
byte-identical to 25G83's (`crates/aurora-speaker-tuning/src/reference.rs`). There is no block for
27.2 (26B123) or the 27.3 beta, so on either v2 qualifies only if this Mac's AID is in 25G83 and
its files equal 25G83's. Otherwise verify refuses and the speakers stay at the floor. That is the
expected safe outcome: `gate.json` and `parity.json` must not be edited.

## Test protocol (dev Linux p5, not the image)

1. **Read only.** Check `uname -r`, that `findmnt /` is p5, and the card
   controls: `amixer -c AppleJ714 cget name='Speaker Protection Interface'`.
   Read the amps' `apple,speaker-config` in `/proc/device-tree`, and check
   `/chosen/asahi,speaker-id` and `/proc/mtd` (`adt`).
2. **Build and install** both packages on the Mac in `~/m5-work/sgv2`.
   p5 also boots the catcher's fallback kernel (`7.3.0-j714s-sleep`), where speakersafetyd
   legitimately runs. After installing, check that `speakerguardd-gate explain` says
   legacy there and that its audio is unchanged.
3. **Dry run:** `aurora-speaker-upgrade --check --json /root/sgv2-check.json`
   with `--device /dev/nvme0n1p2`. It collects, compiles and runs
   the self-check in /run, and stores and switches nothing. Pass `--device` explicitly
   (after the move to 27.2 there may be two macOS builds on disk). Record which System
   volume and build were read, because provisioning binds the blob to that build. If its `apfs_ro`
   cannot read the volume, mount it read only with
   `/root/build/apfs-fuse/build/apfs-fuse` (volume 0 of p2) and unmount
   afterwards. A refusal by verify or the gate (for example, no parity
   attestation for the installed macOS build) is a stop. Do not edit
   `gate.json` or `parity.json`.
4. **Switch:** `aurora-speaker-upgrade run`, then `speakerguardd-gate explain`
   and `systemctl status speakerguardd-v2`. Log in as the seat user so the
   switch test and the graph run.
5. **Before any sample:**
   - v2 owns "Speaker Protection" and is ready;
   - the voicing sink is set to 5 % (`wpctl set-volume`; the first start defaults to 30 %);
   - nothing else is playing;
   - the amps show no fault latch.
6. **Play:** a 2 s pink-noise burst or a 1 kHz tone at 5 %, then 10 %, while
   capturing:
   - `sgv2-telemetry.py /run/speakerguardd/<uid>/<engine page>`: coil and
     magnet temperatures, modelled and measured power, the V/I mean squares
     (`sense_v_ms`/`sense_i_ms` non-zero means current flowed), the gain;
   - the kernel log (grants and releases, no fault);
   - `amixer -c AppleJ714 contents` (the amp gain and the speaker volumes).

   Stop and mute on any fault, a NaN, a temperature rising without bound, or
   a grant without the sense moving.
