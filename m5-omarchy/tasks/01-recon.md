# Task 01 — Recon: where exactly does M5 support stand?

Research only. Don't touch the MacBook. Output: `reports/01-recon.md`.

Starting leads (verify each, go deeper):
- m1n1: commit b2d3f5eb "Initial support for T6050/T6051" (yuyuyureka), PR #578 (M5 pmgr, device-mode USB on M5 Max MBP), PRs #698 #737 #738 #740 #741 #754 merged, **#758 "M5 hypervisor" open** (svenpeter42).
- Reports that Asahi has NVMe working on M4 and early M5 (MacGeneration, Aug 2026).
- Omarchy side: omarchy-mac (malik-na, Codeberg/GitHub), "Aurora Silicon" kernel builds, maralcbr/omarchy-m-testing (catalogue covers M1–M4 + A18 Pro, not M5).

Answer, with sources:
1. **m1n1 on M5 today:** what works (chickens/SMP, pmgr, USB device mode, hypervisor?), what's in open PRs, which M5 machines devs are using. Is J714s / T6050 vs T6051 mentioned anywhere? Which chip is M5 Pro?
2. **Linux kernel on M5:** any branches/patches (AsahiLinux/linux, svenpeter42, yuyuyureka, mailing lists) with T605x device trees or drivers. What boots, to what point.
3. **How devs boot m1n1 on an M5 today** when the Asahi installer doesn't offer it: exact path (installer expert/dev mode? manual stub OS + `kmutil configure-boot`?), what security setting it needs, what's needed on the second machine (proxyclient over USB-C), and recovery if it goes wrong (DFU restore needs another Mac — we have one on Tailscale: another Mac (a second machine)).
4. **M4 learnings that carry over** (SPTM, GPU generation changes, Sven's "M4 will be painful" points). What's the GPU situation for M3/M4/M5 (AGX generation, driver status)?
5. **Omarchy layer:** how omarchy-mac / Aurora Silicon package kernels + m1n1, which repos, who maintains, how a new chip gets added.
6. **Where to coordinate:** Asahi dev channels (IRC/Matrix), etiquette for reporting tests on new hardware.
7. **Proposed ladder for J714s:** concrete first 3 experiments we could run, each with what it needs and how risky it is.

Keep the report under ~2 pages. Mark guesses as guesses.
