# 46: u2c NATIVE, and u3, a one-domain-at-a-time ATC0 power-on

## u2c (NATIVE, `reports/native-u2c.txt`, 07:20): the first correct rev 2 run
- **It was the right set:** kernel 7.2.2-m5slim+, marker USB-U2.
- **op=state matched u0:** atc0_common 0x300 (actual 0), usb_aon 0x2ff (f), usb 0x244 (4), phymxwrap 0x300 (0).
- **The log ends at `insmod m5_usb op=dt_power`,** then WD1 reset the Mac to macOS. Applying the changeset made the kernel pwrstate driver probe the four nodes and genpd power them through the allow-list. Something in that path killed the SoC.
- **What it can't show:** which write it was. One insmod covers every probe and the auto/target writes.
- **Candidates (HYPOTHESIS):**
  - ATC0_COMMON is PMP-notified: its pmgr `devices` flags are 0x2, unlike the 0x0 of USB/PHYMXWRAP. betizzel says m1n1 powers it without PMP (REPORTED).
  - Write order.
  - The pwrstate probe's AUTO_ENABLE write on a gated domain. betizzel saw a pwrstate write to an auto-gated domain never complete, and m1n1 clears AUTO_ENABLE first.

## u3 (built): one PMGR write per insmod, ESP log saved before each
- **New module ops in `m5_usb`** (sha256 `73cff5adf0e29433…`, vermagic 7.2.2-m5slim+):
  - **`op=pon dom=<atc0_common|atc0_usb|atc0_phymxwrap|atc0_usb_aon> step=auto`:** clears AUTO_ENABLE (bit 28). It never writes the W1C flags (bits 9:8), and reads back.
  - **`step=target`:** sets target := 0xf (with AUTO and the flags clear), then polls actual every 500 µs for up to 10 ms, logging each sample.
  - **What these touch:** exactly these four PMGR words, written directly. This is PM-authorized (task 46). The kernel pwrstate driver is not involved: the ps_atc0 nodes stay disabled, and the cmdline allow-list is back to `ans` only.
  - **`op=dt_nopd`:** dwc3_0 and both its DARTs go to status okay with **power-domains removed**, because power is done by op=pon. If the notifier creates no device, it creates one directly.
- **Script order:**
  1. Guard (uname 7.2.2-m5slim+ and marker `USB-U3`, else log and stop).
  2. `op=state` (shows usb_aon already f: the no-op check).
  3. For each of atc0_common, atc0_usb and atc0_phymxwrap: `auto`, `target`, then a dmesg check for `actual f`.
     - If a domain doesn't reach f, it logs `STOP`, runs one last state, and stops, so no child is powered over a dead parent.
  4. `op=state` (it also dumps the PHY and PIPE registers once all four main domains are on), `op=dev`, `op=dt_nopd`.
  5. Log the driver links, then bind dwc3 if it's still unbound.
  6. The NCM/ECM gadget, 10.55.0.1, sshd, and 10 minutes of state logging, as in u2.
- **If it hangs,** the last ESP line is `insmod m5_usb op=pon dom=X step=Y`, which names the exact write.

## Push
- **m5next/** = `build/usb-v1/m5next-u3/`: Image `6ca1319373f9…` (usb-v1), initrd `1a459b5b…`, cmdline `0f5f3641…` (`m5_pmgr_allow=ans`, `m5.testmarker=USB-U3`, autoreboot 900).
- **m5drop/** = `loop/u3/m5drop/`.
