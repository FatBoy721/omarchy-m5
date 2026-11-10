#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# start-hyprland / hyprland on the J714s: pick the graphics stack that works on
# the running kernel.
#
# The distro's Mesa has no driver for the aurora GPU node. On a GPU kernel,
# Aquamarine picks that node, EGL fails ("failed to create dri2 screen") and
# Hyprland aborts in initEGL, every time. With the node present this starts the
# private GPU session instead; without it (the GPU-less fallback kernels) the
# distro session, as before.
#
#   sudo install -Dm755 scripts/start-hyprland.sh /usr/local/bin/start-hyprland
#   sudo ln -sfn start-hyprland /usr/local/bin/hyprland
#
# /usr/local/bin comes first in PATH, so both everyday commands land here. The
# distro's own launcher stays reachable as /usr/bin/start-hyprland.
set -euo pipefail

for driver in /sys/class/drm/card*/device/driver; do
    if [[ $(basename "$(readlink -f "$driver")") == aurora ]]; then
        exec /usr/local/bin/start-hyprland-gpu "$@"
    fi
done
exec /usr/bin/start-hyprland "$@"
