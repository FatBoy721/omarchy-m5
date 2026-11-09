# Task 29 — stage a PUBLIC journey repo (owner request). Stage only; PM reviews + pushes.

Owner: public GitHub repo "Omarchy-M5-Pro" showing the whole journey: every gz build, every outcome, how we work. NO secrets.

Build the tree at ~/publish/Omarchy-M5-Pro (fresh dir, git init, no remote):
- README.md: what this is (native Linux → Omarchy on MacBook Pro 14" M5 Pro J714s, T6050), current status with labels (locally verified native / VM / third-party reported / hypothesis), how it boots (fuOS stub via betizzel's MIT scripts → m5boot → Linux → initramfs → switch_root Omarchy), how we work (PM Claude + worker Claude sessions; owner does physical steps), credits (betizzel/omarchy-m5 and his agent's Discord info [summarize, credit, don't paste the DM], Asahi Linux kernel, Aurora Silicon community threads by link only), and the AI/m1n1 note: we did not use or read m1n1/its forks; Asahi's policy forbids LLM-assisted contributions to Asahi, so nothing here is submitted there.
- JOURNEY.md: chronological table of EVERY gz/probe build (beacon…gz13): date/time, sha256 (from NOTES.md), what changed, native outcome (photos→text descriptions), label. Include the failures and retractions (invalid fast-cycle results, the wrong framebuffer address, cttyhack, the sfdisk logger bug, the secondary WDT 0x2_8833_0008 = 0x7c find).
- m5boot/: source, tests, spec (minus anything below), NOTES.md, tasks/. LICENSE GPL-2.0.
- m5-omarchy/: tools/ (kernel patches, dts overrides, build scripts, initramfs scripts, rootfs overlay), tasks/, reports/ — EXCLUDING the list below.
- logs/: the native m5log captures (reports/native-gz*-m5log-raw.txt) after scrubbing.
- No binaries at all (no gz*.bin, Image, dtb, cpio, ext4, firmware). Hashes only.

MUST EXCLUDE / SCRUB (fail closed — if unsure, leave it out and list it):
- Any password/PIN (grep for <redacted> and any 6+ digit secrets), tokens, private keys, authorized_keys/work.pub, ~/.ssh anything, Tailscale IPs (100.x.x.x), hostnames of personal machines may stay as "work"/"ush"/"macbook" only.
- Emails (<redacted email>, any personal), real names other than public GitHub handles; serial numbers, ECID, MAC addresses, UUIDs/VGIDs (replace with <uuid>), nonces, the raw ADT dump (reports/04-j714s-full.txt) and any raw ADT/IODeviceTree dumps.
- Apple firmware or extracted Apple binaries (tpmtfw etc.), IPSW-derived bytes.
- Anything from m1n1 or its forks (aura), and reports/sections with research-only aura-derived provenance (reports 05/06 decoded layouts etc.) — list what you dropped.
- Private Discord DM text verbatim (research/betizzel-*.txt): replace with a short credited summary.
- Photos/videos of the owner's room: none.
Then run a secret scan (gitleaks or trufflehog if installable as a user binary; plus your own grep list) and write SCAN.md (what was scanned, findings, what was dropped). Commit locally with message "Journey so far" + Co-Authored-By trailer: Claude Opus 5.5 <noreply@anthropic.com>.
Print exactly `DONE 29` (or `BLOCKED 29: <q>`). No dialogs. Do NOT push.
