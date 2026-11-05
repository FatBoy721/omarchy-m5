# Task 03 — Reproduction recipe + PMP deep dive (no hardware)

No MacBook access needed. Outputs: `reports/03-repro-recipe.md`, `reports/03-pmp.md`. Clone upstream code into `src/` (gitignored is fine), don't push anywhere, don't post anywhere.

## Part A — exact recipe to reproduce single-core boot on our J714s
Study betizzel/omarchy-m5 (incl. FOR-AURORA.md), edimoldovan's `linux-aurora:t6050-j714c` + `m1n1:t6050-aurora` branches, and #293.
Write a step-by-step recipe that the owner + PM can follow later, split into:
1. Host side (the machine cabled to the MacBook): packages, m1n1 build (which repo/branch/commit), proxyclient setup.
2. MacBook side, by hand: stub OS creation, 1TR steps, `bputil`/`kmutil` commands, in order, with what each screen looks like where possible. Mark every step that changes the MacBook's boot/security setup.
3. Kernel + DT: which tree/branch/commit, the J714s DT (betizzel's? derived from J714c?), config, how to build, how to load tethered (`linux.py` / chainload).
4. Expected result at each step and how to tell it worked. Known failure modes.
5. Rollback: how to remove the stub and return the Mac to stock.
Pin exact commit SHAs. Flag anything where betizzel and edimoldovan disagree.

## Part B — PMP on T6050
Everything public about PMP (the coprocessor that gates SMP and the GPU `cs` power domain):
- What it is (ASC wrapper v6, RTKit?), where it sits in the ADT (`pmp0`, `ptd-range`, etc.), which firmware it runs and where that firmware comes from (iBoot-loaded? in the macOS firmware bundle?).
- What macOS does to start it and talk to it (driver names in the kernelcache, e.g. AppleT6050PMP or similar; known messages/endpoints). Only use public sources and our own scrubbed dump; no proprietary code.
- What edimoldovan/birkskyum/others already tried and where they're stuck. Why base M5 (T8142) doesn't hit this wall.
- How the M1–M4 PMP (if any) worked under Asahi, for comparison.
- Candidate approaches to start PMP from m1n1 or Linux, ranked by feasibility, and which need hypervisor tracing of macOS (note: that tracing must be done by the owner, human-driven, if results are ever meant for Asahi).
End with `DONE 03`.
