#!/bin/bash
# run_replay.sh <game> <frames> <name> [seed]: MAME state dumps (absolute machine frames), the inputs it played (inputs.txt),
# the control / OKI / sprite bank writes (writes.log) and MAME's audio (mame.wav) into work/replay/<name>: what the whole-machine
# bench (sysbench.sh) and the sound bench (snd.sh) replay.   e.g. run_replay.sh ohmygod "230-1230/50" ohmygod
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
g=$1; frames=$2; name=$3; seed=${4:-12345}
D="$WORK/replay/$name"; mkdir -p "$D"
cd "$WORK/mame"
export GAME=$g DUMPFRAMES="$frames" DUMPDIR="$(wpath "$D")" SEED=$seed INPUTLOG="$(wpath "$D")/inputs.txt" WRLOG="$(wpath "$D")/writes.log"
timeout 900 "$M" $g -rompath "$RP" -video none -sound none -nothrottle -skip_gameinfo -window \
  -cfg_directory "$CFG" -nvram_directory "$NVR" \
  -wavwrite "$(cygpath -w "$D/mame.wav")" \
  -autoboot_script "$LUA" -seconds_to_run 900 2>&1 | grep -v "^PORT" | tail -n 2
