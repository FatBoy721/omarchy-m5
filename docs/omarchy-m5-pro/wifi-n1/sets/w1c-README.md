# w1c: as w1b (a2 Image, w1b dtb, allow-list ans only) + module that also runs without the DT node, + DT evidence in the log. Read-only. Not booted.
- Image = a2 (47587f08...). The dtb = a2 allow-list + `/m5-n1-w1` (compatible only: no power-domains, no reset-gpios). No apcie PMGR nodes, no pinctrl. Merged with live-fdt.dtb.
- cmdline = a2's with marker N1-W1B (m5_pmgr_allow=ans only).
- The module now accepts a missing reset-gpios; the PERST#/train stages refuse without it. The runner runs only `pmgr`, `power` and `rc`:
  - `pmgr`: PMGR PS register reads.
  - `power`: no domain is attached, so no write. It returns -EIO unless the apcie chain already reads ACTIVE, and that stops the runner.
  - `rc`: runs only if the chain is ACTIVE, so no unpowered block is read.
- The module source also fixes a w1 bug: the `phy` stage now writes only port 0's lane (reg[2]+0x10000). In w1 it also wrote phy1..3 and +0x20000, which may serve the storage ports. w1b never runs that stage.

## Why w1c: the W1b kernel did NOT run on our dtb (native-w1b.txt)
- The genpd providers in its dmesg include `apcie_sys_gp_oc`, `apcie_sys_st0_o` and `apcie_sys_st1_o`. Those labels exist only in the loop-v1 / live FDT, not in our w1b dtb (dtc: 0 hits in ours, 1 in live-fdt.dtb). The MTP HID also probed as `294b28000.input`, the loop-v1 layout.
- So `/m5-n1-w1` was absent and m5_n1 never bound. The runner ran in the initramfs (5.8 s) and again in the rootfs (12.5 s, "File exists").
- **Implication:** a2/A2V3/W1B all ran aurora's kernel on loop-v1's DT. The SART/NVMe fixes still mattered, because the live DT uses the t8132 fallbacks and the AIC uses the t6050 entry. Implementer: check how the chain passes `--dtb dtb2` to kexec. w1c logs the DT evidence, so the next run settles it.
- **Likely W1 failure cause:** in the live DT the apcie domains exist with no consumers. genpd turned the unused ones off at about 2.7 s: W1B shows `apcie_gp/sys_gp/phy_sw/st0/st1/sys_st0/sys_st1 SKIP(ro) set val=0x0`. With W1's allow-list those writes REALLY happened for apcie_gp, apcie_sys_gp and apcie_phy_sw. APCIE_PHY_SW is shared with the storage side, so turning it off is a plausible way to lose NVMe and the ESP. **Rule from now on: never allow-list apcie_* while genpd can power them off unused.**
