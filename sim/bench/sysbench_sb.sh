#!/bin/bash
# OMG_ROOT: the folder holding the repository (mister/) and the scratch folder work/ (MAME dumps, ROM images; not in the repository)
OMG_ROOT=${OMG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
# sysbench_sb.sh <game> <frames> <live|vbl> <first> <every>: whole machine from reset (+fast), sprite bank flip option as given,
# pictures vs MAME's dumps; output /tmp/sbsys_<game>_<mode>.*
g=$1; n=$2; mode=$3; first=$4; every=$5
cd $OMG_ROOT/mister
R=$OMG_ROOT
export BDIR=${BDIR:-$HOME/build_omg3}
out=/tmp/sbsys_${g}_$mode
rm -f $out.f*.ppm
opt=""
[ "$mode" = vbl ] && opt="+sblatch"
sim/run.sh $R/work/$g.rom $n $out +inputs=$R/work/replay/$g/inputs.txt +first=$first +every=$every +fast $opt > $out.log 2>&1 || { echo "BENCH FAILED"; tail -n 30 $out.log; exit 2; }
tail -n 3 $out.log
for ppm in $out.f*.ppm; do
  f=$(basename $ppm | sed 's/.*\.f0*\([0-9]*\)\.ppm/\1/')
  printf "RTL[%s] f%05d vs MAME f%05d: " $mode $f $f
  python3 tools/omg_cmp.py $ppm $(printf "$R/work/replay/$g/f%05d.rgb" $f) | head -n 3 | tr '\n' ' '; echo
done
