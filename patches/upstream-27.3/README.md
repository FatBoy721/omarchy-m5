# aurora-silicon base on the 27.3 beta 1 stub (J714s)

Work toward running aurora-silicon's `integration/aurora` kernel and the Aura bootloader on
TripleU613's J714s while it stays on the macOS 27.3 beta 1 stub (26C5035r,
mBoot-20457.60.65.0.1), with the GPU and the internal display handed over as our own kernel and
m1n1 do today.

Status (2026-11-11): **builds, not yet boot-tested.** Do not ship. The first staging attempt
broke the dev Linux root (a `lib/` modules tarball extracted at `/` replaced the `/lib -> usr/lib`
symlink); `~/m5/tools/rescue-lib-bm.bin` repairs it on the next boot and `stage-up273.sh` stages
under `/usr` instead.

| Patch | Applies to | What |
| --- | --- | --- |
| `0001-linux-integration-aurora-pr1173-pr1174-merged.patch` | aurora-silicon/linux `integration/aurora` at f1b79c4beaef (first written on 990e00b72b56) | #1174 as first published (290b7de9f129 + 0cdf8957541b: the full 27.3 method table and swap layout; Jeff Queisser, Rolando Trevino). The updated #1174 (61a1fd086170 + bf43e8cefdf3) has a deliberately partial 27.3 table (the 20 traced methods) and refuses to start a 27.3 DCP ("no ID known for 21 methods"), so it is not used until its table is complete and #1173 (GPU 27.2/27.3 InitData layouts and firmware identity; Rolando Trevino) merged. #1173 conflicted with upstream's `Graph` refactor: each build gets its own `Graph` (`M5_GRAPH_26B123`, `M5_GRAPH_26C5035`, chosen by the firmware's identified layouts), `hw_offset()` and the board graph are kept, and the J813 (common26) keeps its board graph. Compiles with rustc 1.98.0 on ush. |
| `0002-aura-t6050-27.3-gpu-dcp-handoff.patch` | aurora-silicon Aura 1.0.0b11 (main dbf088e151; #173 M5 Pro boot path, #180 DART; first written on 1669cad0) | Aura knows 27.2 and 27.3 beta 1; its T6050 GPU handoff admits the 27.0, 27.2 and 27.3 beta 1 GPU builds (digests and boot-filled ranges from #1173); its T6050 DCP handoff accepts 27.3 beta 1, takes the DCP image the ADT names and publishes `apple,firmware-compat <27 3 0>` (what #1174 keys its 27.3 table by). Only the firmware gate, image check and compat key are changed; our m1n1's notch rows and display-default handling (m1n1-installer 0006/0007) are not ported, so the full 3024x1964 panel is unverified. |
| `0003-aura-notch-default-and-m5-max-27.3-gpu.patch` | after 0002 | The notch rows by default on M5 (T6050/T6051): without a config line Aura keeps iBoot's full framebuffer and sets `/chosen/asahi,show-notch = "1"`; `chosen.asahi,show-notch=0` opts out. And joshuaswarren's M5 Max 27.3 GPU digest (aurora-silicon/aura #172, the upstream equivalent for the Max of 0002's G17S entries) as one more entry in 0002's build table, so there is a single digest check. |

Kernel: `0001` is on `integration/aurora` f1b79c4beaef (after #1595 ANE, #1600 DCP HDR, #1577 AVD, #1597 AVE), cross-built on ush, which the image's kernel recipe (`installer/recipes/linux-aurora-upstream`) builds. Kernel branch: `build/linux-up` branch `up-273c` (merges 0929f4f5c93b, 8a0eb8647062, fix
e0516e36058b). Aura branch: `~/m5/work/up/aura` `up-273-image-b11` (0002 + 0003 on main dbf088e1), packaged by `installer/recipes/m1n1-aurora-upstream`.

Still to check on the Mac: GPU firmware up, DCP modeset 3024x1964@120 with the notch rows,
Wi-Fi (`CONFIG_APPLE_CENTAURI_T6050=m`), trackpad, NVMe.

## Boot test on TripleU613's J714s (27.3 beta 1 stub, 2026-11-11)

Aura (0002, test watchdog) chainloaded from the stage-1 m1n1 proxy, kernel `7.3.0-j714s-up+` (0001):

- GPU: `GPU firmware build: 26C5035r for T6050 G17S` (the 27.3 firmware); Vulkan `Apple M5 Pro (G17S B1)`, Borealis.
- Internal display: DCP handed over, `eDP-1` 3024x1890 at 120 Hz (`set_digital_out_mode ... 120`); notch rows not shown yet (m1n1 0007's default is not in Aura yet). External DCPs and `DP-1`..`DP-4` registered.
- Wi-Fi (N1) up, trackpad (`Touch MT ready`), NVMe, USB (a device enumerates, Type-C ports 0/1), SEP firmware reserved by Aura, USB4 router (acio) present, AOP sensors.
- Notch rows: with `chosen.asahi,show-notch=1` in Aura's config the panel runs 3024x1964 at 120 Hz.
- Sound: with `CONFIG_SND_SOC_APPLE_T8152_AOP_AUDIO=m` (off in our config) the `AppleJ714` card (speakers, headphone jack) and `AppleJ714HPAI` (microphones) come up; the speakers stay locked until speakerguardd (shipped in the image) takes them, not tried on the dev Linux.

## Packaged kernel boot test (2026-11-12, RAM, Aura 1.0.0b11)

linux-aurora 7.3.0.aurora17.up273-2 (f1b79c4b + this 0001) from RAM via Aura b11 with the test watchdog: GPU 26C5035r, DCP `eDP-1` 3024x1964 at 120 Hz on apple-drm (the notch rows), Hyprland running, Wi-Fi up. The up273-1 build with the updated #1174 had no DCP (simpledrm only). Not working on 27.3 yet: the ANE (the kernel pins the 27.0 TEXT digest and the preloaded TEXT reads as zeros) and the AVE encoder ("unexpected firmware segment sizes").
