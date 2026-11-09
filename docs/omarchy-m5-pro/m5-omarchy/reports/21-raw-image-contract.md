# 21 — Byte-level contract of a raw fuOS image (allowed sources only)

**Sources:**
- AsahiLinux/docs @5acb80f (`platform/introduction.md`, `fw/macho-boot-protocol.md`, `fw/boot.md`).
- asahi-installer @e93743d (MIT).
- omacom/omarchy-mac-installer @3dd6799 (MIT; its `AGENTS.md` is Codex-workflow guidance and doesn't prohibit AI use; Engine under `Engine/overlay/src`).
- omacom/linux-aurora `tools/aurora-sep/M3-AIR-26.6.2.md` @5dcdeb8c.
- Our reports 16/19.

**No m1n1 code** (upstream or forks) was read. The aurora-silicon/m1n1 stage-1 sources/releases are restricted (owner note), so they're cited only by name where the documents above link them.

## Headline (REPORTED, code-visible): stock m1n1 stage 1 also panics iBoot on macOS 26.6.2
`omarchy-mac-installer/Engine/overlay/src/omarchy_asahi.py:443-445`:
> "The m3next Stage 1 boots only a J613 with 26.6.2 OS firmware and stays in proxy mode on anything else, so older firmware keeps asahi's. **asahi's Stage 1 makes iBoot panic on 26.6.2 before m1n1 runs.**"

This is the **same symptom as ours** (iBoot panic after the `fuos` load, report 15), on a different SoC (T8122, J613). The OS firmware is 26.6.2 = mBoot-18000.161.10 (tests pair them: `test_omarchy_firmware.py:99`). So the failure isn't specific to our image or to T6050. On 26.6.2 iBoot rejects a stock raw image, and Aurora's patched `m3next` stage 1 gets past it. **What m3next changed isn't in any allowed source**: it lives in aurora-silicon/m1n1 (restricted). [HYPOTHESIS] The change affects either the image's layout/header or its early code. Only the first is something iBoot can check before the jump, which fits "before m1n1 runs".

That raises the earlier firmware explanation (H4) again: a 26.6.x stage-2 mBoot change that a stock raw image doesn't satisfy. That explanation had been "refuted" by probe2, which is now retracted.

## (1) Documented layout requirements for `kmutil configure-boot --raw`
- Asahi `platform/introduction.md:185`: "Custom kernel images can be flat ARM64 executable images; the entrypoint and (virtual; mostly meaningless) load address are specified when the image is configured. Previously Mach-O binaries were required, but it seems Apple added this feature in 12.1…". **No header, magic, alignment or padding requirement is documented.**
- Entry semantics, Asahi `fw/macho-boot-protocol.md` §Entry (written for Mach-O, the only description available): "iBoot enters us at the entrypoint … Entry is with the MMU off. `x0` points to the boot_args structure". Also: "iBoot sets and locks the RVBAR of the boot CPU to be the top of the page that the entrypoint lives in."
  - [HYPOTHESIS] With `--entry-point 2048 --lowest-virtual-address 0` the entry page is page 0 of the image (16 KiB pages), so RVBAR locks to image base + 0.
- Every installer uses exactly `--raw --entry-point 2048 --lowest-virtual-address 0`:
  - asahi-installer `src/step2/step2.sh:125`;
  - omarchy engine `omarchy_asahi.py:349`, `:371`;
  - the J613 26.6.2 guide `M3-AIR-26.6.2.md:30-31`.
- What kmutil stores is our file byte-for-byte inside IMG4/IM4P `fuos`. No entry/VA metadata is in the payload (NATIVE, report 16).

## (2) What installers do to m1n1.bin before kmutil
- **asahi-installer** `src/m1n1.py` `build()`: `fd.write(m1n1_data + vars)`, where vars = `"\n".join(lines) + "\n"` + `b"\0\0\0\0"`. Typical lines are `chosen.asahi,efi-system-partition=<uuid>` and `chainload=<uuid>;<next>` (`osinstall.py:187-196`). **Only appended text: no padding, no header, no alignment.** `extract_vars()` locates them after a `STACKBOT` marker, so the image is expected to end at its own `STACKBOT` tail (an m1n1 convention, not an iBoot one).
- **omarchy engine** (Aurora stage 1): `fill_aurora_stage1()` (`omarchy_asahi.py:425-485`, "port of aurora-silicon/m1n1 tools/fill_stage1_config.py, MIT"). It fills a versioned config block **in place** so that "the image keeps its length and STACKBOT tail":
  - magic `AURORA-S1-CFG01\0`;
  - body `<II40s192s>` = version 1, proxy window ms, ESP UUID, `;path`;
  - CRC32.

  It checks `image.endswith(b"STACKBOT")` and that the magic occurs exactly once. **No size, padding or alignment change**, apart from a board allowlist by OS firmware (`BOARD_STAGE1`, `j613ap` → `"26.6.2"`).
- No installer checks or adjusts the image for iBoot. The kmutil call is the same as ours.

## (3) Must the image be a valid Mach-O despite `--raw`?
- **No evidence it must.**
  - Asahi says raw is a supported format since 12.1.
  - Our stored IM4P payload carries no Mach-O wrapper (report 16).
  - rolotrealanis98 reports kmutil refuses a Mach-O/BootKC on 27.2, and plain raw m1n1 boots on 20457.x (report 19).
  - On 26.6.2 a raw *Aurora* stage 1 boots J613 (REPORTED, guide + engine allowlist).
- So raw is accepted on 26.6.2. The stock image fails and the patched one passes; that difference is **inside the image**, not Mach-O vs raw. Not knowing the patch, I can't name the byte-level requirement.

## Other useful facts from these sources
- `M3-AIR-26.6.2.md:25`: "Make the full 26.6.2 volume the **default Startup Disk** before … hold power … **A one-time volume selection does not select its paired Recovery.**" This independently confirms the report 18 correction.
- `:35`: "Restore your working default Startup Disk before testing … explicitly select the 26.6.2 volume for the first installed cold boot." This is the one-shot test pattern we want.

## Recommended next steps
1. **Conservative, no restricted code:** test our own images on 26.6.2 for layout hypotheses that iBoot could check. Each needs a *verified* install (kernelcache.custom.* hash changed):
   - (a) branch at 0 + 16 KiB padded (beacon3, pending);
   - (b) the same with an m1n1-style trailing `STACKBOT`-terminated var block [HYPOTHESIS, weak];
   - (c) size rounded to 16 KiB vs not.
2. **Ask (owner/PM decision):** the reason for the m3next fix is documented only in restricted aurora-silicon/m1n1. An authorized human could read the commit message or release notes of `v1.6.1-m3next.stage1` / `j613-stage1-20261009` and pass on the plain-language reason (not code). Alternatively, ask in omacom/linux-aurora #26 or #72, which is allowed and public: "why does stock stage1 panic iBoot on 26.6.2, and what did m3next change?".
3. **Firmware route** (report 19): a stub on 27.x stage 2 avoids 18000.161.x entirely. It needs owner approval.


## NATIVE update 2026-11-04 (owner-verified; supersedes the open ranking for this question)
**beacon3 painted GREEN on stub firmware mBoot-18000.161.10.** beacon3 is a raw image with a **branch at file offset 0** plus **16 KiB padding**, and it was installed via `finish-install.sh` (a real kmutil install, unlike the retracted probe2 cycles). This is the first native code execution.
- The stock-image iBoot panic on 26.6.2 (ours and, REPORTED, asahi stage 1 on J613) is **avoided by our header**: a branch at offset 0 and/or 16 KiB padding. Which of the two matters isn't separated yet.
- The 26.6.x firmware itself doesn't block raw boots, so Plan B (report 22) stays a fallback only.
- The earlier retraction (probe2) stays as written; this result comes from a different, verified install.
