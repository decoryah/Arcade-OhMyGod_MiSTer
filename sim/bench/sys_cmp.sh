#!/bin/bash
# OMG_ROOT: the folder holding the repository (mister/) and the scratch folder work/ (MAME dumps, ROM images; not in the repository)
OMG_ROOT=${OMG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
# sys_cmp.sh <game>: the whole-machine frames written so far vs MAME's frames (same absolute number)
g=$1
cd $OMG_ROOT/mister
R=$OMG_ROOT
for ppm in /tmp/sys_$g.f*.ppm; do
  f=$(basename $ppm | sed 's/.*\.f0*\([0-9]*\)\.ppm/\1/')
  printf "RTL f%05d vs MAME f%05d: " $f $f
  python3 tools/omg_cmp.py $ppm $(printf "$R/work/replay/$g/f%05d.rgb" $f) | head -3 | tr '\n' ' '; echo
done
