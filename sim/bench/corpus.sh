#!/bin/bash
# OMG_ROOT: the folder holding the repository (mister/) and the scratch folder work/ (MAME dumps, ROM images; not in the repository)
OMG_ROOT=${OMG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
cd $OMG_ROOT/mister
g=$1; shift
python3 tools/omg_corpus.py $OMG_ROOT/work/$g.rom "$@"
