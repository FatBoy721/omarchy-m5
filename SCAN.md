# SCAN: what was checked, dropped and scrubbed before publishing (2026-11-05)

Staged from `~/m5boot` and `~/m5-omarchy` into this fresh tree; nothing pushed. Fail-closed: when unsure, left out.

## Scanners
- **gitleaks/trufflehog: not run.** Installing the gitleaks release binary was refused by the session's permission policy (no external executables). We used our own stdlib scanner instead: `m5-omarchy/tools/secret-scan.py`, with gitleaks-style rules plus a project list:
  - private keys, ssh public keys, GitHub/AWS/Slack/OpenAI-style tokens, JWTs, `password=`/`token=` assignments, high-entropy blobs (≥40 chars, entropy > 4.5, git/sha hashes excluded);
  - known secret strings (passed via the environment, not stored); emails; Tailscale 100.64/10 IPs; MAC addresses; UUIDs; ECID; Apple serial patterns; home paths. Personal names and the local user name are passed the same way, via the environment.
- **Result on the final tree: 13 hits, all reviewed benign:**
  - 9 "high-entropy" hits are long file paths;
  - `/home/alarm` ×2 is Arch Linux ARM's default user;
  - an Alpine package-signing key file name;
  - the one image file, a QEMU screenshot of Omarchy (no photo).
- **Manual greps** for the same patterns, plus a 6-word-shingle comparison against the private Discord message, to find verbatim quotes.

## Not included at all
- **Binaries:** every `m5boot*.bin`, kernel Image/Image.gz, DTBs, initramfs cpio, rootfs ext4/tar, the probe module build products. Only their SHA-256 values appear.
- **Apple material:** the extracted trackpad firmware (`tpmtfw-j714s.bin`), IPSW-derived bytes, the macOS panic report JSON (`native-panic-1.json`, iBoot UUID/board data).
- **Raw ADT / device dumps:** `reports/02-j714s-dump.txt`, `reports/04-j714s-full.txt`.
- **Photos/videos of the screen:** `native-gz5-linux-serror.jpg`, `native-gz3-screen.jpg`, `native-gz4-screen.jpg`, `native-gz6-f06/f12/f14.jpg`. They're described in text in JOURNEY.md.
- **Keys:** `work.pub` / authorized_keys (m5boot `spec/work.pub`, `build/work.pub`), anything from `~/.ssh`.
- **Research-only, aura-derived material** (decoded with layouts from an m1n1 descendant, used under a research-only owner decision):
  - `reports/05-audit-and-build.md`, `reports/06-evidence.md`, `reports/09-rootfs.md` (uses those addresses);
  - `tools/adt-pmp-decode.py`, `tools/t6050-probe/` (its probe addresses come from that decode);
  - one sentence in `reports/25-pmgr-reset.md` (marked in place).
- **m1n1 / forks:** nothing (none was ever used).
- **The private Discord message** (`research/betizzel-*.txt`): not included. Four verbatim quotes in `m5boot/tasks/19-secwdt.md`, `m5boot/NOTES.md`, `m5-omarchy/tasks/28-input-usb.md` and `m5-omarchy/reports/28-input-usb.md` were replaced with short credited summaries. README credits it as a summary.
- **Internal-only files:** `tools/pm-watch*.sh` (PM session helpers), m5boot `build/` and `ref/` (upstream reference clones), `__pycache__`.

## Scrubbed in the included files
- The password-like string in `m5-omarchy/tasks/29-publish.md` → `<redacted>`; the partial personal email there → `<redacted email>`.
- iBoot build UUID (from the panic report) → `<uuid>`.
- Local home paths → `~`; the local user name in `user@host` → `user@` (incl. the kernel build banner in `logs/`).
- The owner's name → "the owner". A personal machine's hostname (in reports 01, 02 and task 01) → "another Mac". Machine nicknames kept: `ush`/`work` (build host), `macbook`.
- `logs/`: UUID/MAC pass (none found besides public GPT type GUIDs); the build banner is scrubbed.

## Kept on purpose
- Public GPT partition-type GUIDs, public GitHub handles, public issue/comment URLs, MMIO addresses from our own ADT dump, SHA-256 hashes of our builds and of public Apple IPSW members.
- Commit identity: this repo uses `TripleU613 <TripleU613@users.noreply.github.com>` (no personal email in git metadata).
