# Task 05 — Repo audit, open questions, build the J714s kernel (no MacBook)

Rule 7 was narrowed (re-read CLAUDE.md): the only known restriction is upstream AsahiLinux/m1n1's own instruction. Everything else follows each repo's own instructions + license. Don't touch the MacBook. Output: `reports/05-audit-and-build.md`.

## A. Repo audit (do this first, and obey what you find)
For each repo we might use, record license + any CLAUDE.md/AGENTS.md/GEMINI.md text (check via `gh api repos/<r>/contents/<file>?ref=<branch>` before cloning): aurora-silicon/aura (+ its m1n1 fork if separate), edimoldovan/m1n1 @ t6050-aurora, edimoldovan/linux-aurora @ t6050-j714c, omacom/linux-aurora, betizzel/omarchy-m5, AsahiLinux/linux @ asahi-wip-7.2, omacom/omarchy-mac-*. If a fork still carries upstream m1n1's notice on the branch we'd use, treat that repo as owner-only too. Table: repo | branch | license | AI instructions | our use allowed?

## B. Open questions from report 04
Answer Q1 (notify_pmp domain list incl. devices 0x1b/0x1c) and Q2 (PTD offsets / PMP-STATUS) using only repos whose own instructions allow AI use. Add the results to report 04's findings in report 05 (don't edit 04's provenance line).

## C. Build (on ush, user-level only, under `build/`)
1. Kernel: AsahiLinux/linux `asahi-wip-7.2` @ 236788cd + betizzel's 9 patches + the J714s DT, per recipe 03A. Produce Image + DTB, record SHA-256 and exact commands in `tools/build-kernel.sh` so it's reproducible. If a needed toolchain isn't installable user-level (rustup, clang cross), end with `BLOCKED 05: <exact packages>`.
2. Bootloader: if an audited repo whose instructions allow AI provides a T6050-capable m1n1 build (e.g. a fork), build it the same way. Otherwise list the upstream-m1n1 build as an owner step with exact commands.

## D. Report
What's built and ready, what's an owner step (with exact commands), and what's left before the first tethered boot. End with `DONE 05`.
