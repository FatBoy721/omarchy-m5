# 16 — The fuOS object kmutil stored (pending PM data) + the 0xcb0000 question

## What we already know (NATIVE)
| Boot object | Size | Result |
|---|---|---|
| m5boot (raw) | 49,034,128 B (46.8 MiB) | logo → power-off ×5 → Recovery (PanicMedic); SOCD: iBoot panic `3bdace14b1a9a68:1026` right after the `fuos` breadcrumbs `3000f/3000c/3000d/30010` (report 15) |
| m5boot-gz | 18.9 MB (~18.0 MiB) | **same** loop, ×5 → Recovery. `panicmedic-telemetry` shows the same boot stage 0x22 (34). No new SOCD `.panic` file |
| probe | 192 KB | testing now (PM) |

## Is 0xcb0000 plausibly a fuOS size cap?
- The breadcrumbs `40038(0xcb0000) 40059(0) 40039(0x1ff8000) 4003a(0) 4005a(1) 40061(0)` are logged right after `sepi` (SEP image) and **before** `stg1`…`fuos`. Neither value is documented anywhere public (report 15).
- **The new result argues against 0x1ff8000 (31.97 MiB) as the cap:** 18.0 MiB < 31.97 MiB, yet `m5boot-gz` failed at the same stage.
- **0xcb0000 (13,303,808 B = 12.69 MiB)** is consistent with both failures (46.8 MiB and 18.0 MiB both exceed it), and so is any non-size cause.
- **[HYPOTHESIS] Ranking**, from the two NATIVE data points:
  1. A cap ≤ ~18 MiB, of which 0xcb0000 is the only candidate number in the evidence. Its position next to `sepi` could mean a SEP/region size rather than fuOS, which is why this is only a hypothesis.
  2. Something unrelated to size that both images share. For example, kmutil's raw-to-Mach-O wrapping of a single large segment at VA 0, our first instructions, or an assumption in m5boot's header/layout. That would fail at any size.
- **Deciding tests, no extra arms needed beyond these:**
  - **192 KB probe:** works → size is the issue (the cap is between 192 KB and 18.0 MiB). Fails → not size (go to cause 2).
  - If it works: the probe **padded to 12.0 MiB** and **to 13.5 MiB**. Works at 12.0 but fails at 13.5 ⇒ 0xcb0000 is the cap.
  - Each test boots once via Startup Options → Omarchy → **Continue**, with Macintosh HD as default (report 15), so PanicMedic can't loop.

## Locating the stored object: exact read-only commands for the PM
On the Mac, `ssh -tt macbook`. `sudo` is used only for reads, and the one mount is read-only. **Don't copy or paste `.im4m` manifests or `bputil` nonce/ECID lines** (rule 6).
```sh
# 0. which volume is disk3s3, and the stub's volume group
diskutil info disk3s3 | grep -E 'Volume Name|Mount Point|APFS Volume Group|Volume Role|APFS Container'
diskutil apfs list | grep -B2 -A14 'Omarchy' | grep -E 'Name:|Role|Volume Group|APFS Volume Disk'
VG=<stub volume-group UUID from the line above>

# 1. mount the stub Preboot read-only if it isn't mounted
diskutil info disk3s3 | grep 'Mount Point'          # "Not mounted"? then:
sudo diskutil mount readOnly disk3s3
MP=$(diskutil info disk3s3 | awk -F': *' '/Mount Point/{print $2}'); echo "MP=$MP"

# 2. where kmutil put the custom boot object (names, sizes, dates)
sudo find "$MP" -maxdepth 4 -type d | sed "s|$MP||" | head -60
sudo find "$MP" -type f \( -iname '*kernelcache*' -o -iname '*.im4p' -o -iname '*.img4' -o -iname '*custom*' -o -iname '*fuos*' \) -exec ls -l {} \;
sudo find "$MP" -type f -mtime -3 -size +100k -exec ls -l {} \;      # large files written in the last 3 days

# 3. copy the custom kernelcache / fuOS object (our own code, no secrets) for analysis on ush
sudo cp "<path from step 2>" /tmp/fuos-stored && sudo chown "$USER" /tmp/fuos-stored
shasum -a 256 /tmp/fuos-stored; ls -l /tmp/fuos-stored
xxd -l 64 /tmp/fuos-stored
#    then copy /tmp/fuos-stored to ush:~/m5-omarchy/build/fuos/ and I run:
#    tools/fuos-inspect.py build/fuos/fuos-stored <the m5boot-gz.bin that was armed>

# 4. LocalPolicy side: names and sizes only
sudo ls -l "/System/Volumes/iSCPreboot/$VG/LocalPolicy/"
sudo bputil -d -v "$VG" | grep -iE 'coih|fuos|custom|kernel|smb1|smb2|sip'   # no nonce/ECID lines

# 5. kmutil's own documentation of --raw on this macOS
man kmutil | col -b | grep -n -B1 -A6 -iE -- '--raw|--compress|--entry-point|--lowest-virtual-address|custom boot object'

# 6. tidy up: unmount only if step 1 mounted it
sudo diskutil unmount disk3s3
```

## What the analysis will report (`tools/fuos-inspect.py`, stdlib, self-tested on synthetic IM4P/IMG4)
- **Container:** IMG4 (IM4P + IM4M + IM4R), a bare IM4P (with its 4CC type, e.g. `fuos`/`krnl`), or a bare Mach-O. It also reports IM4P compression info (algorithm, uncompressed size) and LZFSE `bvx2`/`complzss` payloads.
- **Payload:** size and SHA-256; whether it equals our file byte for byte.
- **Mach-O load commands:** each `LC_SEGMENT_64` (name, vmaddr, vmsize, fileoff, filesize, prot), plus `LC_UNIXTHREAD` pc / `LC_MAIN`. This shows how kmutil mapped `--lowest-virtual-address 0 --entry-point 2048`.
- **Where our offset-0x800 bytes sit inside the payload**, which pins the file-offset → VA relation iBoot uses.
- **IM4M/IM4R are reported by size only**, with no values.


## Result (NATIVE object, analysed on ush with `tools/fuos-inspect.py`)
Stored object: stub Preboot `boot/<nsih>/System/Library/Caches/com.apple.kernelcaches/kernelcache.custom.<hash>` (path per PM). **18,896,763 B**, sha256 `68d9a1390859030d7fbfc0239279cdbd539b2c76917b1015f9ba3ac97836cbfc`.

| Layer | Finding |
|---|---|
| Outer | DER `SEQUENCE` **`IMG4`**, 3 elements: IM4P, then a `[0]` element of 2,612 B (the IM4M manifest; content not printed) |
| IM4P | fields `IM4P`, type **`fuos`**, description **`KernelManagement_executables-487.100.11`** (the kmutil/KernelManagement build that made it). **No compression element**, so it's stored uncompressed |
| Payload | 18,893,904 B, sha256 `dfab8d046940ce22f7a4af60bbfd36115c0c362c20645ef2871b3a3ec46e86fb`. **Byte-identical to the armed `m5boot-gz.bin`** (same size and hash) |
| Mach-O? | **No.** The payload starts `00000000…`, which is our own file (code at 0x800). kmutil `--raw` adds **no Mach-O wrapper, no segments and no load commands** to the stored object |

**Consequences:**
- **Container overhead:** 2,859 B (18,896,763 − 18,893,904): DER headers + IM4P strings + the 2,612 B IM4M. The image iBoot loads is exactly our file. **Its in-memory size equals our file size.** kmutil's `-C/--compress` would add an IM4P compression element and is untested here.
- **Segment layout / VA:** none in the object. The `--entry-point 2048 --lowest-virtual-address 0` values aren't in the payload, and no Mach-O carries them. [HYPOTHESIS] They're recorded in the IM4M manifest (2,612 B, the linked `fuos` manifest in Asahi `fw/boot.md` terms) or in the LocalPolicy. Reading them would need the IM4M's properties; it holds identifiers, so it stays on the Mac. If wanted, the PM can run a read-only, values-redacted dump later.
- **Load succeeded:** the SOCD breadcrumbs show the `fuos` load completing (report 15). So iBoot read and verified this 18.9 MB IMG4 (signature/hash against `coih`). The failure is after that.
- **Size comparison:** the stub's own Apple **`kernelcache`** in the same directory is **30,316,086 B** and is a normal XNU boot path. iBoot therefore loads 30 MB objects in general. Any size cap would be **specific to the fuOS path** (where or how a raw `fuos` payload is placed), not a general load limit. That keeps 0xcb0000 (12.69 MiB) a plausible but unproven fuOS-specific cap, and it rules out the "everything ≥ 18 MiB" reading for kernelcaches.
- **0xcb0000 vs 0x1ff8000:** with the m5boot-gz failure at 18.0 MiB, 0x1ff8000 (31.97 MiB) as a cap is **excluded**, assuming size is the cause at all. **0xcb0000 remains the only candidate number** consistent with both failures. The **192 KB probe** decides size vs non-size; if it boots, probes padded to **12.0 MiB** and **13.5 MiB** test 0xcb0000 directly.

**What to change if size is confirmed:** keep m5boot small. Ship only the shim + DTB + a compressed kernel/initramfs blob and inflate it in RAM after iBoot has handed off, with the fuOS object kept well under 12 MiB. Our current compressed payload alone is ~18 MB, so the kernel needs a size diet too: today `Image.gz` 16.3 MB + initramfs 2.4 MB. Options are a smaller bring-up config (modules out of the image; the gzip'd Image could drop well below 10 MB) or the loader-kernel design.
