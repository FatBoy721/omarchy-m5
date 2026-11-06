#!/bin/sh
# usage: run.sh <tree>   (tree = codex-tier2-kbd/src)
set -e
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT; h=$(dirname "$0")
sed -n '/M5_VERDICT_BEGIN/,/M5_VERDICT_END/p' "$1/drivers/soc/apple/m5_kbdlight.c" > "$d/verdict.inc"
sed -n '/M5_TOK_BEGIN/,/M5_TOK_END/p' "$1/drivers/pmdomain/apple/pmgr-pwrstate.c" > "$d/token.inc"
for t in verdict token; do cc -Wall -Werror -I"$d" -o "$d/$t" "$h/$t-test.c"; "$d/$t" | tail -1; done
