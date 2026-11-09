# W2: w1c (our DTB, read-only node, allow-list ans only) + module power check fixed + the first port-0 writes. Not booted.
- PMGR check (pmgr-pwrstate.c: AUTO_ENABLE = BIT(28), ACTUAL 7:4, TARGET 3:0): a domain with target f + AUTO_ENABLE counts as on, the same rule as aurora apple_pmgr_ps_is_active(). W1c SYS_GP/SYS_ST*/APHY_*_AUS5 = 0x1000030f and PHY_SW 0x1400024f are on-demand, not off. No PMGR writes at all.
- Stages (ESP save before each): pmgr, power (check only), rc (read), phy (ONE RMW: port-0 lane reg[2]+0x10000 bit 28), corerun (NO write if CORE_RC_CTL.RUN is already set; the core is shared with storage), rc, enable (port0 regs only: reset table, RID2SID/MSIMAP, config tunables, APPCLK, port PERST handshake), config (port-0 root port config space, Gen1 x1), rc.
- No train: PERST# (GPIO 80) needs pinctrl_ap in the DT, which is the next set (W3). No SYS_ST*/PHY_SW/ANS writes anywhere.

## W2b (after the W2 SError at pll@reg2 0x417180838 with APCIE_PHY_SW actual 4)
- rc reads the PLL/AUSPMA blocks only if APCIE_PHY_SW (+0x1b0) reads actual f; otherwise it logs the skip. It still reads the core RC, port0, the PHY lanes 0x41701x000 and 0x417020000, INTR2AXI (all read fine in W2).
- corerun: no write if CORE_RC_CTL.RUN OR CORE_RC_STAT.READY (W2: CTL 0, STAT 1, storage running).
- Same stages otherwise: pmgr power rc phy corerun rc enable config rc.

## W2c (W2b died ~0.03 s into the rc after the phy write; phy wrote 0x417010000 0x33000070 -> 0x23000070, bit 28 cleared)
- Stages: pmgr power rc phy, then ONE read per step via run=rd:<addr> (only inside windows proven readable before the write), ESP save before and after each. Order: core RC CTL/STAT, port0 STATUS/LINKSTS/LTSSMCTL/APPCLK/PERST/0xa8/0x820, INTR2AXI, PHY lanes 1-3, 0x417020000, lane 0 (the written one), root-port ECAM id last. No enable/config.
- The last saved "stage rd:<addr>" line without its rc= line names the killing read.

## W3: port-0 enable/config, small stages
- The W2c phy-lane write is NOT repeated (lane 0 bit 28 stays as iBoot left it).
- W2b vs W2c: W2b second rc read 3 things W2c never read after the write: pmgr +0x1b0, ECAM 0x1cb0000018 (RP buses) and ECAM 0x1cb0000728 (LTSSM). Its rc ran ~0.06 s after the write, W2c seconds later with flushes. W3 reads 0x18/0x728 first, one per step, to settle it.
- Then: corerun (no write: core shared/READY), en1 (port reset table), en2 (RID2SID/MSIMAP clear, late table, config tunables), enable (APPCLK, PERST handshake, PORT_STATUS.READY, CGDIS), config (only if the RP config space answers: rc + shadow tunables, Gen1 x1), with single reads in between. ESP save before and after each step.
- No train: PERST# via GPIO 80 needs pinctrl_ap in the DT (W4).

## W4 = W3 + AP pinctrl (pin 80 only) + PERST# release + Gen1 x1 training
- dtb: w1b + pinctrl_ap okay with gpio-reserved-ranges <0 80>, <81 140> (aurora J716c) + m5-n1-w1 reset-gpios = <&pinctrl_ap 80 GPIO_ACTIVE_LOW>. Still no power-domains on the node, pcie0/N1/dart_apcie0 disabled.
- After config: train = lane refclk0/1 req+ack, lane clock bits, PERST# released (GPIO 80), LTSSM start, LINKSTS + LTSSM logged every 50 ms for 1 s; on link up: RP buses 0/1/1, endpoint 01:00.0-2 vendor:device (expect 106b:1901/1902/1903). Then perst re-asserts. No firmware.
- train runs only if config succeeded (the RP config space answered). LTSSM stuck in Detect (0x00/0x01) = nothing on the lane = N1 still in SMC reset (gP13, PM decision).

## W5 = W4 + the port-0 PHY lane tunable before `enable` + diagnostics on the 0xa8 timeout. Not booted.
- **W4 (native-w4.txt:1534-1541):** APPCLK_EN and PERST_OFF were written and read back fine. Then 0x4100280a8 bit 0 never acked within 20 ms (0x00000000).
- **What 0xa8 waits on (code reading, HYPOTHESIS):** in aurora's sequences (pcie-apple.c `apple_pcie_t6050_port_disable/enable`), 0xa8 is the port's own PERST/clock handshake. Bit 0 acks PERST_OFF, bit 16 acks the assert, before any refclk request or endpoint activity.
  - **Not refclk/CLKREQ:** aurora's `port_disable` drops the refclk requests and `port_enable` still expects the ack before `train` requests them again.
  - **Not the N1 / gP13:** the endpoint is not involved before the LTSSM starts.
  - **That leaves the PHY side.** Aurora runs this only on a port whose PHY the loader already brought up.
  - Our port-0 lane: PHY_LANE_CFG = 0x33000070, bit 28 set. The ADT `apcie-phy-tunables` entry for port 0 (reg[2]+0x10000) wants bit 28 = 0.
  - APCIE_PHY_SW reads clock-gated (actual 4, auto).
- **W5 fix tried:** the `phy` stage (ONE RMW: 0x417010000 bit 28 clear, as in W2c, where every read after it survived) is placed after en1/en2 and before `enable`. Then single reads of the lane, PORT_STATUS and 0xa8 (ESP save each), then enable/config/train as in W4.
- **If 0xa8 still times out:** `enable` now logs the lane, PORT_STATUS/LINKSTS/APPCLK and the PMGR PHY_SW/APHY_GP_AUS5(_A)/APCIE_SYS_GP states.
  - The next suspect is the shared PHY/PLL (PHY_SW clock-gated). Bringing it to actual f is a PMGR write on a domain shared with storage, so it needs the PM's approval.
- **gP13: not used in W5.** It acts on the N1 (radio power/reset, same form as aurora gpio-macsmc.c:38-43 J713 reg_on). The 0xa8 ack happens inside the host port before the endpoint matters.
  - Writing it would also need the SMC (macsmc + its mailbox + RTKit) enabled in our DT/config, which is a separate set.
  - It becomes the fix once the port enables and `train` stays in Detect (LTSSM 0x00/0x01).
