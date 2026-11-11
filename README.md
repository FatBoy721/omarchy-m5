# omarchy-m5

**[Omarchy](https://omarchy.org) on the 14-inch MacBook Pro with M5 Pro (J714s).**

We don't reinvent anything. A lot of people are getting Linux running on the M5 Macs, each
in their own repo. We collect the parts that already work, put them together in one image,
test it on a real J714s, and say who made each part.

---

## What works

| Thing | Works? | Whose work |
| --- | --- | --- |
| Boots from the Mac's own disk, all 15 CPU cores | ✅ | Apple's firmware fix + rolotrealanis98, betizzel |
| Keyboard, backlight | ✅ | rolotrealanis98, edimoldovan |
| Trackpad (every boot) | ✅ | edimoldovan (the reset fix) |
| Wi-Fi, Bluetooth | ✅ | rolotrealanis98, betizzel, TripleU613, DjDeveloperr |
| Wi-Fi on 6 GHz | 🟡 in the next image, not tested here | edimoldovan |
| Speakers, headphone jack, microphones | 🟡 works, speakers kept quiet on purpose (-30 dB cap) | rolotrealanis98, edimoldovan |
| GPU (Vulkan) | ✅ | TripleU613, betizzel, DjDeveloperr |
| Screen | ✅ (basic mode; full-speed mode coming) | betizzel, DjDeveloperr |
| Sleep (lid close) | 🟡 works on the dev kernel, not yet in the image | betizzel |
| USB-C ports, external displays, USB4 | 🔜 testing now (aurora-silicon's new J714s kernel) | DjDeveloperr, erikwb |
| Quiet fans at idle | 🔜 in the next image | edimoldovan |
| Camera, Touch ID | ❌ not yet | |

✅ works · 🟡 partly · 🔜 coming · ❌ no

---

## Try it

You need:

- A **MacBook Pro 14-inch, M5 Pro** (J714s). Not M5 Max, not the 16-inch, not yet.
- **macOS 27.3 beta 1 or newer** on it.
- About **35 GB free** on the Mac's disk.
- A Linux PC and a USB-C cable for the first setup.

Steps:

1. **Set up the Mac once** so it can boot Linux:
   follow [`docs/bringup.md`](docs/bringup.md). This is the only fiddly part.
2. **Download the image** on your PC:
   ```sh
   gh release download j714s-developer-image-2026.11.11 -R betizzel/omarchy-m5
   cat omarchy-2026.11.11-*.zip.part0 omarchy-2026.11.11-*.zip.part1 \
     > omarchy-2026.11.11-aarch64-apple-silicon-mac-edge-os-package.zip
   sha256sum -c SHA256SUMS --ignore-missing
   ```
3. **Write it to the Mac** from Linux running on the Mac, as root:
   ```sh
   tools/install-image/install-from-linux.sh omarchy-2026.11.11-*.zip /usr/lib/firmware
   ```
4. **Reboot.** First boot sets things up, then asks for your name and password.

Stuck? Open an [issue](https://github.com/betizzel/omarchy-m5/issues) and paste what you see.

---

## Who we collect from

These are the people and repos we watch. A script ([`tools/watch/watch.sh`](tools/watch/watch.sh))
checks all of them every 30 minutes for new commits, and anything new that works on a J714s
gets pulled in here.

### M5 Mac owners doing the bring-up

| Who | Mac | Their repo | What we took |
| --- | --- | --- | --- |
| [rolotrealanis98](https://github.com/rolotrealanis98) | 16" M5 Pro (J716s) | [m5pro-linux](https://github.com/rolotrealanis98/m5pro-linux), [m4-m5-linux](https://github.com/rolotrealanis98/m4-m5-linux) (status tracker) | the T6050 kernel base, audio, many fixes |
| [edimoldovan](https://github.com/edimoldovan) | 14" M5 Max (J714c) | [linux-aurora](https://github.com/edimoldovan/linux-aurora), [omarchy-mac-pkgs](https://github.com/edimoldovan/omarchy-mac-pkgs) | trackpad reset, speaker safety + sound profiles, 6 GHz Wi-Fi, quiet idle fans |
| [DjDeveloperr](https://github.com/DjDeveloperr) | 14" M5 Pro (J714s) | via [aurora-silicon/linux](https://github.com/aurora-silicon/linux) and [aura](https://github.com/aurora-silicon/aura) | the upstream J714s device tree: USB-C, USB4, displays, GPU handoff (testing now) |
| [betizzel](https://github.com/betizzel) | 14" M5 Pro (J714s) | this repo | the first J714s boot, display, GPU |
| [TripleU613](https://github.com/TripleU613) (Nignion on X) | 14" M5 Pro (J714s) | this repo | Wi-Fi, GPU, the installer image |
| [FatBoy721](https://github.com/FatBoy721) | 14" M5 Pro (J714s) | | reported the installer image booting to the Omarchy desktop (#293) |
| [cameroncooper](https://github.com/cameroncooper) | 16" M5 Max (J716c) | | watched (Aura stage 1, accelerated Hyprland on J716c) |
| [joshuaswarren](https://github.com/joshuaswarren) | | | J714c PMP and USB-C upstream, PMP analysis in #293 |
| [erikwb](https://github.com/erikwb) | | | T6050 USB4 and external displays upstream (J716c) |

### The Omarchy-on-Mac team ([omacom](https://github.com/omacom))

[maralcbr](https://github.com/maralcbr) (Marcelo Alcantara) ·
[scottjones](https://github.com/scottjones) (Scott Jones) ·
[chriskearney](https://github.com/chriskearney) (Chris Kearney) ·
[malik-na](https://github.com/malik-na) (Naeem Malik) ·
[DjDeveloperr](https://github.com/DjDeveloperr) (Dj) ·
[joshuaswarren](https://github.com/joshuaswarren) (Joshua Warren) ·
[themartiano](https://github.com/themartiano) (Eduardo Martinez) ·
[riverscn](https://github.com/riverscn) (Shun Li) ·
[RyanTheTide](https://github.com/RyanTheTide) (Ryan Murray) ·
[Acelogic](https://github.com/Acelogic) (Miguel Cruz) ·
[LiamRay11](https://github.com/LiamRay11) (Liam) ·
[erykwieliczko](https://github.com/erykwieliczko) (Eryk Wieliczko) ·
[subedijaidip](https://github.com/subedijaidip) (Jaidip Subedi) ·
[shawnyeager](https://github.com/shawnyeager) (Shawn Yeager) ·
[jondkinney](https://github.com/jondkinney) (Jon Kinney) ·
Randy (GitHub name unknown: tell us)

Also watched: [satchlj](https://github.com/satchlj), [joske](https://github.com/joske).

### Repos we watch

| Repo | What it is |
| --- | --- |
| [aurora-silicon/linux](https://github.com/aurora-silicon/linux) | the Apple Silicon kernel everyone lands work in |
| [aurora-silicon/aura](https://github.com/aurora-silicon/aura) | the bootloader (m1n1 fork) |
| [aurora-silicon/mesa](https://github.com/aurora-silicon/mesa), [u-boot](https://github.com/aurora-silicon/u-boot) | graphics drivers, U-Boot |
| [omacom/linux-aurora](https://github.com/omacom/linux-aurora), [m1n1](https://github.com/omacom/m1n1) | Omarchy's kernel and bootloader |
| [omacom/omarchy-mac-pkgs](https://github.com/omacom/omarchy-mac-pkgs), [omarchy-mac-installer](https://github.com/omacom/omarchy-mac-installer) | Omarchy's Mac packages and installer |
| [omacom/linux-aurora#293](https://github.com/omacom/linux-aurora/issues/293) | the thread where M5 owners post results |
| [omarchyarchive.com](https://omarchyarchive.com/search/?q=M5) | community posts about the M5 Macs (X, blogs) |

Plus every repo the people above push to, and a GitHub-wide search for `t6050`, `j714s`,
`j714c`, `j716s`, `m5 pro linux`, `m5 max linux`. Know someone we missed? Open an issue.

---

## Help out (dev)

You don't need to be a kernel hacker. The easiest ways to help:

- **Got a J714s?** Try the image and tell us what works and what doesn't.
- **Found someone's M5 work that we don't have?** Open an issue with the link. That's the whole job here.
- **Want to watch the repos yourself?** `tools/watch/watch.sh` (needs `gh` logged in). The first
  run just records where everything is; after that it prints what changed.

Want to build it yourself? The kernel and bootloader patches are in [`patches/`](patches/), the
image recipe in [`installer/`](installer/README.md), and the full build guide is
[`docs/bringup.md`](docs/bringup.md). Everything detailed (status history, how each piece was
found, the old notes) lives in [`docs/status-and-history.md`](docs/status-and-history.md).

---

Built on [Asahi Linux](https://asahilinux.org), [Aurora Silicon](https://github.com/aurora-silicon)
and [omacom](https://github.com/omacom). [MIT](LICENSE) for this repo's own scripts and docs;
patches keep the license of the project they apply to. No Apple firmware is shipped here.
