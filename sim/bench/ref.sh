#!/bin/bash
# OMG_ROOT: the folder holding the repository (mister/) and the scratch folder work/ (MAME dumps, ROM images; not in the repository)
OMG_ROOT=${OMG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
# ref.sh <game> <frame> [more frames...] : reference renderer vs MAME's own pixels
cd $OMG_ROOT/mister
g=$1; shift
for f in "$@"; do
  p=$(printf "$OMG_ROOT/work/states/%s/f%05d" $g $f)
  echo "frame $f:"
  python3 tools/omg_ref.py $OMG_ROOT/work/$g.rom $p $OMG_ROOT/work/states/$g/ref_$f.png
done
