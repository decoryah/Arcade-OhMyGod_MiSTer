#!/bin/bash
# OMG_ROOT: the folder holding the repository (mister/) and the scratch folder work/ (MAME dumps, ROM images; not in the repository)
OMG_ROOT=${OMG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
# corpus_rtl.sh <game> : every frozen state of work/states/<game> through the RTL, vs MAME's pixels
g=$1
cd $OMG_ROOT/mister
R=$OMG_ROOT
export NOBUILD=1
ok=0; bad=0; worst=0
for regs in $R/work/states/$g/f*.regs; do
  p=${regs%.regs}; n=$(basename $p)
  sim/run.sh $R/work/$g.rom 3 /tmp/cr_$g +state=$p +first=3 +every=100 > /tmp/cr_run.log 2>&1 || { echo "BENCH FAILED"; tail /tmp/cr_run.log; exit 2; }
  r=$(grep -oE "longest render [0-9]+" /tmp/cr_run.log | tail -1 | grep -oE "[0-9]+")
  [ -n "$r" ] && [ "$r" -gt "$worst" ] && worst=$r
  out=$(python3 tools/omg_cmp.py /tmp/cr_$g.f00003.ppm $p.rgb | head -1)
  case "$out" in *": 0 of"*) ok=$((ok+1));; *) bad=$((bad+1)); echo "$n: $out";; esac
done
echo "$g: $ok identical, $bad different; longest line render $worst clocks (of 6144)"
