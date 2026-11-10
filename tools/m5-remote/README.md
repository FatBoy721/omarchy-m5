# m5-remote: hands-free J714s test loop

Drive the Mac from a Linux host over the USB-C tether (the Mac's left-back
port). On every boot the installed stage-1 m1n1 offers its USB proxy for a
few seconds; grabbing it gives full control, and not grabbing it lets the
normal ESP default boot. Nothing here writes the disk or the ESP.

Setup: `make m1n1-installer` (builds `build/m1n1-installer`, whose
`proxyclient/` is linked here as `m1n1-proxy`), a Python with `pyserial` and
`construct` (`PYTHON=...`), and a udev rule for `/dev/m1n1` (m1n1's
`udev/80-m1n1.rules`, readable by your user).

| Script | What it does |
| --- | --- |
| `m5catch.py info\|reboot` | Catch the proxy at boot; print boot-args, reboot through m1n1. |
| `hvtest.sh PAYLOAD [-m SCRIPT]` | Catch, chainload a host m1n1, run PAYLOAD under the hypervisor; guest UART in `logs/`. Run it in tmux. |
| `hvwdt.py` | `-m` script: dedicate cpu16 as HV watchdog (host stall >1 s reboots the Mac). Always use it. |
| `trace-apcie.py` | `-m` script: SYNC-trace the apcie/N1 MMIO, plus `hvwdt.py`'s watchdog. Don't trace ranges whose bad access can SError the host. |
| `bmboot.sh LOADER` | Bare metal: catch and chainload a small stage-2 loader from RAM (it reads the kernel/DTB from the ESP folder named in its `boot=`). Hang = power-cycle once; next uncaught boot is the ESP default. |
| `mkguest.py` | Build a self-contained m1n1 payload (loader + chosen.* + DTB + kernel + initramfs). `--allow-extra fpwm0` extends `m5_pmgr_allow`. |
| `patch_initrd.py` | Edit one file inside a gzipped newc initramfs, keeping device nodes intact (e.g. make the USB-gadget failure non-fatal for HV guests). |
| `arm_wdt.py` | Arm the SoC watchdog from the proxy. See the warning in the file: repeated watchdog resets sent the next boot to macOS. |

Hypervisor runs: disable `usb@2aa280000` and its DARTs in the guest DTB
(`fdtput -t s guest.dtb /soc/usb@2aa280000 status disabled`), since the host
m1n1 owns that controller for the proxy.
