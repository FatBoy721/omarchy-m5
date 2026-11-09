# Task 04 — Full read-only dump + PMP vs MTP static diff (no hardware changes)

Outputs: fixed `tools/dump-j714s.sh` (stop at `READY 04A` for PM review/run), then `reports/04-pmp-vs-mtp.md`.

## Part A — fix + extend the dump script
- Fix the `-n` node lookup bug (find nodes by `+-o name@` in the full tree).
- Add: `--full` scrubbed ADT; IOService plane for `pmp0`, `mtp`, `pmgr`, `gfx`/`agx`, and the cpus (class names, driver bundle names, matched properties) — read-only `ioreg -p IOService`.
- Keep it no-sudo, read-only, scrubbed. Put the full ADT in a separate output section so it can be saved as its own file.
- Print a short summary of what got scrubbed (count per key) so the PM can verify scrubbing worked.
End with `READY 04A` and wait. The PM drops output at `reports/04-j714s-full.txt`.

## Part B — after the output lands
1. `pmp0` vs `mtp` (both ascwrap-v6 / rtbuddy-v2): every reg entry, wrapper props, DART/mapper, power domain, nub props. Where would `ASC_CPU_CONTROL` live for each? Does the `+0x44` fault look like a wrong-address problem?
2. `pmgr`: is `function-pmp_control` absent (vs T8142)? List PMGR domains with `notify_pmp`.
3. IOService: which macOS classes/drivers bind to pmp0, mtp, gfx, cpus. Just names — no binary analysis.
4. Concrete proposal for ladder step 2 probes (single 32-bit reads only), with exact addresses, in priority order.
End with `DONE 04`.
