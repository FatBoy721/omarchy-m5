# Task 18 (PRIORITY, pause 17): fast iteration step2 + one-shot boot

The owner wants faster native test cycles. Write tools/step2-fast.sh (based on betizzel step2.sh, which is MIT; keep the license header). It runs in the stub 1TR like step2:
1. Skip bputil -nc if the stub LocalPolicy is already Permissive (check with bputil -d -v VGID for "Permissive"). Only run it if needed.
2. Run kmutil configure-boot -c boot.bin --raw --entry-point 2048 --lowest-virtual-address 0 -v <stub system volume>, exactly as step2 does.
3. Make the next boot go to the stub ONCE while the default stays Macintosh HD (bless --nextonly, or the equivalent that works from 1TR; cite the man page). A failing test then powers off and the next normal power-on boots macOS, with no PanicMedic 5x loop.
4. Restore/disable the install-media marker exactly as step2 does, then reboot.
Also give the exact over-SSH commands (macOS side) to (a) drop a new boot.bin + step2-fast.sh into the stub Finish Installation.app and (b) re-arm .IAPhysicalMedia, WITHOUT re-blessing the stub as default (or bless it --nextonly). The PM runs them over SSH with expect. Keep the macOS default = Macintosh HD.
Target per-cycle owner steps: hold power, Omarchy, Continue, FileVault password, Enter, one kmutil password. Document the exact prompts. End with DONE 18, then resume 17 if still useful.
