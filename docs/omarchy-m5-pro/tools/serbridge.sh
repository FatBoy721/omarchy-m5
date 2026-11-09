#!/bin/sh
# serbridge.sh: expose /dev/ttyUSB0 on 127.0.0.1:7777 here and on <worker-host> (reverse tunnel) for the workers
while :; do socat TCP-LISTEN:7777,bind=127.0.0.1,reuseaddr FILE:/dev/ttyUSB0,raw,echo=0; sleep 1; done &
while :; do ssh -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -N -R 127.0.0.1:7777:127.0.0.1:7777 <worker-host>; sleep 3; done
