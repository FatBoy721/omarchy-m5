# 39: MTP keyboard/trackpad, get the MTP CPU running (top priority)
NATIVE facts (see ~/m5-omarchy/reports/37-mtp-power.md, 41-mtp-release.md, 42-t11-t13.md, native-t*.txt):
- MTP firmware is already in SRAM 0x294c00000 (vector table), CRC unchanged after RUN.
- RUN write at 0x294600044 accepted, but CPU_STATUS stays 0x4c; PS_PROT 0x2890fc000 ignores writes.
- DART-mtp TCRs (0x294801000+) for active streams are locked (PROTECT 0x1a), but unused stream 15 is writable.
Hypothesis: iBoot/stub left DART-mtp locked with a mapping Linux can't change; the MTP CPU stalls on its first DMA/fetch.
Do:
1. In m5boot (runs BEFORE Linux and before any lock we cause), dump DART-mtp state (TCR/TTBR/PROTECT for all streams) to the ESP log, and if not yet locked set the MTP stream to bypass or identity, the way the aurora kernel (GPL, allowed) expects for t60xx MTP. Do NOT read/use m1n1 or its forks.
2. If it's already locked at m5boot entry, record that and try: the MTP using stream 15 (writable) via the DT `iommus` / sid remap.
3. Build as a loop set (m5next and m5drop, like chain-n1j), VM-prove that the boot path doesn't break, and keep every native run auto-returning to macOS.
Print DONE 39 with the set path and what to look for in the log.
