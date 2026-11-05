# Task 26 — candidate FIXES for the ~45 s idle reset (build now, in parallel with the gz8 native run)

Facts: gz7 disabled every armed WDT in the main block and the Mac still reset at the same point (~45 s after initcalls, idle). So a plain WDT is unlikely. Prime suspects: a PMGR write (genpd power-off of "unused"/deferred domains, sync_state, deferred-probe timeout teardown) or a late driver touching PMP-owned hardware.

Build three slim-v3 variants (same DTB base, record hashes in ~/m5boot/spec/inputs.md § Slim v4):
- A: no PMGR power-state driver at all (CONFIG off or all apple,pmgr-pwrstate nodes disabled in DT; drop power-domains users). Zero PMGR writes from Linux.
- B: A's kernel + cmdline `fw_devlink=off deferred_probe_timeout=0` and nothing else changed.
- C: current v3 but disable every driver that probes after 30 s (list them from the gz6 initcall_debug/deferred lines) — your judgment.
VM-boot each to the shell. Report which you recommend first and why, in reports/26-reset-fixes.md. Print exactly `DONE 26` (or `BLOCKED 26: <q>`). No dialogs.
