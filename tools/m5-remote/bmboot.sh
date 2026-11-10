#!/bin/bash
# Bare-metal one-shot: catch m1n1 at boot and chainload PAYLOAD from RAM.
# Nothing on disk changes; any later uncaught boot runs the ESP default.
set -u
cd "$(dirname "$0")"; P=${PYTHON:-python3}; T=m1n1-proxy/tools
echo "waiting for m1n1 proxy..."; until [ -e /dev/m1n1 ]; do sleep 0.02; done
USE_CLANG=1 $P $T/chainload.py -r "$1" 2>&1 | grep -vE '^TTY>' | tail -4
echo "chainloaded at $(date +%T)"
