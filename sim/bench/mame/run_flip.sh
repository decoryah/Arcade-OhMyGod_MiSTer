#!/bin/bash
# run_flip.sh <game> <name> <frames> <actions> [dipset]: MAME state dumps with scripted inputs (tools/lua/dump_state.lua SCHEDULE=actions) and DIP
# switches set (DIPSET), into work/flip/<name>; its own cfg folder, because MAME saves the DIP settings on exit and would carry them into the next run
#   e.g. A="330:coin:6,400:start:8,470:start:8,540:start:8,610:start:8,680:start:8,700:b1:4,790:b1:4,880:b1:4,970:b1:4,1060:b1:4"
#        run_flip.sh naname off "1000-1300/20" "$A"
#        run_flip.sh naname on  "1000-1300/20" "$A" ":DSW2|Flip Screen|0"      then: python tools/omg_flipstates.py
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
g=$1; name=$2; frames=$3; actions=$4; dip=$5
D="$WORK/flip/$name"
rm -rf "$D"; mkdir -p "$D"
CFGD="$WORK/mame/cfg_$name"; rm -rf "$CFGD"; mkdir -p "$CFGD"
cd "$WORK/mame"
export GAME=$g DUMPFRAMES="$frames" DUMPDIR="$(wpath "$D")" SEED=1 SCHEDULE=actions ACTIONS="$actions" DIPSET="$dip" WRLOG="$(wpath "$D")/writes.log"
timeout 900 "$M" $g -rompath "$RP" -video none -sound none -nothrottle -skip_gameinfo -window \
  -cfg_directory "$(cygpath -w "$CFGD")" -nvram_directory "$NVR" \
  -autoboot_script "$LUA" -seconds_to_run 900 2>&1 | grep -v "^PORT" | tail -n 2
