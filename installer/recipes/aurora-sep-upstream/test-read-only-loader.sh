#!/bin/bash
# Exercise the patched aurora-sep-load against a fake modprobe and sysfs.
# $1: patched loader.
set -u
loader=$1
fail=0
run_case() {
  local name=$1 config=$2 xart=$3 want_rc=$4 want_log=$5
  local t
  t=$(mktemp -d)
  mkdir -p "$t/bin" "$t/devices/1234.sep/diag"
  [[ $xart == absent ]] || printf '%s\n' "$xart" >"$t/devices/1234.sep/diag/xart"
  printf '%s\n' "$config" >"$t/config"
  cat >"$t/bin/modprobe" <<EOF
#!/bin/sh
if [ "\$1" = -c ]; then cat "$t/config"; exit 0; fi
printf '%s\n' "\$*" >>"$t/calls"
EOF
  printf '#!/bin/sh\nexit 1\n' >"$t/bin/keyctl"
  chmod 0755 "$t/bin/modprobe" "$t/bin/keyctl"
  sed "s|/sys/bus/platform/devices|$t/devices|g; s|/sys/module/apple_sep/parameters/keystore_only|$t/none|; s|/run/aurora-sep-load|$t/run-aurora-sep-load|g" "$loader" >"$t/loader"
  local out rc
  out=$(PATH="$t/bin:$PATH" AURORA_SEP_SESSION=1 AURORA_SEP_READY_TIMEOUT=1 sh "$t/loader" 2>&1)
  rc=$?
  local calls
  calls=$(cat "$t/calls" 2>/dev/null)
  if [[ $rc != "$want_rc" || $out != *"$want_log"* || $calls != "apple_sep" ]]; then
    echo "FAIL $name: rc=$rc calls=[$calls] out=$out"
    fail=1
  else
    echo "ok   $name (rc=$rc): ${out:0:110}"
  fi
  rm -rf "$t"
}
run_case "read-only default" "options apple_sep xart_writes=0 provision_keybag=0" disabled 0 "read-only"
run_case "owner opt-in, driver writes" "options apple_sep xart_writes=1 provision_keybag=1" enabled 1 "did not seal"
run_case "owner opt-in, store refused" "options apple_sep xart_writes=1 provision_keybag=1" disabled 1 "asks for xART writes"
run_case "later file wins (writes)" $'options apple_sep xart_writes=0 provision_keybag=0\noptions apple_sep xart_writes=1 provision_keybag=1' disabled 1 "asks for xART writes"
run_case "later file wins (read-only)" $'options apple-sep xart_writes=1\noptions apple_sep xart_writes=0' disabled 0 "read-only"
run_case "nothing configured = driver default 1" "" disabled 1 "asks for xART writes"
run_case "no diag attribute, read-only" "options apple_sep xart_writes=0 provision_keybag=0" absent 0 "xART absent"
run_case "no diag attribute, owner opt-in: upstream flow" "options apple_sep xart_writes=1 provision_keybag=1" absent 1 "did not seal"
exit $fail
