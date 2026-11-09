# Task 22: Plan B, a stub with non-26.6.2 OS firmware (research + exact plan; NO Mac changes)

Why: report 21 found (REPORTED) that on 26.6.2 OS firmware even stock Asahi stage-1 makes iBoot panic before m1n1 runs. Raw boots are reported working on 18000.120.36 (26.5) and 20457.x (27.x). Our stub was cloned from the host 26.6.2, so its stage-2 mBoot is 18000.161.10.
From allowed sources (asahi-installer MIT; omarchy-mac-installer engine MIT/AI-allowed; Asahi docs; Apple docs):
1. How the asahi-installer / omarchy engine build a stub from a chosen IPSW/OS-firmware version (partial IPSW download, which components, personalization/TSS, what step2/bputil does), and how we would do that for J714s (patch their board tables locally if needed).
2. Which versions are currently SIGNED for Mac17,9 (ipsw.me lists 27.2, 27.0.1, 27.0, 26.6.2, 26.6.1, 26.6; check 26.5 / 26.4), and which are REPORTED to boot raw images on T6050 (report 19).
3. Recommended version (prefer the one with REPORTED T6050 raw-boot success, e.g. 27.x 20457.x or 26.5 if signed) and risks (the macOS 27 beta partition-hiding report; boot picker behaviour; does a newer stub firmware than the host macOS cause issues?).
4. Exact plan: replace the existing stub (delete + recreate) vs a second stub; commands; what the owner does in 1TR; undo.
Write reports/22-stub-firmware.md. End with DONE 22.
