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

## W6: diagnostic set. Not booted.
**W5 evidence (native-w5.txt):**
- APCIE_PHY_SW flips between 0x1f0002ff (actual f) and 0x1400024f (actual 4) between two reads 0.08 s apart (lines 1375/1399). It is auto-power-managed: storage traffic wakes it, then it gates again.
- At the 0xa8 timeout it read actual f, yet there was still no ack.

**Comparison with aurora's T6050 port bring-up (pcie-apple.c de86c93b/94e4ebf6):**
- Aurora's enable runs only on a port that is in this state:
  - the loader powered and trained it;
  - the PHY/PLL is up;
  - the lane refclk was used before.
- Its `train` requests refclk only AFTER enable, so refclk/CLKREQ are not prerequisites of the 0xa8 ack in aurora's own order.
- Aurora has no PHY/PLL init code at all.
- The N1 (gP13, CLKREQ# on AP pin 76) only matters from LTSSM start on.
- So the evidence points at the host PHY/PLL (never initialised by us; the shared PHY clock auto-gates), not at N1 power. HYPOTHESIS.

**W6 does:**
- The W5 path: the port-0 lane write, then enable.
- On the 0xa8 timeout: watch 0xa8/STATUS/LINKSTS/PERST/lane every 100 ms for 1 s (a late ack would show), a PMGR snapshot, then watch again.
- If enable succeeds: config + train, as in W4/W5.

**Safety change:** the module NEVER reads the PLL/AUSPMA blocks now. Its old "read only if PHY_SW actual f" check races the auto-gating, the same pattern as the W2 SError.

**Not in W6, because each needs a decision or a bigger set:**
- **(a) Hold APCIE_PHY_SW on.** A PMGR write: target f, AUTO_ENABLE cleared. It only adds power to a domain the storage also uses, but your rules forbid writes to it.
- **(b) The PLL/AUSPMA tunables.** Writes into the gated PHY block; this needs (a) first.
- **(c) gP13 (approved).** There is no T6050 SMC binding in this tree: `drivers/mfd/macsmc.c` matches only `apple,t8103-smc`/`apple,smc`, and aurora's `t6050-die0.dtsi` smc node is `apple,t6050-smc` with no fallback. It needs MFD_MACSMC + the smc mailbox + an `apple,smc` fallback in our DT, and a module stage doing `apple_smc_write_u32('gP13', 0x00800001)` directly. Note: the generic macsmc-gpio set path would write CMD_OUTPUT|level = 0x01000001, not the 0x00800000-template value. SMC RTKit has never run under m5-n1.

## W7 (PM-approved (a)+(b)). Not booted.

**(a) `physw`: one direct MMIO write to APCIE_PHY_SW (0x2809001b0).** It does not go through genpd or the allow-list (still `ans` only).
- new = (old & ~(AUTO_ENABLE bit 28 | WAS_* bits 9:8 | TARGET 3:0)) | 0xf. TARGET f, AUTO_ENABLE off. The write-1-clear flags are written as 0. RESET (bit 31), DEV_DISABLE (bit 10) and all other bits are written back as read.
- It polls ACTUAL == f (100 ms) and never lowers the domain.
- No DT node references PHY_SW in this dtb, so genpd can never switch it off. `pd_ignore_unused` is kept. The domain stays on until reboot.

**(b) PLL/AUSPMA tunables, from the ADT, at reg[4] 0x417800000.**
- Why reg[4] and not reg[2]: the auspma list ends at +0x1b04a4, just inside reg[4]'s size 0x1b4000. reg[2] is 8 MiB, which gives no such fit. W2's SError was a read at reg[2]+0x180838 while PHY_SW was gated.
- **Scope:** the shared PLL (+0x180000..+0x183fff, 19 entries) and port 0's AUSPMA block only (+0x184000..+0x18ffff, 26 entries). The three other 0xc000-strided blocks (ports 1-3: SD reader and storage) are never touched.
- **Every access is checked:** the module refuses unless PHY_SW reads target f + actual f + AUTO_ENABLE off.
- **Order:**
  1. `tuncmp`: read-only compare; logs how many entries already MATCH.
  2. `tw:p:0..18`, then the 26 `tw:a:<i>` steps. ONE entry per step, written only if it differs. ESP save before and after each step.
  3. `tuncmp` again.
- **HYPOTHESIS:** the PLL may be shared with storage. If storage uses it, its entries should already MATCH and are skipped.

**Then:** the port-0 lane write (`phy`), then enable. If enable fails: ackwait + pmgr. If it succeeds: config → train (PERST# GPIO 80, Gen1 x1, LTSSM/LINKSTS every 50 ms), then the endpoint IDs. PHY_SW is left on.

## W8: SMC binding + gP13 (PM-approved) + CLKREQ#/early refclk. Not booted.

**W7 evidence (native-w7.txt):**
- Before any write, 44/45 of the PLL + port-0 AUSPMA entries at reg[4] already held the ADT values. iBoot had configured the PHY/PLL, which confirms the reg[4] base.
- W7 wrote one entry: 0x4179820a4, 0x66120280 -> 0x65110280. Storage survived it.
- So the missing 0xa8 ack is not PHY/PLL setup, which leaves the N1 side.

**SMC:**
- **DT:** `smc` gets an `apple,smc` fallback (drivers/mfd/macsmc.c matches only t8103-smc/apple,smc) and `smc_mbox` is enabled. All SMC children stay disabled: hwmon, reboot, pcIO gpio, rtc.
- **Modules:** macsmc.ko + mfd-core.ko (MFD_MACSMC=m, same source/vermagic; every symbol they import is exported by this kernel, Module.symvers checked; no MODVERSIONS). They are insmod'ed by the runner before m5_n1, with an ESP save before and after each.
- **Probe:** RTKit wake of the already-running SMC, then the NTAP flag write, as every Asahi kernel does. On shutdown/kexec the driver quiesces the SMC's RTKit; a watchdog reset skips that.
- **Image:** a2's, unchanged.

**Stages, ESP save before and after each:**
1. corerun, en1, en2, physw (PHY_SW held on), pmgr, tuncmp (read only).
2. `smc`: read gP13.
3. `clkreq`: CLKREQ# level on AP pin 76 (ADT function-clkreq). The DT now exposes pins 76 and 80 only.
4. `gp13`: SMC write gP13 := 0x00800001, read it back, wait 100 ms.
5. `clkreq`, then `smc` again.
6. `phy`: port-0 lane bit 28.
7. `refreq`: lane REFCLK0/1 request + ACK poll BEFORE enable. In aurora this happens only in train.
8. enable. On failure: ackwait + pmgr. On success: config, then train (PERST# release, Gen1 x1, LTSSM/LINKSTS polled), then the endpoint IDs.

**What to read in the log:**
- **gP13:** the value before and after the write.
- **CLKREQ#:** whether it goes asserted after gP13. A powered N1 should pull it low.
- **REFCLK ACKs:** whether they arrive.
- **0xa8:** whether it now acks.

## W8b: W8 with only the SMC linkage fixed
- W8: symbol_get(apple_smc_read) was refused ("failing symbol_get of non-GPLONLY symbol"), so gp13 never ran. m5_n1 now calls apple_smc_read/apple_smc_write directly, built against macsmc exports (modinfo depends: macsmc). The runner already loads mfd-core, then macsmc, then m5_n1.

## W9: W8b + three orderings for the 0xa8 ack (ESP save before and after each step)
- **(1) perstrel:** PERST# GPIO 80 released BEFORE enable. Aurora keeps it asserted until train.
- **(2) enablelong:** aurora's enable with a 500 ms 0xa8 wait. Aurora uses 20 ms (`apple_pcie_t6050_port_enable`).
- **(3) asahien, if both fail:** the AsahiLinux t8103/t602x order, from our asahi-wip-7.2 `pcie-apple.c` (`setup_link`/`setup_refclk`). It has NO 0xa8 handshake:
  1. APPCLK_EN.
  2. refclk req/ack.
  3. REFCLKEN (lane bits 9/10).
  4. PERST_OFF and the GPIO deassert together.
  5. Wait 100 ms, then PORT_STATUS.READY (250 ms). 0xa8 is only logged.
  - Then `enfinish`, aurora's enable tail: PERST bit 16 clear, READY, CGDIS, LINKSTS !BUSY.
- **If the port enables either way:** config, then train (Gen1 x1, LTSSM/LINKSTS), then the endpoint IDs.
- **gP13 read back as 0 after a successful write (W8b).** HYPOTHESIS: a write-only, command-style key. Aurora's macsmc-gpio J713 path keeps its own level cache and never reads the key back. CLKREQ# going 0 -> 1 is the evidence that the write took effect.

## W10: the Asahi order end to end (no aurora 0xa8/BUSY waits)
- **What Asahi does after setup_link's PORT_STATUS.READY.** Our asahi-wip-7.2 `drivers/pci/controller/pcie-apple.c`, `apple_pcie_setup_port()`, t602x path with port_refclk = 0:
  1. Lane REFCLKCGEN (PHY_LANE_CFG bits 30/31) set.
  2. PORT_APPCLK_CGDIS cleared.
  3. Port IRQs, RID2SID reset.
  4. `writel(PORT_LTSSMCTL_START, PORT_LTSSMCTL)`, then wait for the link-up IRQ (link_up_timeout).
- **PORT_LINKSTS_BUSY is defined there but never polled.** The BUSY wait (and the 0xa8 handshake) exist only in aurora's T6050 restart path. In W9, LINKSTS read 0xc3002204 with BUSY set while the link was down. HYPOTHESIS: BUSY clears only once the link trains.
- **Asahi applies no root-port tunables in Linux** (m1n1 does). W10 still tries `config` (root-port tunables, Gen1 x1), which refuses by itself if the RP config space reads 0xffffffff.
- **Runner, ESP save before and after each step:**
  1. The W8b prefix (PHY_SW hold, SMC gP13 := 0x00800001, CLKREQ#, lane bit 28, early refclk).
  2. asahien (READY in W9), single reads, config.
  3. `asahitrain`: REFCLKCGEN, CGDIS clear, LTSSM start, LINKSTS/LTSSMCTL/STATUS (+ RP LTSSM if the RP answers) every 50 ms for 2 s.
  4. On link up: RP buses 0/1/1 and the 01:00.0-2 vendor:device. Then the final reads, pmgr, perst.

## W11: N1 power/reset/train trials (W10: RP answers 106b:100c, LTSSM stays 0x00 Detect for 2 s)
**Checked before choosing the trials:**
- **(a) PERST# pin and polarity.** ADT pci-bridge0 `function-perst` = <AP gpio 0x50 (80), flags 0>. Aurora J716c: `reset-gpios = <&pinctrl_ap 80 GPIO_ACTIVE_LOW>`, driven `gpiod_direction_output(perst, asserted)`. That is the same pin and polarity as ours, so there is no T6050 difference. W11 still tries the opposite raw level.
- **(b) Delays.** The Asahi setup_link waits 100 ms after pwren (T_PVPERL) and after PERST# release. W11 waits 300 ms after gP13 and 200 ms after PERST#.
- **(c) gP13 encoding.** The ADT value is `function-reset` = pKW4('gP13', 0x00800000). Aurora's macsmc-gpio J713 path writes 0x00800000|level. Asahi DTs power PCIe devices with `pwren-gpios = <&smc_gpio N ...>`, which goes through the generic macsmc-gpio set, i.e. CMD_OUTPUT|level = 0x01000001. The ADT names this function "reset", not power, so level 1 may mean "reset asserted". W11 tries both levels and both encodings.
- **No second N1 key in our ADT.** pci-bridge0 has only `function-reset` (gP13), `function-warm_reset` (pKW4 key 0x62706c69, arg 1, not used), `function-clkreq` (AP pin 76), `function-perst` (AP pin 80) and `function-pcie_port_control` (<0x8b 'PtrC' 0x8c>: a PMGR-device function, not used).
- **(d) Refclk.** In W8b+ the lane REFCLK0/1 ACKs arrive and CLKREQ# is asserted. W11 adds Asahi's REFCLKCGEN and APPCLK_CGDIS clear (`asahiprep`) before training.

**Runner:**
1. The W8b prefix.
2. asahien (READY), RP id, config, asahiprep.
3. Trials in order, stopping at the first link up:
   - gP13 = 0x00800001 / 0x00800000 / 0x01000001;
   - PERST# logical 0 (the DT deassert) and 1 (the opposite raw level) for each.
4. Each trial:
   1. PERST# asserted, LTSSM stopped.
   2. gP13 written, then read back.
   3. 300 ms, then CLKREQ# read.
   4. PERST# set.
   5. 200 ms, then LTSSM start.
   6. LINKSTS/STATUS/RP LTSSM polled every 50 ms for 1.5 s.
   - On link up: the endpoint IDs.
- ESP save before and after every trial. The final gP13 value persists until reboot (volatile).

## W12: diagnostics around one training start (W11: gP13 level 1 -> CLKREQ# asserted, yet LTSSM 0x00 in all 6 trials)
- **Where "LTSSM 0x00" comes from:** root port config 0x728 bits 5:0. This is aurora's `RC_T6050_PORT_DEBUG0`/`RC_T6050_LTSSM_STATE`, the DesignWare port logic register, which aurora itself polls for L1 idle. W12 also logs DEBUG1 (0x72c), the LTSSMCTL readback and the PCIe LNKSTA.
- **Sequence:** the W8b prefix, asahien, config, asahiprep, gp13 (0x00800001), clkreq; then dumps, tuncmp, `ltssmgo`, the same dumps again, tuncmp, pmgr.
  - `dumprp`: RP config 0x000-0x0ff, DW port logic 0x700-0x73f, 0x800-0x82f, 0x880-0x8bf. Decoded: LNKCAP, LNKCTL (Link Disable bit 4, Retrain bit 5), LNKSTA (speed, width, training, DLL active), LNKCAP2/LNKCTL2, DEBUG0/1.
  - `dumpport`: port0 0x000-0x2ff and 0x800-0x8ff, lane 0x00-0x3f, INTR2AXI 0x00-0xff.
  - `ltssmgo`: PERST# deassert, 200 ms, LTSSMCTL := 1 (readback logged), then LTSSMCTL/LINKSTS/DEBUG0/DEBUG1/lane every 50 ms for 1 s.
- **RISK:** the dumps read port/lane/INTR2AXI offsets never read before. If one of them faults, the ESP log ends at that `stage dump*` line.
- **Not available:** aurora has no register for the PHY lane's receiver-detect status. Its T6050 lane decode stops at PHY_LANE_CFG bits 0-4/9/10/30/31, so W12 only dumps raw lane words.
