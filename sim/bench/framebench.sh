#!/bin/bash
# OMG_ROOT: the folder holding the repository (mister/) and the scratch folder work/ (MAME dumps, ROM images; not in the repository)
OMG_ROOT=${OMG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
# framebench.sh <game> <frame> [frame...]: the RTL's picture of MAME's frozen state vs MAME's own pixels
# (NOBUILD=1 to reuse the Verilator build).  Extra bench arguments in $BENCHARGS.
g=$1; shift
cd $OMG_ROOT/mister
R=$OMG_ROOT
fail=0
for f in "$@"; do
  p=$(printf "$R/work/states/$g/f%05d" $f)
  if ! sim/run.sh $R/work/$g.rom 3 /tmp/fb_${g}_$f +state=$p +first=3 +every=100 $BENCHARGS > /tmp/fb_run.log 2>&1; then
    echo "BENCH FAILED:"; tail -30 /tmp/fb_run.log; exit 2
  fi
  grep -E "RDBG|state of|longest" /tmp/fb_run.log | tail -${TAILN:-3}
  python3 tools/omg_cmp.py /tmp/fb_${g}_$f.f00003.ppm $p.rgb $R/work/states/$g/rtl_diff_$f.png || fail=1
  export NOBUILD=1
done
exit $fail
