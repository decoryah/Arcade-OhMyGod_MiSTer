#!/bin/bash
# run_states.sh <game> <frames> <name> [seed]: MAME state dumps of the scripted play into work/states/<name>
# e.g. run_states.sh ohmygod "60-6000/100" ohmygod 12345       (frame spec: see the header of tools/lua/dump_state.lua)
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
g=$1; frames=$2; name=$3; seed=${4:-12345}
D="$WORK/states/$name"; mkdir -p "$D"
cd "$WORK/mame"
export GAME=$g DUMPFRAMES="$frames" DUMPDIR="$(wpath "$D")" SEED=$seed
[ -n "$WRLOG" ] && export WRLOG="$(wpath "$D")/writes.log"
timeout 900 "$M" $g -rompath "$RP" -video none -sound none -nothrottle -skip_gameinfo -window \
  -cfg_directory "$CFG" -nvram_directory "$NVR" \
  -autoboot_script "$LUA" -seconds_to_run 900 2>&1 | grep -v "^PORT" | tail -n 3
