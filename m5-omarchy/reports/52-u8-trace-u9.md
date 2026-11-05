# 52 — u8 trace: where SET_CONFIGURATION stalls; u9

**Bottom line (NATIVE, `reports/native-u8-trace.txt`):**
- **What works:** the SETUP stage of SET_CONFIGURATION, all of the device-side config work, and the start of the status stage.
- **Where it stalls:** the status-stage zero-length IN packet on **ep0in** is armed, and the controller accepts the command (`Start Transfer` → Successful), but it **never completes**. There is no Transfer Complete event for 126 s, until the host's re-authorize ends the transfer.
- **What is different from the status stages that worked:** after SET_CONFIGURATION, the ECM notify endpoint **ep2in** (interrupt, TxFIFO 2) has an 8-byte notification TRB already handed to the hardware, **before** the ep0in status. Neither SET_ADDRESS nor any other status stage before it had another IN endpoint with queued data.

## The SET_CONFIGURATION transaction (trace lines 228–254, all at t = 29.2202x s)
1. `0000c040 ep0out Transfer Complete [Setup Phase]` → `Set Configuration(Config = 1)`.
2. `Start New Configuration` (DEPSTARTCFG, XferRscIdx 2) → Successful.
3. `usb_gadget_set_state` → 7 (CONFIGURED).
4. **ep2in** is set up:
   - `Set Endpoint Configuration` with params `00040086 0a080200`: interrupt endpoint, MPS 16, **TxFIFO 2**, physical ep 5 → Successful;
   - `Set Endpoint Transfer Resource` → Successful;
   - `Start Transfer` at `3fffffe4000` → Successful.
5. ECM queues its 8-byte notification on ep2in: `prepare_trb` with HWO set, then `Update Transfer` → Successful. The host isn't polling ep2 yet, so this data stays waiting in TxFIFO 2.
6. `ep0in Transfer Not Ready [Status Phase]`: the host's status IN token has arrived.
7. `prepare_trb ep0in` with a size-0 status2 TRB, then `Start Transfer` → **Successful**.
8. **No `ep0in Transfer Complete [Status Phase]` follows.** The next event is at 155.906 s: `End Transfer` on ep0in (from the host re-authorize), then `Set Stall`, then ep2in's request is given back with -108.

For comparison, the SET_ADDRESS status stage (lines 96–99) runs the same sequence on the same TRB address, with `ctrl 00000c33` and the same `ffff8000`, and completes in 15 µs.

- **No DART fault anywhere in `native-u8.txt`.** dwc3_1 is iommu group 1 in DMA (translated) mode. The ep0 TRB and buffer go through the same DART that already worked for every earlier stage. The DART is unlikely to be the cause, but u8p still checks it.

## What the controller is likely doing (HYPOTHESIS, ranked)
1. **The TxFIFO layout is broken.** ep2in's FIFO 2 overlaps FIFO 0 (ep0in), or a FIFO size is 0. Fetching the 8-byte notify into FIFO 2 then corrupts or blocks the ep0in zero-length packet. Linux never programs GTXFIFOSIZ (no `tx-fifo-resize`), so the layout is whatever the hardware defaults are after reset.
2. **The TxFIFO arbiter waits on the stale ep2 data.** The interrupt endpoint has data but the host doesn't poll it yet, so the controller won't serve ep0. This shouldn't happen on a correct dwc3, but it would also be fixed by not queueing until the host is configured.
3. **DMA through the DART.** No fault was seen; u8p tests this.

## u9 (built): split hypotheses 1–2 from 3
- **Push:**
  - m5next/ = `build/usb-v1/m5next-u9/`: Image `09ec53ef…` and initrd `6fe015a9…` (same as u8), cmdline `de239597…` with marker `USB-U9`.
  - m5drop/ = `loop/u9/m5drop/`.
  - Cable stays on the left-front port (Port-USB-C@2).
- **The gadget is ACM only.** f_acm enables its notify endpoint at SET_CONFIGURATION but **doesn't queue anything** until the host opens the tty. If SET_CONFIGURATION succeeds, the host sees `cdc_acm` / `/dev/ttyACM0`. That pins the fault on IN data queued on a second endpoint while the status stage is pending (hypothesis 1 or 2).
- **m5_usb dwc3dump now also reads** (read-only; module sha `1af63a82…`):
  - GHWPARAMS0–8;
  - GTXFIFOSIZ0–7 and GRXFIFOSIZ0–2;
  - the GDBG FIFO space, LTSSM, BMU, LSP and EPINFO registers;
  - GEVNTSIZ0 and GEVNTCOUNT0;
  - DEPCMD for ep1 and ep5.
  
  It runs before the function is linked, 5 s after the UDC binds, and at t+1m and t+2m. Reading the FIFO table directly tests hypothesis 1, by checking start address + depth for overlap.
- **Unchanged from u8:** the trace and dynamic debug, dartinfo, `m5_hpm op=auto usid=0xa`, ATC1 power-on and the dwc3 bind.

## Next (u10), depending on the u9 results
- **ACM works and FIFOs overlap or are 0:** u10 = ECM plus `tx-fifo-resize` in the live DT before the bind, so dwc3 programs GTXFIFOSIZ itself; or have m5_usb write a sane layout before the bind (needs approval: a dwc3 register write).
- **ACM works and FIFOs look sane:** u10 = ECM with the first notification deferred (a small kernel patch to f_ecm: queue the notify on the first host IN token) — or switch to RNDIS/NCM with the same change.
- **ACM fails too:** the problem isn't queued data. Run u8p (DART bypass), and next compare DEPCMD_1 and GDBGEPINFO in the dump.

Labels: trace sequence NATIVE; §"likely" HYPOTHESIS; u9 built, not run.
