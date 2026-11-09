# 02 — J714s dump analysis + contribution policy

Inputs: `reports/02-j714s-dump.txt` (PM-run, scrubbed, 2026-11-04). The diff tool is `tools/compat-diff.sh`. **[guess]** marks inference.

## Headline

**Someone is already doing exactly our mission, publicly.** [betizzel/omarchy-m5](https://github.com/betizzel/omarchy-m5) targets "M5 Pro MacBook Pro, T6050, Mac17,9 / J714s", using m1n1 + linux-asahi, tethered from a ThinkPad. They report these as verified on hardware: iBoot → m1n1 → Linux, **single-core**; Arch root on the internal NVMe (dual-boot); simplefb console; built-in keyboard and trackpad; USB gadget networking; and an m1n1 patch that unblocks USB on T6050. Not done: SMP (the "open blocker"), GPU, N1 Wi-Fi/BT.

The same wall is documented on a J714c (14" M5 Max, also chip-id 0x6050) by edimoldovan in [omacom/linux-aurora#293](https://github.com/omacom/linux-aurora/issues/293). Secondary cores power up but are never released from reset. On T6050 that release goes through the **PMP coprocessor**, which no loader starts. The GPU's `cs` power domain is blocked by the same PMP (`notify_pmp`): the asahi G17 driver comes up, but jobs stall. **PMP bring-up on T6050 is the single key that unlocks both SMP and the GPU.** It's the frontier, and the right place for us to aim.

## Part C — the dump

| Item | Value | Notes |
|---|---|---|
| Chip | `chip-id 0x6050`, rev `0x11` | **T6050 confirmed.** |
| Board | `board-id 0x8`, J714sAP, Mac17,9 | |
| macOS / firmware | 26.6.2 (25G83); system firmware and OS loader `mBoot-18000.161.10` | Same firmware for both, which simplifies the stub. |
| CPUs | 15 = cluster 0: 5× M (cpu0–4), cluster 1: 5× M (cpu6–10), cluster 2: 5× P (cpu12–16). Gaps at cpu-id 5, 11, and 17 are binned cores. | macOS calls P "Super" and M "Performance". CPU compatibles are the stale M3 names `apple,sawtooth` / `apple,everest`, as #706 saw on T8142. The boot CPU is cpu0, an M-core (matches #610). |
| UART | `uart0@5200000`, `uart-1,samsung` (old Samsung UART, already supported) | Consistent with m1n1's `EARLY_UART_BASE 0x505200000` if arm-io sits at `0x500000000`. [guess: arm-io `ranges` weren't captured, see script bugs below.] `dockchannel-mtp@94B00000` (`dockchannel,t8002`) is the keyboard/trackpad. |
| Wi-Fi/BT | **Apple N1**: `centauri-control/alpha/beta`, PCI `106b:1901/1902/1903` | **Not Broadcom.** No Asahi driver. Only Aurora's `t6050/centauri-*` branches touch 1902/1903. |
| SD reader | `pci17a0,9755` (Genesys GL9755) | Linux already has a driver. |
| bputil -d | skipped: requires root | As expected. |

**Compatibles** (153 unique; full table produced by `tools/compat-diff.sh`):
- **New-generation strings, our work list** (`t6050`/`t605x`, or `t8142` reused on our board). Nothing in upstream m1n1 or the Asahi kernel matches them exactly:
  - Platform: `arm-io,t6050`, `pmgr1,t6050`, `mcc,t6050` (m1n1 has MCC only for T8142; needed for the hypervisor), `soc-tuner,t6050`, `error-handler,t6050`, `clpc,t6050`, `apple-processor-trace,t6050`.
  - PCIe/USB: `apcie,t6050`, `apciec,t6050`, `usb-drd,t6050`, `usb-drd,t8142`, `usb-auss,t6050`, `atc-phy,t6050` (an `atc-phy,t6040` is also present).
  - Display: `disp0,t605x`, `dispext0..3,t605x`, `display-crossbar,t6050`, `atc-dpxbar,t6050/t8142`, `dptx-aux,t8142`, `dptx-ufp-aux,t8142`.
  - Audio: `admac,t6050`, `admac,t605x`, `admac-evolution,t6050`, `admacled,t6050`.
  - **`gpu,t6050`**.
  - N1 (above).
  - The PMP shows up as `pmp0` with `iop,ascwrap-v6`, a new ASC wrapper generation that Aurora has a binding for.
- **Reused older blocks**, likely handled by existing drivers once the DT is written: `dart,t8110`, `aic,3`, `i2c,t8101`/`s5l8940x`, `gpio,t8101`, `spi-1,spimc`, `wdt,t8101`, `jpeg/scaler/aod,t8101`, `avd,t8103`/`t6020`, `dptx-core,t8103`, `pcie-apiodma,t6020`, `dockchannel,t8002`, `aapl,spmi`, `pmu,spmi`, `usbc,sn201202x,spmi` (ACE3 over SPMI, as on M3 Pro+), and audio codecs `cs42l84`/`sn012776`.
- Caveat: Linux DT compatibles are Asahi-style (`apple,t6000-…`), not ADT strings. So "known" on the Linux side is by family, and the authoritative list is the new-suffix list above.

**Script bugs, for any re-run:**
- The `uart0`/`arm-io` lookups by `-n` name matched the root node instead, so that section dumped the whole tree.
- The root `compatible`/`model` lines came out empty.
- Fix: look nodes up with `ioreg -p IODeviceTree -l -w0 | awk` by `+-o name@`, or rerun with `--full`.
- No `<scrubbed>` lines appear in the output. Either nothing identifying was printed or a key escaped the filter, so please confirm the dump was eyeballed before it was committed.

## Part B

### 1. AI/LLM rules
- **omacom/Omarchy: no restriction, and agents are expected.** `omacom/omarchy` ships `AGENTS.md` (+ `CLAUDE.md` → `@AGENTS.md`) with "agents/skills" procedures. `omarchy-mac-pkgs` has `AGENTS.md`/`CLAUDE.md` with engineering rules only. I found no AI clause in CONTRIBUTING or the PR templates.
- **Aurora Silicon** ([`aura/.github/aurora/AGENTS.md`](https://github.com/aurora-silicon/aura/blob/main/.github/aurora/AGENTS.md)) has "Aurora Silicon's own policy for AI coding assistants". It has two rules: "Only public code goes in. Never copy code from proprietary sources." and "Changes are tested on the hardware they affect before they are merged." A workflow keeps upstream (Asahi) agent files from overwriting it. `linux-aurora` CONTRIBUTING covers report format only (board, SoC, release tag, both firmware versions).
- **Asahi:** banned (see 01). So Omarchy and Aurora are the AI-compatible venue, and Asahi is human-only.

### 2. T6050 results posted so far
| Who | Machine | Result | Where |
|---|---|---|---|
| betizzel | **J714s** (our board) | Single-core Linux, NVMe root, fb, keyboard, trackpad, USB gadget; SMP blocked. Also feeds data on #293. | [omarchy-m5](https://github.com/betizzel/omarchy-m5), `FOR-AURORA.md` |
| edimoldovan | J714c (M5 Max 14", 0x6050) | Aurora kernel single-core, USB2, NVMe, Omarchy started, trackpad. GPU driver/firmware init OK, jobs stall on `cs`/PMP. PMP + SMP analysis (2026-11-03). | [installer#149](https://github.com/omacom/omarchy-mac-installer/issues/149), [linux-aurora#293](https://github.com/omacom/linux-aurora/issues/293); branches `edimoldovan/linux-aurora:t6050-j714c`, `edimoldovan/m1n1:t6050-aurora` |
| birkskyum | J716c (M5 Max 16") | ADT only (can't run m1n1); `ioreg2adt.py`; PMP `ptd-range` matches J714c | #293 |
| MarianoMiguel | J716C | ADT vs APIF assumptions | [aurora #142](https://github.com/aurora-silicon/linux/discussions/142) |
| scottjones | J815 (base M5) | Linux **with all 10 cores** under Aura: the PMP wall is T6050-only | #293 |
| Yureka (Asahi) | M5 Max MBP | m1n1 basics (#578, #610) | upstream |

Aurora #142 itself still has no J714s boot log. The sitewide "works" claims remain unsupported. The real evidence lives in #293 and betizzel's repo.

### 3. proxyclient host requirements
The host must be **physically cabled** USB-C ↔ a Thunderbolt port on the MacBook (any architecture; Linux preferred, macOS works too).
- **Python ≥ 3.9**, with `pyserial` and `construct` (required). `IPython` is optional, for nicer `shell.py`. Example: `python3 -m venv ~/m1n1-venv && ~/m1n1-venv/bin/pip install pyserial construct ipython`.
- **USB access:** install `udev/80-m1n1.rules` to `/etc/udev/rules.d/` (VID:PID `1209:316d`; it gives `/dev/m1n1` = interface 0 and `/dev/m1n1-sec` = interface 2). Put the user in the tty group (`uucp` on Arch, `dialout` on Debian), or edit the rule's `MODE`. This is a system-wide install, so the task must allow it. Add `picocom` for `tools/picocom-sec.sh`.
- **Building m1n1** (not needed if prebuilt): clang + lld (the default `USE_CLANG=1`) or `aarch64-linux-gnu-` gcc; `make`; and **Rust with cargo** (m1n1 has a Rust lib; nightly features are enabled via `RUSTC_BOOTSTRAP=1`, plus `-Z build-std` on some setups).
- **Kernel builds:** aarch64 cross toolchain, `dtc`, Rust toolchain plus bindgen for the asahi kernel's Rust drivers.
- **Which machine:** whatever sits next to the MacBook. ush is leaving, so [guess] a small Linux box or laptop, or another Mac (a second machine) if it's co-located (it also covers DFU revive). Note: m1n1's proxy ABI is not stable, so host-tool and on-device m1n1 versions must match. `run_guest_kernel.sh` handles this by chainloading.

## Recommendation for the PM
Don't redo betizzel's single-core bring-up. Next step:
1. Contact betizzel (repo) and edimoldovan/birkskyum (#293). the owner or the PM posts, in the omacom/Aurora venues, where AI help is allowed.
2. Get their m1n1 patches and DT for J714s.
3. Reproduce single-core on our J714s, which is ladder step 2–3 with known-good parts.
4. Put our effort on **T6050 PMP start**, which gates both SMP and the GPU.

Keep anything aimed at Asahi human-written.
