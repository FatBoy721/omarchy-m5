#!/bin/bash
# compat-diff.sh COMPATS M1N1_DIR LINUX_DIR [EXTRA_TEXT]
# For each ADT compatible: m1n1 = exact string in m1n1 src/proxyclient; linux = exact string, or its
# family (drop the trailing SoC suffix, e.g. "pmgr,t6050" -> "pmgr") appears in Linux/m1n1 source as a
# known compatible; aurora = string present in EXTRA_TEXT (Aurora t6050 patches).
set -u
c=$1; m=$2; l=$3; x=${4:-/dev/null}
grep -rhoE '"[A-Za-z0-9_,.+-]+"' "$m"/src "$m"/proxyclient 2>/dev/null | tr -d '"' | sort -u > /tmp/.m1n1s.$$
grep -rhoE '"[A-Za-z0-9_,.+-]+"' "$l"/drivers "$l"/sound "$l"/arch/arm64/boot/dts/apple 2>/dev/null | tr -d '"' | sort -u > /tmp/.lnx.$$
grep -hoE '"[A-Za-z0-9_,.+-]+"' "$x" | tr -d '"' | sort -u > /tmp/.aur.$$
printf '%-40s %-7s %-7s %-7s %s\n' compatible m1n1 linux aurora family
while read -r s; do
  [ -z "$s" ] && continue
  f=$(sed -E 's/,(t|s)[0-9]{4}[a-z]?$//; s/-(t|s)[0-9]{4}$//' <<<"$s")
  inm=no; grep -qxF "$s" /tmp/.m1n1s.$$ && inm=yes
  inl=no; grep -qxF "$s" /tmp/.lnx.$$ && inl=yes
  if [ $inl = no ] && [ "$f" != "$s" ] && grep -qE "^$f,(t|s)[0-9]{4}" /tmp/.m1n1s.$$ /tmp/.lnx.$$; then inl=family; fi
  ina=no; grep -qxF "$s" /tmp/.aur.$$ && ina=yes
  printf '%-40s %-7s %-7s %-7s %s\n' "$s" $inm $inl $ina "$f"
done < "$c"
rm -f /tmp/.m1n1s.$$ /tmp/.lnx.$$ /tmp/.aur.$$
