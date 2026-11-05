#!/bin/sh
# sshbridge.sh: <worker-host>:127.0.0.1:2201 -> Mac 10.55.0.1:22 (over the USB EEM link on this PC)
while :; do ssh -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -N -R 127.0.0.1:2201:10.55.0.1:22 <worker-host>; sleep 3; done
