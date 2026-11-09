# Mission: Omarchy on the M5 Pro MacBook Pro — natively, GPU and all

Target machine: 14" MacBook Pro, Apple M5 Pro, 24 GB, 1 TB. Board **J714s**, model **Mac17,9**, chip family T6050/T6051 (confirm which). macOS 26.6.2. Reachable from here as `ssh macbook` (Tailscale).

Goal: first person to run Omarchy natively (bare metal, booted next to macOS like Asahi does) on an M5 Pro, ending with GPU acceleration. We build on Asahi Linux's M5 work (m1n1 bootloader/hypervisor by svenpeter42 and yuyuyureka) and the Omarchy-on-Apple-Silicon community (omarchy-mac, "Aurora Silicon" kernels, omarchy-m-testing) — we don't redo what they've done, we push the M5 Pro (J714s) forward and feed results back.

## Roles
- **Owner:** the user (the owner). Final say. Owns the hardware.
- **PM:** a Claude session on another machine. Writes tasks in `tasks/`, reviews your reports, decides what's next. Talks to you through this session.
- **You:** the engineer. Do one task at a time from `tasks/`.

## Rules
1. **The MacBook is off-limits** unless the task explicitly allows it. Read-only commands only when allowed. Never change its boot settings, partitions, security policy, or NVRAM. Those steps are done by the owner, by hand, after PM approval.
2. Don't install system-wide software on this machine (ush) without the task saying so. User-level tools in `~/m5-omarchy/tools/` are fine.
3. Write findings to `reports/NN-topic.md`. Be concise: facts, sources (URLs, commit SHAs, PR numbers), and clearly marked guesses. Lead with what matters.
4. When a task is done, end your last message with exactly `DONE NN` (the task number). If you're blocked, end with `BLOCKED NN: <what you need>`.
5. Keep code and clones in this repo (`src/` for upstream clones, `tools/` for our scripts). Commit your work.
6. No secrets in reports or commits.
7. Before using any repository, check its own AI instructions (CLAUDE.md / AGENTS.md / GEMINI.md) and license, obey them, and record them in reports. Known: upstream AsahiLinux/m1n1 has a root CLAUDE.md/AGENTS.md (commit c9a03479, 2026-07-14) telling AI tools not to use that repository, so AI sessions don't clone, read, build, run, or patch upstream m1n1. Forks and other repos are governed by their own instructions and licenses. Prefer an authorized path (e.g. a fork whose own instructions allow AI) over handing work to the owner. Only hand a step to the owner when no authorized path exists, and cite why. Asahi's LLM policy (https://asahilinux.org/llm-policy/) covers material contributions to Asahi Linux. We aren't submitting anything there, so it doesn't limit our own work. Never delete or relabel existing results. Keep provenance notes accurate.

## Owner priorities (2026-11-04)
- Outcome: Omarchy running **natively** on this M5 Pro. Establish what works on this exact hardware, what blocks booting, which projects help; give an evidence-backed path to a bootable system, then work through the blockers.
- **Hardware support and booting Linux come before desktop packaging.**
- Always label results **NATIVE** (on the J714s, bare metal), **VM** (Try Omarchy / QEMU), or **REPORTED** (someone else's claim we haven't reproduced).
- Preserve macOS and recovery. **Explicit owner approval before repartitioning, firmware changes, or anything destructive.**
- Don't hand core work to the owner unless there's a real, cited blocker (see rule 7).
8. Never open interactive question dialogs. If you need a decision, write the options and your recommendation, end with BLOCKED NN: <question>, and stop. If a decision is routine, pick the conservative option, record it, and keep going.
