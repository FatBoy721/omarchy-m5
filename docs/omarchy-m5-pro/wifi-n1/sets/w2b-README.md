# W2: w1c (our DTB, read-only node, allow-list ans only) + module power check fixed + the first port-0 writes. Not booted.
- PMGR check (pmgr-pwrstate.c: AUTO_ENABLE = BIT(28), ACTUAL 7:4, TARGET 3:0): a domain with target f + AUTO_ENABLE counts as on, the same rule as aurora apple_pmgr_ps_is_active(). W1c SYS_GP/SYS_ST*/APHY_*_AUS5 = 0x1000030f and PHY_SW 0x1400024f are on-demand, not off. No PMGR writes at all.
- Stages (ESP save before each): pmgr, power (check only), rc (read), phy (ONE RMW: port-0 lane reg[2]+0x10000 bit 28), corerun (NO write if CORE_RC_CTL.RUN is already set; the core is shared with storage), rc, enable (port0 regs only: reset table, RID2SID/MSIMAP, config tunables, APPCLK, port PERST handshake), config (port-0 root port config space, Gen1 x1), rc.
- No train: PERST# (GPIO 80) needs pinctrl_ap in the DT, which is the next set (W3). No SYS_ST*/PHY_SW/ANS writes anywhere.

## W2b (after the W2 SError at pll@reg2 0x417180838 with APCIE_PHY_SW actual 4)
- rc reads the PLL/AUSPMA blocks only if APCIE_PHY_SW (+0x1b0) reads actual f; otherwise it logs the skip. It still reads the core RC, port0, the PHY lanes 0x41701x000 and 0x417020000, INTR2AXI (all read fine in W2).
- corerun: no write if CORE_RC_CTL.RUN OR CORE_RC_STAT.READY (W2: CTL 0, STAT 1, storage running).
- Same stages otherwise: pmgr power rc phy corerun rc enable config rc.
