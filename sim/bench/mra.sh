#!/bin/bash
# OMG_ROOT: the folder holding the repository (mister/) and the scratch folder work/ (MAME dumps, ROM images; not in the repository)
OMG_ROOT=${OMG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
cd $OMG_ROOT/mister
python3 tools/make_mra.py
Z=${ROM_DIR:-"/mnt/r/Games/Arcade/MAME 0.289 ROMs (merged)"}   # the folder with ohmygod.zip / naname.zip
for p in "ohmygod:Oh My God! (Japan)" "naname:Naname de Magic! (Japan)"; do
  g=${p%%:*}; t=${p#*:}
  python3 tools/mra_build.py "mra/$t.mra" "$Z/$g.zip" /tmp/$g.mra.rom
  cmp /tmp/$g.mra.rom $OMG_ROOT/work/$g.rom && echo "$g: MRA image == omg_rom.py image"
done
