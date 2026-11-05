#!/bin/sh
# Task 18 (VM only): sparse NVMe disk image like the J714s disk0, with 4096-byte logical blocks.
# Facts from the PM (macOS, 22:53): disk0s4 = EFI type, FAT32, 499,998,720 B, empty; disk0s5 = Linux filesystem type,
# 120,000,000,000 B, first 4 MiB zero; the rest are Apple partitions (ISC, 868 GB APFS, 6 GB stub, recovery).
# The order of s1-s3/s6 and their exact sizes are an approximation (only s4/s5 matter to the logger).
# Usage: tests/mkdisk-j714s.sh OUT.img
set -e
O=$1
rm -f "$O"; truncate -s 1001000000000 "$O"
APFS=7C3457EF-0000-11AA-AA11-00306543ECAC; ISC=69646961-6700-11AA-AA11-00306543ECAC
REC=52637672-7900-11AA-AA11-00306543ECAC; ESP=C12A7328-F81F-11D2-BA4B-00A0C93EC93B; LNX=0FC63DAF-8483-4772-8E79-3D69D8477DE4
s() { echo $(( $1 / 4096 )); }	# bytes -> 4 KiB sectors
sfdisk --sector-size 4096 -q "$O" <<EOF
label: gpt
first-lba: 6
size=$(s 524288000), type=$ISC
size=$(s 868000000000), type=$APFS
size=$(s 6000000000), type=$APFS
size=$(s 499998720), type=$ESP
size=$(s 120000000000), type=$LNX
size=$(s 5368709120), type=$REC
EOF
start=$(sfdisk --sector-size 4096 -d "$O" | grep -F "${O}4 :" | sed 's/.*start= *\([0-9]*\).*/\1/')
mkfs.vfat -F 32 -S 4096 --offset="$start" -n M5ESP "$O" $(( 499998720 / 1024 )) >/dev/null
sfdisk --sector-size 4096 -l "$O" | tail -7
