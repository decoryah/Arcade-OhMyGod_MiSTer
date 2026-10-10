#!/bin/bash
# OMG_ROOT: the folder holding the repository (mister/) and the scratch folder work/ (MAME dumps, ROM images; not in the repository)
OMG_ROOT=${OMG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
# snd3.sh <game> <replay dir name> <t0> <t1>: native-rate samples of the RTL's OKI for the window of a replay_sr run
g=$1; name=$2; t0=$3; t1=$4
cd $OMG_ROOT/mister
R=$OMG_ROOT
dur=$(python3 -c "print($t1 - $t0)")
python3 tools/omg_oki_events.py $R/work/replay_sr/$name/writes.log $g $t0 $t1 > /tmp/snd3_$g.ev
SNDNATIVE=/tmp/snd3_$g.nat sim/run_snd.sh $R/work/$g.rom /tmp/snd3_$g.ev /tmp/snd3_$g.wav $dur 2>&1 | tail -3
wc -l /tmp/snd3_$g.nat
