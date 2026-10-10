#!/bin/bash
# OMG_ROOT: the folder holding the repository (mister/) and the scratch folder work/ (MAME dumps, ROM images; not in the repository)
OMG_ROOT=${OMG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
# sysbench.sh <game> <frames> [bench args]: the whole machine from reset, MAME's inputs replayed (absolute machine frames), vs
# MAME's dumps.  The RTL picture that ends at vertical blank N is MAME's frame N.
g=$1; n=$2; shift 2
cd $OMG_ROOT/mister
R=$OMG_ROOT
export BDIR=${BDIR:-$HOME/build_omg}
out=/tmp/sys_$g
rm -f $out.f*.ppm
frames=$(ls $R/work/replay/$g/f*.rgb | sed 's/.*f0*\([0-9]*\)\.rgb/\1/' | sort -n)
# save every MAME dump frame up to n
args=""
if ! sim/run.sh $R/work/$g.rom $n $out +inputs=$R/work/replay/$g/inputs.txt +first=${FIRST:-230} +every=50 "$@" > /tmp/sys_$g.log 2>&1; then echo "BENCH FAILED"; tail -30 /tmp/sys_$g.log; exit 2; fi
tail -3 /tmp/sys_$g.log
for ppm in $out.f*.ppm; do
  f=$(basename $ppm | sed 's/.*\.f0*\([0-9]*\)\.ppm/\1/')
  printf "RTL f%05d vs MAME f%05d: " $f $f
  python3 tools/omg_cmp.py $ppm $(printf "$R/work/replay/$g/f%05d.rgb" $f) | head -3 | tr '\n' ' '; echo
done
