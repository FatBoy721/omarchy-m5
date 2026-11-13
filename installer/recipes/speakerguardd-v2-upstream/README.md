# speakerguardd v2 for the J714s upstream image

**Status (2026-11-12): recipes only. Not built, not installed, speakers not played.**
The dev Mac was unreachable over ssh for the whole session (it answered ping but
not port 22, probably while the installed image was being tested). Nothing
below has run on a J714s yet, so the image does not include these packages.

Two recipes, both pinned to aurora-silicon/speakerguardd `v2` at
[`bd2b2099`](https://github.com/aurora-silicon/speakerguardd/commit/bd2b2099eb7333857ad05adc1c7b8c15b8428f58):

| Recipe | From | Changes |
| --- | --- | --- |
| `speakerguardd-v2` 1.0.0alpha.1-40.1 (aarch64) | aurora-silicon/alarm-aurora `packages/speakerguardd-v2` at 9420980b8fc0 (pkgrel 40, pin 26b88eac) | the pin moves to the v2 head (adds #168: V/I sense enabled and verified before a grant, Secondary speaker route selected before provisioning); `pipewire-speaker-graph>=2` and `aurora-audio` dropped from depends (PKGBUILD says why) |
| `aurora-speaker-upgrade` 0.1-15 (any) | the same repo's `packages/aurora-speaker-upgrade` (0.14) | same pin; not in Aurora's package group |

At bd2b2099, on ush (x86_64): `cargo test` for the four shipped crates and the
`test_provision`, `test_wiring`, `test_verify` and upgrade tests pass. The
upgrade tests that need `python-cryptography` (a makedepend here) were not run
there. This PKGBUILD's `prepare()` unit checks pass on the bd2b2099 tree.

## Why there are no J714 files to gather

v2 has no per-board files any more. The channel map, V/I order, card, amp count,
PipeWire/WirePlumber graph and voicing are all derived at runtime from the live
device tree, this Mac's own tuning and the silent self-check
(`docs/NEW-PLATFORM.md` in the source). DjDeveloperr's only J714s change to v2
is [#158](https://github.com/aurora-silicon/speakerguardd/pull/158), which adds
the `apple,t6050-aop-audio` transport to `wiring.py`. It is in this pin.
`packaging/pipewire/sgv2-*.conf` has no J714 file, and that is by design.

What the J714s needs from the rest of the stack:
- **The kernel:** linux-aurora-upstream has the dual interface
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

## The speakersafetyd hold stays

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

## Collisions to check on the Mac before the first grant

- **omarchy-aurora-firmware's `j714-speakers.conf`:** a software-dsp filter on
  `hw:AppleJ714,1`, made for the old kernel. v2's raw rules
  (`59-sgv2-raw.conf`) disable that node, so the filter has no parent. Confirm
  with `pw-dump` that no node other than sgv2's protect output opens
  `hw:AppleJ714,1`.
- **The UCM:** `MacBook Pro J714.conf` includes the installed
  `laptops/HiFi.conf`. Only alsa-ucm-conf-asahi at or after aurora-silicon
  099f2b9c (#13) drops the Speaker device while
  `/run/speakerguardd-graph/speakerguardd-owns-speakers` exists. Check the
  installed copy with `grep speakerguardd-owns-speakers`.
- **The card name:** confirm that `cat /proc/asound/AppleJ714/id` and the
  longname match what the rules use (`MacBook Pro J714`).

## Test protocol (dev Linux p5, not the image)

1. **Read only.** Check `uname -r`, that `findmnt /` is p5, and the card
   controls: `amixer -c AppleJ714 cget name='Speaker Protection Interface'`.
   Read the amps' `apple,speaker-config` in `/proc/device-tree`, and check
   `/chosen/asahi,speaker-id` and `/proc/mtd` (`adt`).
2. **Build and install** both packages on the Mac in `~/m5-work/sgv2`.
3. **Dry run:** `aurora-speaker-upgrade --check --json /root/sgv2-check.json`
   (add `--device /dev/nvme0n1p2` if needed). It collects, compiles and runs
   the self-check in /run, and stores and switches nothing. If its `apfs_ro`
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
