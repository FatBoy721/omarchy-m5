# Task 12 — Desktop path research: Omarchy on aarch64 without a GPU driver (no Mac changes)

The goal includes a **usable Omarchy desktop** natively. Hardware comes first, but we need to know early what the desktop needs. Output: `reports/12-desktop-path.md`. Rule 7 applies: check each repo's AI instructions + license.

1. **Omarchy on aarch64 Arch (ALARM):**
   - How omacom ships Omarchy for Apple silicon (omarchy-mac-pkgs, pkgs.omarchy.org aarch64 repo, omarchy-mac-installer). Which parts are Apple-specific (kernel/m1n1/Mesa) vs plain Omarchy.
   - Can we install the Omarchy userland on our ALARM rootfs with **our** kernel (IgnorePkg for theirs)? List exact repos, keys, packages, and the install command sequence. Note any packages that assume x86_64 or a GPU.
2. **Hyprland with no GPU driver:**
   - Display = simpledrm (the iBoot framebuffer, 3024x1964). Can Hyprland (aquamarine) run on simpledrm with Mesa llvmpipe/softpipe (EGL on GBM, kms_swrast), or a pixman/software renderer? Cite Hyprland/aquamarine docs/issues.
   - Expected performance on **1 core** vs N cores.
   - What's the minimum for "usable" (login, terminal, browser)?
3. **What multi-core changes:** quantify why SMP (the PMP blocker) matters for a usable desktop, with numbers from sources if available (llvmpipe scales with cores).
4. **Input/other essentials for daily use:** keyboard/trackpad (DockChannel MTP: already in the safe kernel), backlight (does brightness need SMC/PMGR? we banned SMC), battery status (SMC-based, banned for now), suspend (disable for now), Wi-Fi (N1, no driver: use USB-Ethernet once USB host works, or USB gadget networking via work for package installs).
5. **A proposed staged plan:** Stage A console + SSH (first boot) → B Omarchy userland on simpledrm/llvmpipe single-core → C SMP (PMP) → D GPU. What "usable" means at each stage, and which stage meets the goal's bar (to be confirmed by the owner later; don't ask now).

End with `DONE 12`.
