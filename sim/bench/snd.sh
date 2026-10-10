#!/bin/bash
# OMG_ROOT: the folder holding the repository (mister/) and the scratch folder work/ (MAME dumps, ROM images; not in the repository)
OMG_ROOT=${OMG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
# snd.sh <game> <t_start s> <t_end s>: MAME's OKI writes of that machine-time window replayed into the RTL's sound path;
# compared with MAME's recording of the same window
g=$1; t0=$2; t1=$3
cd $OMG_ROOT/mister
R=$OMG_ROOT
dur=$(python3 -c "print($t1 - $t0)")
python3 tools/omg_oki_events.py $R/work/replay/$g/writes.log $g $t0 $t1 > /tmp/snd_$g.ev
sim/run_snd.sh $R/work/$g.rom /tmp/snd_$g.ev /tmp/snd_$g.wav $dur
python3 tools/wav_slice.py $R/work/replay/$g/mame.wav /tmp/snd_$g.mame.wav $t0 $t1
python3 tools/cmp_audio.py /tmp/snd_$g.wav /tmp/snd_$g.mame.wav $dur | head -60
