#!/bin/bash
# run_sr.sh <game> <name> <samplerate> [seed]: the scripted run of run_replay.sh with MAME's audio recorded at <samplerate>
# into work/replay_sr/<name>/mame.wav.  500000 Hz is 33 x the OKI's own rate: MAME's resampler then hands out the chip's samples
# with a smooth curve between them, which tools/omg_oki_fit.py compares with the RTL's, sample for sample.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
g=$1; name=$2; sr=$3; seed=${4:-12345}
D="$WORK/replay_sr/$name"; mkdir -p "$D"
cd "$WORK/mame"
export GAME=$g DUMPFRAMES="230-1000/770" DUMPDIR="$(wpath "$D")" SEED=$seed INPUTLOG="$(wpath "$D")/inputs.txt" WRLOG="$(wpath "$D")/writes.log"
timeout 900 "$M" $g -rompath "$RP" -video none -sound none -nothrottle -skip_gameinfo -window \
  -cfg_directory "$CFG" -nvram_directory "$NVR" \
  -samplerate $sr -wavwrite "$(cygpath -w "$D/mame.wav")" \
  -autoboot_script "$LUA" -seconds_to_run 900 2>&1 | grep -v "^PORT" | tail -n 2
