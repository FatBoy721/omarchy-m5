#!/bin/bash
# dump-j714s.sh — read-only hardware dump for Apple Silicon Macs (target: J714s / M5 Pro).
# Normal user, no sudo, writes nothing. All output passes through scrub(), which ends with a
# per-key count of what it replaced.
# Usage: bash dump-j714s.sh [--full] > 04-j714s-full.txt
#   --full  also emit the whole scrubbed ADT between "=== BEGIN FULL ADT" / "=== END FULL ADT"
#           (cut it out with: sed -n '/^=== BEGIN FULL ADT/,/^=== END FULL ADT/p')
set -u
export LC_ALL=C

# Replace identifying values with <scrubbed> and count replacements per key.
scrub() {
  perl -ne '
    BEGIN { $k = qr/serial|uuid|udid|ecid|unique-chip-id|nonce|random-seed|mac-?address|macaddr|wifi-?addr|bt-?addr|bluetooth-?addr|device-?address|mlb|provisioning|unique-id|imei|hardware.?id|region-info|ssid|entropy|seed|hash|digest/i; }
    if (/("([^"]*$k[^"]*)"\s*=\s*)(.*)/ && $3 ne "<scrubbed>") { $c{$2}++; s//$1<scrubbed>/; }
    elsif (/^(\s*([^:="]*$k[^:="]*):\s*).+/) { $c{$2}++; s//$1<scrubbed>/; }
    $n = s/\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b/<scrubbed>/g; $c{"(uuid-shaped string)"} += $n if $n;
    $n = s/\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b/<scrubbed>/g;            $c{"(mac-shaped string)"} += $n if $n;
    print;
    END { print "\n=== scrub summary (key: count)\n"; printf "%6d  %s\n", $c{$_}, $_ for sort keys %c; print "  (nothing scrubbed)\n" unless %c; }
  '
}

le32() { local h; h=$(sed -E 's/.*<([0-9a-fA-F]+)>.*/\1/' <<<"$1"); [ -n "$h" ] && printf '0x%x\n' "$((16#$(sed -E 's/(..)(..)(..)(..).*/\4\3\2\1/' <<<"${h}00000000")))"; }
prop() { grep -m1 "\"$1\" = " <<<"$2"; }

ADT=$(ioreg -p IODeviceTree -l -w0)
SVC=$(ioreg -p IOService -l -w0)

# node NAME [TREE]: header line + own properties of every node named NAME or NAME@addr (until next +-o)
node() {
  awk -v n="$1" '
    /\+-o /{ p=0; h=$0; sub(/^[ |]*\+-o /,"",h); split(h,a," "); split(a[1],b,"@"); if (b[1]==n) { p=1; print "" } }
    p' <<<"${2:-$ADT}"
}
# subtree NAME [TREE]: node NAME plus all its descendants (header lines and properties)
subtree() {
  awk -v n="$1" '
    /\+-o /{ i=index($0,"+-o"); h=substr($0,i+4); split(h,a," "); split(a[1],b,"@");
             if (p && i<=d) p=0; if (!p && b[1]==n) { p=1; d=i; print "" } }
    p' <<<"${2:-$SVC}"
}

{
echo "=== dump-j714s.sh v2  $(date -u +%Y-%m-%dT%H:%MZ)"
echo; echo "=== macOS / firmware"
sw_vers
system_profiler SPHardwareDataType 2>/dev/null | grep -Ei 'model|chip|cores|memory|firmware|loader'
for k in firmware-version system-firmware-version os-loader-version iboot-version; do prop "$k" "$(node chosen)"; done

echo; echo "=== identity"
ROOTN=$(awk '/\+-o /{c++} c==2{exit} {print}' <<<"$ADT")   # root node's own properties
for k in compatible model target-type; do prop "$k" "$ROOTN"; done
for k in chip-id board-id chip-revision security-domain; do
  l=$(prop "$k" "$(node chosen)$ROOTN"); [ -n "$l" ] && echo "$l  -> $(le32 "$l")"
done

echo; echo "=== sysctl"
sysctl hw.model hw.ncpu hw.physicalcpu hw.memsize hw.nperflevels machdep.cpu.brand_string 2>/dev/null

echo; echo "=== ADT nodes of interest (own properties)"
for n in arm-io uart0 pmgr pmgr1 pmp0 iop-pmp0-nub dart-pmp0 mapper-pmp0 mapper-pmp0-ptd-fwd \
         mtp iop-mtp-nub dart-mtp mapper-mtp sgx gfx-asc gpu; do
  echo "--- $n"; node "$n"
done

echo; echo "=== pmgr function-* and notify-related property names"
node pmgr | grep -oE '"(function-[^"]*|[^"]*notify[^"]*)"' | sort -u

echo; echo "=== IOService skeleton for pmp/mtp/pmgr/gfx/agx/sgx/cpu nodes (class names only)"
grep -E '\+-o ' <<<"$SVC" | grep -iE '\+-o [^ ]*(pmp|mtp|pmgr|gfx|agx|sgx|gpu|cpu)' | sed -E 's/, id 0x[0-9a-f]+//; s/, (registered|matched|active|busy|retain)[^>]*//'

echo; echo "=== IOService subtrees (classes, bundle ids, matched properties)"
for n in pmp0 mtp pmgr sgx gfx-asc agx gpu cpu0 cpu12; do
  echo "--- $n"; subtree "$n" | grep -E '\+-o |"(IOClass|CFBundleIdentifier|IOProviderClass|IONameMatch|IONameMatched|IOMatchedAtBoot|IOPropertyMatch|compatible|role|name)" = '
done

echo; echo "=== bputil -d"
if out=$(bputil -d </dev/null 2>&1); then echo "$out"; else echo "skipped: $(head -1 <<<"$out")"; fi

echo; echo "=== unique compatible strings"
grep '"compatible" = ' <<<"$ADT" | sed -E 's/.*"compatible" = //' | perl -ne 'print "$1\n" while /"([^"]+)"/g' | sort -u

if [ "${1:-}" = "--full" ]; then
  echo; echo "=== BEGIN FULL ADT"; echo "$ADT"; echo "=== END FULL ADT"
fi
} 2>&1 | scrub
