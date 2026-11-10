#!/bin/bash
# Catch m1n1 at boot, chainload a matching host m1n1, run PAYLOAD under the HV.
# Logs: hv-<ts>.{chain,out,uart}.log. Run inside tmux session "m5hv".
set -u
export USE_CLANG=1
cd "$(dirname "$0")"; P=${PYTHON:-python3}; T=m1n1-proxy/tools
PAYLOAD=${1:?usage: hvtest.sh PAYLOAD [run_guest.py args...]}; L=logs/hv-$(date +%H%M%S); mkdir -p logs
echo "waiting for m1n1 proxy..."; until [ -e /dev/m1n1 ]; do sleep 0.02; done
$P $T/chainload.py -r ${HOST_M1N1:-../../build/m1n1-installer/build/m1n1.bin} 2>&1 | tee $L.chain.log | tail -3
sleep 1; until [ -e /dev/m1n1 ] && [ -e /dev/m1n1-sec ]; do sleep 0.1; done
stty -F /dev/m1n1-sec raw -echo 2>/dev/null; cat /dev/m1n1-sec > $L.uart.log &
echo "guest uart -> $L.uart.log"
export USE_CLANG=1
shift; exec $P $T/run_guest.py -l $L.out "$@" -r "$PAYLOAD"
