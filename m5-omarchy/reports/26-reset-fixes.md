# 26 — Candidate fixes for the ~45 s idle reset (VM: all reach the shell; NATIVE pending)

One kernel (`build/slim-v4/Image.gz`), three variants. Hashes are in `~/m5boot/spec/inputs.md` § Slim v4.

| Variant | What changes | Removes |
|---|---|---|
| **A** | cmdline `m5_pmgr_ro` (new switch in our patch 0002) | **every** PMGR write from Linux: genpd power on/off, the always-on power-up, probe min-state/auto-enable, reset assert/deassert. Domains still register with their boot state, so consumers (NVMe) still probe. Each skipped write is logged `m5 pmgr: <domain> SKIP(ro) …` |
| **B** | A + `fw_devlink=off deferred_probe_timeout=0` | additionally the device-link/sync_state machinery and the deferred-probe timeout teardown |
| **C** | DTB C: gz6+fb with dwc3_0 + both DARTs, the 3 pinctrl blocks, serial0 and the wdt node **disabled** | the late/deferred probes: USB0 (its DART -110, the PMP-notified ATC0 chain, report 25) and the pinctrl suppliers behind "sync_state() pending" |

**Why not "no PMGR driver"** (the literal A): with the driver gone, every `power-domains` user defers forever, NVMe included. Then the deferred-probe timeout tears them down, which is the very path we suspect. The read-only switch gives "zero PMGR writes" and keeps the probes.

**Facts used:**
- Our genpd core already skips the sync_state power-off under `pd_ignore_unused` (betizzel's `drivers/pmdomain/core.c` change, verified in the tree).
- Runtime-PM power-offs of *used* domains, and power-ons from retried/failed probes, are **not** covered by pd_ignore_unused. A/B close those.
- In the slim kernel the pinctrl, s5l-uart and wdt drivers aren't built, so those nodes only feed fw_devlink waits.

**VM (QEMU virt, the v4 kernel + initramfs-slim):** A, B and C (C = the base cmdline; its DTB can't be used under virt) all reach `m5init: === shell …`. Limits: virt has no PMGR/Apple DT, so the VM proves only that the kernel and parameters don't break boot. It does **not** exercise the read-only path.

## Recommendation: first boot "A+C" = DTB C + `m5_pmgr_ro`
- It removes both prime suspects in one boot: Linux PMGR writes, and the late USB/pinctrl probes and their timeout teardown.
- **Safety:** with `m5_pmgr_ro` and the gz6 DTB (plain A), dwc3_0's DART would probe with its domain possibly **off**, and power-on is now skipped. That's the gz5 SError path again. DTB C disables it, so pair A with C.
- **Readout:**
  - Survives > 2 min idle: the fix is in that set. Bisect next with A alone on DTB C minus one item, or C without `m5_pmgr_ro`.
  - Still resets at ~45 s: neither PMGR writes nor those probes cause it. The last `m5 pmgr:` / initcall lines on screen give the next suspect, and B's `fw_devlink=off` is the next try.
- The opt-in ESP log (`m5.esplog=1`, report 25) would record the last dmesg before the reset; it's still waiting for owner approval.
