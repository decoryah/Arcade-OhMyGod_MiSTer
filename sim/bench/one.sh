#!/bin/bash
# OMG_ROOT: the folder holding the repository (mister/) and the scratch folder work/ (MAME dumps, ROM images; not in the repository)
OMG_ROOT=${OMG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
# one.sh <game> <frame>: one frozen-state run with full output
g=$1; f=$2
cd $OMG_ROOT/mister
R=$OMG_ROOT
p=$(printf "$R/work/states/$g/f%05d" $f)
sim/run.sh $R/work/$g.rom 3 /tmp/fb_${g}_$f +state=$p +first=3 +every=100
python3 tools/omg_cmp.py /tmp/fb_${g}_$f.f00003.ppm $p.rgb
head -c 300 $p.regs
