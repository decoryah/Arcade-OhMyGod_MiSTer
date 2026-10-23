#!/bin/bash
# End-to-end bench of the MiSTer top level (OhMyGod.sv): hps_io and the PLL stubbed, everything else real (the framework's video
# path, the SDRAM controller, the loader, the fast load, the machine), with a behavioural SDRAM and DDR3 on the pins.
#   sim/emu/run_emu.sh <image> [frames after load, default 6] [out prefix]
# Environment (all optional):
#   FAST=1       load the way Main_MiSTer does for address= on the MRA (image in the DDR3, a download that carries only its length)
#   BTN=1        print / check the input wiring table (joysticks, keyboard -> the board's P1 / P2 bits)
#   FX=0..4      Scandoubler Fx (None, HQ2x, CRT 25 / 50 / 75 %);  FSD=1  the framework's forced_scandoubler (MiSTer.ini)
#   CRT=1        CRT Adjust on;  HSIZE (-16..5), HPOS (-16..16) and VSHIFT (-12..3) set its amounts as the OSD counts them
#   SCALE=0..4   Scale (Normal, V-Integer, HV-Integer, Narrower HV-Integer, HV-Integer+);  AR=0..3  Aspect ratio
#   HW / HH      the HDMI scaler's size (default 1920 x 1080)
#   SBL=1        Sprite bank flip: At vblank
#   PICS=230,280 write the pictures of those MAME machine frames (needs a run of at least ~300 frames: the cold start's 3 s)
# The image is work/<game>.rom (tools/omg_rom.py build, or tools/mra_build.py on a mra/*.mra; 0x380010 bytes).
set -e
cd "$(dirname "$0")"
IMG="$1"; FR="${2:-6}"; PRE="${3:-emu}"
[ -f "$IMG" ] || { echo "usage: $0 <image> [frames] [prefix]" >&2; exit 2; }
case "$IMG" in /*) ;; *) IMG="$PWD/$IMG" ;; esac
case "$PRE" in /*) ;; *) PRE="$PWD/$PRE" ;; esac
export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
S=../../sys
OBJ="${BDIR:-$HOME/build_omg_emu}"
mkdir -p "$OBJ"
# OhMyGod.sv includes build_id.v, which Quartus' pre-flow script writes (and git ignores): the bench writes its own
printf '`define BUILD_DATE " 000000"\n' > "$OBJ/build_id.v"
# The framework's video_mixer.sv declares R_in/G_in/B_in inside an unnamed generate block and uses them outside it.  Quartus accepts
# that (every MiSTer core builds with it); Verilator takes them for undeclared implicit wires nothing drives, and the picture comes out
# black.  The bench builds a copy with the three wires declared at module level (for GAMMA=1, HALF_DEPTH=0 -- arcade_video with
# DW=24): sys/ is untouched.
python3 - $S/video_mixer.sv "$OBJ/video_mixer_sim.sv" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'generate\s+if\(GAMMA && HALF_DEPTH\) begin.*?end else begin(.*?)end\s+endgenerate', s, re.S)
assert m, 'video_mixer.sv: the R_in generate block was not found'
open(sys.argv[2], 'w').write(s[:m.start()] + m.group(1).strip() + chr(10) + s[m.end():])
PY
if [ -z "$NOBUILD" ]; then
verilator --cc --exe --build -j ${JOBS:-8} -O2 --x-assign fast --x-initial fast --public-flat-rw --no-assert-case \
    -Wno-fatal -Wno-WIDTH -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PINCONNECTEMPTY -Wno-IMPLICIT -Wno-TIMESCALEMOD \
    -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-LATCH -Wno-UNSIGNED -Wno-CMPCONST -Wno-PROCASSWIRE -Wno-BLKANDNBLK -Wno-INITIALDLY \
    -Wno-UNDRIVEN -Wno-SYNCASYNCNET -Wno-BLKSEQ -Wno-VARHIDDEN -Wno-PROCASSINIT -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
    +1364-2005ext+v -I"$OBJ" -I. -I../.. --top-module tb_emu_top --prefix Vtb_emu_top -Mdir "$OBJ/obj" \
    ../../OhMyGod.sv ../../rtl/omg_ram.sv ../../rtl/omg_cen.sv ../../rtl/omg_cache.sv ../../rtl/omg_main.sv ../../rtl/omg_video.sv \
    ../../rtl/omg_render.sv ../../rtl/omg_sound.sv ../../rtl/omg_core.sv ../../rtl/omg_crtadj.sv ../../rtl/omg_mem.sv \
    ../../rtl/omg_fastload.sv ../../rtl/sdram_ctrl.sv ../../modules/crt_adjust/crt_adjust.sv \
    ../../modules/cpu-fx68k/fx68kAlu.sv ../../modules/cpu-fx68k/uaddrPla.sv ../../modules/cpu-fx68k/fx68k.sv \
    ../../modules/jt6295/hdl/jt6295.v ../../modules/jt6295/hdl/jt6295_adpcm.v ../../modules/jt6295/hdl/jt6295_timing.v \
    ../../modules/jt6295/hdl/jt6295_acc.v ../../modules/jt6295/hdl/jt6295_ctrl.v ../../modules/jt6295/hdl/jt6295_rom.v \
    ../../modules/jt6295/hdl/jt6295_serial.v ../../modules/jt6295/hdl/jt6295_sh_rst.v \
    $S/arcade_video.v "$OBJ/video_mixer_sim.sv" $S/scandoubler.v $S/scanlines.v $S/gamma_corr.sv $S/hq2x.sv $S/video_freezer.sv $S/video_freak.sv $S/math.sv \
    hps_io_stub.sv pll_stub.sv sync_fix.sv ../sdram_model.sv ../ddr_model.sv tb_emu_top.sv tb_emu.cpp \
    > "$OBJ/build.log" 2>&1 || { grep -E "%Error" "$OBJ/build.log" | head -30; tail -n 5 "$OBJ/build.log"; exit 1; }
fi
# the 68000's microcode ROMs are read with $readmemb relative to the working directory (as Quartus does from the project directory)
cd ../..
stdbuf -oL "$OBJ/obj/Vtb_emu_top" "$IMG" "$FR" "$PRE"
