# N1 Wi-Fi on J714s (M5 Pro): port of aurora-silicon/linux — findings (2026-11-05)

Labels: NATIVE = our own J714s ADT dump; REPORTED = aurora commit text / third-party; HYPOTHESIS = my inference, untested.
Repos: `~/m5-n1/linux` (alternates → our asahi tree objects, no checkout of m1n1 anything). ADT excerpt: `~/m5-n1/adt-apcie0-excerpt.txt` (= `reports/04-j714s-full.txt:3860-4300`).

## Pinned SHAs (github.com/aurora-silicon/linux, fetched 2026-11-05)
| PR | head SHA |
|---|---|
| #938 N1 integrated | 28c98074f21e272737608de1d86775217df05843 |
| #937 PCIe adopt/PERST | a873be047e9a514f8a2e886f5272c570e0dd6516 (ancestor of #938) |
| #945 J716c DT | 301c0e3ca37654c520e3b18f686effaf9880befa (NOT ancestor of 938; 12 commits apart) |
| #474 | 98663e5cbcd96ec4fdd6b88e93a031322d508900 (older APIF host variant, superseded) |
| #482/#483/#484 | a3cc8117 / 9a4dad6a / 93c2c77e (content is in #938 as de6d2888/d0f0e67e/d18473b8) |
| #946 | 31785b39df6b07a5c90e60b0a7e91851b048033e (not needed) |

N1-relevant commits in #938 (16, `b42e9ca0bfc8^..28c98074`): DT bindings b42e9ca0, 11481f95; PCI 660bd18c (adopt), 92841e50 (pci_trylock_rescan_remove), de86c93b (T6050 port reset/enable/configure/train), 94e4ebf6 (port-0 multifunction N1 + reset_root_port), a873be04 (PERST via pinctrl); N1 de6d2888 (fw+ACIPC), d0f0e67e (wifi), d18473b8 (BT), + 6 wifi/BT fixups. Diff: 15 files, +5054/-33.

## 1. Does J714s apcie port 0 carry N1? — YES (NATIVE)
- `apcie0@B0000000` compatible `apcie,t6050`, `#ports`=4 (ADT :3860, :3893).
- `pci-bridge0` `apcie-port`=0, `maximum-link-speed`=3 (Gen3), `centauri-builtin`, `keep-root-port-on`, `manual-enable` (excerpt :57,:60,:74,:75,:83).
- Endpoints behind it: `centauri-control` pci106b,1901 (:4185), `centauri-alpha` pci106b,1902 class 0d2000 Wi-Fi (:4238), `centauri-beta` pci106b,1903 class 0d1100 BT (:4288). Port 1 = GL9755 SD reader (pci17a0,9755, :4407). Note: macOS saw control as **0x1901** (firmware running); aurora driver accepts 0x1900 (ROM) or 0x1901.
- DART: `dart-apcie0@10000000` with mappers control/alpha/beta (+piodma sid 0x11) (:4447-4520) = J716c's "streams 1-3".
- Registers (NATIVE, from IODeviceMemory) match J716c DT (#945 t6050-j716c.dts `&pcie0`) exactly: config 0x1cb0000000/256M, rc 0x414000000, port0 0x410028000, phy0 0x417010000, intr2axi0 0x410024000; port IRQ 1523 (ADT `interrupts` first = 0x5f3), DART IRQ 1524 per die0.dtsi. ⇒ J716c `&pcie0` block is reusable for J714s nearly verbatim (HYPOTHESIS for IRQs beyond the first; check full `interrupts`).
- PERST#: `function-perst` = AP GPIO pin 0x50 = 80 (:81) — same as J716c `reset-gpios = <&pinctrl_ap 80 ...>`. CLKREQ pin 0x4c (:73).
- N1 reset: `function-reset` = SMC (phandle 0x27c) key `gP13`, arg 0x8000 (:71); `function-warm_reset` (:65) also SMC. J716c comment: "boot loader trains the link after the SMC releases the N1's reset" (REPORTED).
- Tunables present on root port: `apcie-config-tunables`, `pcie-rc-tunables`, `pcie-rc-gen{3,4,5}-shadow-tunables` (:51-:70); host-level PHY: `apcie-phy-tunables`, `apcie-phy-ip-pll-tunables`, `apcie-phy-ip-auspma-tunables`, `apcie-cio3pllcore-tunables`, `apcie-pcieclkgen-tunables`, `apcie-axi2af-tunables` (:24-:44).
- Power-gates (NATIVE, decoded from pmgr `devices`, ADT :117, id at byte 26): 0x89 APCIE_GP, 0x8a APCIE_GE, 0x8b APCIE_ST0, 0x8c APCIE_ST1, 0x8e ANS, 0x8f APCIE_SYS_GP, 0x90/0x91 APCIE_SYS_ST0/1, 0x97 APCIE_SYS_GE, 0x9c APCIE_PHY_SW, 0xae-0xb6 APHY_{ST0,ST1,GE,GP}_AUS5[_A] (pmgr regs 0x240-0x280). Our `t6050-pmgr.dtsi` has apcie_gp/sys_gp/phy_sw but **no APHY_*_AUS5 domains**.
- Platform ID: J716c uses 0x000e6050 (board 0x0e). Ours `board-id`=0x8 (ADT :20) ⇒ **0x00086050** (HYPOTHESIS: same encoding).

## 2. What #937/#938 expect at kernel start (REPORTED from code, `drivers/pci/controller/pcie-apple.c` @28c98074)
`apple_pcie_adopt_link()` (:1675-1801) refuses the port (-ENOLINK/-ENODEV) unless ALL hold:
- CORE_RC_CTL RUN, CORE_RC_STAT READY; PORT_STATUS READY; LINKSTS UP && !BUSY; LTSSMCTL START; APPCLK &0x101 == 0x101; PERST reg &0x10001 == 1; PHY_LANE_CFG &0x1000061f == 0x60f.
- Root port 0x100c106b, bus numbers set by loader (primary 0, secondary=subordinate), x1 link Gen1..Gen3; endpoint present, CMD mem/io/master off, MSI/MSI-X off, RID2SID table empty.
- t6050_hw comment (:265): "Firmware owns power, PHY, reset and training." No PMGR/clock calls on t6050 (`retain_clocks`).
- Tunables are read from DT root-port node as `apple,apcie-config-tunables`, `apple,pcie-rc-tunables`, `apple,pcie-rc-gen{3,4,5}-shadow-tunables`, u32 groups (offset, 4, mask, value), max 16 entries (`apple_pcie_t6050_tune` :1871). Loader is expected to copy them; we can bake them statically from ADT (ADT entries are offset u32, size u32, mask u64, value u64 → take low words).
- Kernel already implements (de86c93b, used by `reset_root_port` :2120ff): port disable, port reset table, port enable (PERST handshake, APPCLK), RC configure (tunables, Gen3 x1, speed change), train (PHY refclk0/1 req/ack, PERST# GPIO release, LTSSM, 100 ms).
- Kernel does NOT implement: PMGR power-up of APCIE_*/APHY_* domains, shared PHY/PLL init (`apcie-phy*`, `cio3pllcore`, `pcieclkgen` tunables + PLL lock), core RC enable, SMC `gP13` N1 reset release, bus numbering.
- m5boot does none of this (NATIVE: no pcie code in ~/m5boot/src).

**Can the kernel do it alone? — Plausibly yes, but it is new clean-room work (HYPOTHESIS).** Minimal own patch (`pcie-apple-t6050-cold.c`, GPL-2.0, hooked before adopt when `apple,kernel-cold-init` is set):
1. `pm_runtime`/power-domains: apcie_gp, apcie_sys_gp, apcie_phy_sw, + new aphy_gp_aus5(_a) nodes (pmgr 0x258/0x280) → add these labels to `m5_pmgr_allow=` (`apcie_gp,apcie_sys_gp,apcie_phy_sw,aphy_gp_aus5_a,aphy_gp_aus5`; plus ans/fab6_soc already on for NVMe).
2. Apply host PHY tunable lists from DT (copied from ADT) to the phy/ip regions in ADT order: pcieclkgen → phy-ip-pll (poll PLL lock bit — UNKNOWN) → auspma → phy → cio3pllcore → axi2af. Order and lock bits are the unknown; must be found by MMIO-tracing/inspection on our own hardware, not from m1n1.
3. Set CORE_RC_CTL RUN, wait RC_STAT READY.
4. SMC write key `gP13`=0x8000-ish (exact value semantics UNKNOWN; macsmc gpio driver in our tree can expose it as a gpio line).
5. Call aurora's existing `apple_pcie_t6050_port_enable/configure/train` (Gen1 for ROM), program bus numbers 0/1/1, then fall into `apple_pcie_adopt_link()` unchanged.
Risk: wrong PHY sequence = no link (non-destructive; port stays off). PMGR writes are the only hazard, gated by the allow-list.
Alternative: m5boot loader change (needs physical reinstall) — avoid.

## 3. Firmware (REPORTED from code)
- Single file: DT `firmware-name` on the control node, e.g. `apple/centauri/j716c-ftab.bin` (#945 dts:92). Driver: `request_firmware_direct()` (centauri_pci.c:123), must be an RTKitOS image with `rkosftab` at offset 0x20 (:133) containing a `2ftb` secondary (centauri_ipc.c:92). BT/Wi-Fi request no other files; no calibration/NVRAM file (regulatory from cfg80211). For us: `/lib/firmware/apple/centauri/j714s-ftab.bin`.
- Doc (`Documentation/arch/arm64/aurora-apif-centauri.rst:14`) says the FTAB is **personalized** and supplied by the boot producer. Exact macOS path NOT confirmed (HYPOTHESIS). Commands for PM on the Mac (read-only):
```
ioreg -l -w0 | grep -iE 'centauri|firmware' | head -50
kmutil showloaded 2>/dev/null | grep -iE 'centauri|n1|wlan'
sudo find /usr/share/firmware /usr/standalone /System/Volumes/Preboot /System/Library/Extensions /System/Library/PrivateFrameworks -xdev -type f \( -iname '*centauri*' -o -iname '*ftab*' -o -iname '*n1*' \) 2>/dev/null
sudo find /usr/share/firmware /usr/standalone /System/Volumes/Preboot -xdev -type f -size +64k -exec grep -l -a 'rkosftab' {} + 2>/dev/null
```
  If a hit is an IM4P, extract the payload (`img4tool -e` or pyimg4 on ush, decompress lzfse) and check `rkosftab` at 0x20. If only found inside an IPSW: `ipsw` / `unzip` the J714s restore bundle on ush, same grep. Copy candidate(s) to ush ~/m5-n1/fw/ via scp; nothing written on the Mac.
- Also needed in DT: `local-mac-address` (alpha) and `local-bd-address` (beta) — scrubbed in our dump; PM reads them from `ioreg -l -w0 -n centauri-alpha` / `-n centauri-beta` or `networksetup -getmacaddress en0`.

## 4. Build plan
Trial results (NATIVE, ush):
- **N1 commits onto our asahi 236788cd**: 1st commit conflicts in binding yaml (trivial); 2nd (660bd18c) 16 conflict hunks in pcie-apple.c. Aurora's pcie-apple.c/apple-dart/pinctrl differ from ours by +7389/-348 lines; whole tree is v7.3 vs our 7.2 (+1.5M lines). Backporting = rewrite of PCIe host → **not recommended**. Log: `~/m5-n1/cherry-pick.log`.
- **Ours onto aurora #938** (branch `ours-on-aurora`, reset after test): `git apply --3way` of our 2707-line working diff → 12 files conflict, ~84 hunks (`~/m5-n1/ours-on-aurora-conflicts.txt`): dockchannel-hid.c 45, nvme/apple.c 10, spmi 8, pmgr-pwrstate 7, rtkit-helper 5, aic 3, rest 1 each. Our 17 untracked DT files add cleanly as new files. Aurora already has T6050 support (#945 die0.dtsi, pinctrl uncached regmap 264b181b).
- Recommended: base = #938 + cherry-pick #945's 12 commits (`refs/pr/938..refs/pr/945`, DT + pinctrl), then port ours: keep only what aurora lacks (m5fb earlycon, m5_pmgr_ro/allow, rtkit cold restart, our J714s DT); drop betizzel bits aurora supersedes. Est. 1-2 days for conflicts.
- J714s DT: copy `&pcie0`/`port00`/n1_* from j716c.dts; `apple,centauri-platform-id = <0x00086050>`; `firmware-name = "apple/centauri/j714s-ftab.bin"`; tunables baked from ADT; leave status disabled until (2) works; `gpio-reserved-ranges` to open pin 80.
- Config: CONFIG_PCIE_APPLE, CONFIG_APPLE_CENTAURI(+_WIFI), CONFIG_BT_HCICENTAURI, CONFIG_PINCTRL_APPLE_GPIO, CFG80211.

## 5. Licenses
- aurora-silicon/linux: GPL-2.0 (pcie-apple.c, centauri_*.c, btcentauri.c: `GPL-2.0-only`/`GPL-2.0`); DTS `GPL-2.0+ OR MIT`. Our derived patches must be GPL-2.0 (DTs may stay dual).
- AsahiLinux/linux base: GPL-2.0. Our ADT dump: our own data. N1 FTAB firmware: Apple proprietary; redistribution not allowed — keep local only, never commit to repos.
- Not used: m1n1 / aura / m1n1-aurora (not read, cloned, or run).

## Build 1 (2026-11-05, coordinator follow-up): ~/m5-n1/out/
- Branch `m5-n1` = #938 @28c98074 + #945's 12 commits (applied cleanly) + f0ef16e9 (our 0001-0003, ported by hand) + c235213b (J714s DT). See out/README.md.
- MTP keyboard (asked): aurora HAS its own T6050 MTP support, and it differs from ours.
  - Aurora: generic `apple,dockchannel-hid` + `apple,t6050-mtp`/`apple,rtk-helper-asc4` (t6050-max.dtsi:74-115). rtkit-helper adopts a live RTKit session handed over by aura (contract `mtp-live-v1`, rtkit-helper.c:25, :270ff). The trackpad AFE is reset through SMC pcIO GPIO (j716c.dts `apple,afe-reset-gpios`, `smc_pcio`).
  - Ours (betizzel + task 30): `apple,t6050-dockchannel-hid`, cold-restarting the iBoot-started MTP, with no SMC.
  - The build uses aurora's driver + our cold restart, and does NOT set afe-reset (no SMC).
- Blocker for a standalone DTB: needs the ESP's `m5log/live-fdt.dtb` to merge in m5boot's /memory and reservations (out/merge-live.py).
- Aurora's T6050 PMGR DT has no apcie/aphy domains (17 pwrstate nodes only). A cold-init attempt needs them added.
