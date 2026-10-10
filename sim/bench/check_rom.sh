#!/bin/bash
# OMG_ROOT: the folder holding the repository (mister/) and the scratch folder work/ (MAME dumps, ROM images; not in the repository)
OMG_ROOT=${OMG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
cd $OMG_ROOT/mister
Z=${ROM_DIR:-"/mnt/r/Games/Arcade/MAME 0.289 ROMs (merged)"}   # the folder with ohmygod.zip / naname.zip
for g in ohmygod naname; do
  echo "== $g"
  python3 tools/omg_rom.py check $g "$Z/$g.zip" $OMG_ROOT/work/regions/$g
  python3 tools/omg_rom.py build $g "$Z/$g.zip" $OMG_ROOT/work/$g.rom
done
