# Task 02 — Read-only J714s hardware dump + contribution-policy check

Two parts. Output: `tools/dump-j714s.sh` (for the PM to review and run) and `reports/02-dump-and-policy.md`.

## Part A — write the dump script (don't run it on the MacBook yourself)
Write `tools/dump-j714s.sh`: a macOS bash script, **read-only, no sudo**, that prints to stdout everything step 1 of your ladder needs: chip-id, board-id, CPU clusters/cores, UART, iBoot/firmware versions, `wlan-pcie` compatible (N1 vs Broadcom), and every device-tree compatible string (so we can diff against what m1n1/Linux know). Use `ioreg -p IODeviceTree -l` and anything else that's read-only (`system_profiler`, `sysctl`, `bputil -d` only if it works without sudo — otherwise skip it and say so).
**Scrub before printing:** serial numbers, MAC addresses, UUIDs, nonces, ECIDs, IOPlatformUUID, Wi-Fi/BT addresses — replace with `<scrubbed>`. Keep it short and commented. The PM will review the script, run it on the MacBook from another machine, and drop the output at `reports/02-j714s-dump.txt`. When the script is ready, end with `READY 02A` (not DONE) and wait.

## Part B — while waiting, research (no MacBook needed)
1. Do **omacom/Omarchy** and **Aurora Silicon** have rules about AI/LLM-assisted contributions? Quote them with links. If none, say so.
2. Aurora discussion #142 and anything else: has anyone posted a J714s (or any T6050) boot log, m1n1 output, or test result? Who has an M5 Pro machine?
3. Which machine should run m1n1's proxyclient? It must be physically cabled to the MacBook over USB-C. ush is being sold soon. List exactly what proxyclient needs (Python version, packages, USB permissions/udev) so we can set it up on whatever machine ends up next to the MacBook.

## Part C — after the PM drops `reports/02-j714s-dump.txt`
Analyze it: confirm chip T6050 or not, clusters, UART, N1 vs Broadcom Wi-Fi, and the list of compatibles that neither upstream m1n1 nor any public kernel tree knows (that's our work list). Write `reports/02-dump-and-policy.md` with Parts B and C. End with `DONE 02`.
