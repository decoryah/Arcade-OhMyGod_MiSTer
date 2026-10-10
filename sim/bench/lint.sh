#!/bin/bash
# OMG_ROOT: the folder holding the repository (mister/) and the scratch folder work/ (MAME dumps, ROM images; not in the repository)
OMG_ROOT=${OMG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
cd $OMG_ROOT/mister/sim
verilator --lint-only -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-TIMESCALEMOD -Wno-UNUSEDPARAM \
  --top-module tb_top ../rtl/omg_ram.sv ../rtl/omg_cen.sv ../rtl/omg_cache.sv ../rtl/omg_main.sv ../rtl/omg_video.sv ../rtl/omg_render.sv \
  ../rtl/omg_sound.sv ../rtl/omg_core.sv ../rtl/omg_mem.sv ../rtl/sdram_ctrl.sv \
  ../modules/cpu-fx68k/fx68kAlu.sv ../modules/cpu-fx68k/uaddrPla.sv ../modules/cpu-fx68k/fx68k.sv \
  ../modules/jt6295/hdl/jt6295.v ../modules/jt6295/hdl/jt6295_adpcm.v ../modules/jt6295/hdl/jt6295_timing.v \
  ../modules/jt6295/hdl/jt6295_acc.v ../modules/jt6295/hdl/jt6295_ctrl.v ../modules/jt6295/hdl/jt6295_rom.v \
  ../modules/jt6295/hdl/jt6295_serial.v ../modules/jt6295/hdl/jt6295_sh_rst.v sdram_model.sv tb_top.sv 2>&1 \
  | grep -E "^%(Warning|Error)" | grep -E "omg_|tb_top" | sed 's|\.\./rtl/||' | head -60
