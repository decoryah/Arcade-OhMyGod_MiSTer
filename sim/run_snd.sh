#!/bin/bash
# OKI bench: sim/run_snd.sh <image> <events> <out.wav> [seconds]   (build directory $HOME/build_omg_snd; NOBUILD=1 reuses it)
set -e
cd "$(dirname "$0")"
IMG="$1"; EV="$2"; OUT="$3"; SEC="${4:-10}"
case "$IMG" in /*) ;; *) IMG="$PWD/$IMG" ;; esac
case "$EV"  in /*) ;; *) EV="$PWD/$EV" ;; esac
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
B="${BDIR:-$HOME/build_omg_snd}"; mkdir -p "$B"
if [ -z "$NOBUILD" ]; then
verilator --cc --exe --build -j 4 -O3 --x-assign fast --x-initial fast -CFLAGS "-O3 -march=native" --public-flat-rw \
    -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-WIDTH -Wno-CASEINCOMPLETE \
    -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-INITIALDLY -Wno-UNDRIVEN -Wno-SYNCASYNCNET -Wno-MULTIDRIVEN -Wno-LATCH -Wno-BLKSEQ \
    -Wno-UNSIGNED -Wno-CMPCONST -Wno-VARHIDDEN -Wno-BLKANDNBLK --no-assert-case -Wno-PROCASSINIT -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
    --top-module tb_snd_top -Mdir "$B/obj" \
    ../rtl/omg_cen.sv ../rtl/omg_sound.sv ../rtl/omg_mem.sv ../rtl/sdram_ctrl.sv ../rtl/omg_ram.sv \
    ../modules/jt6295/hdl/jt6295.v ../modules/jt6295/hdl/jt6295_adpcm.v ../modules/jt6295/hdl/jt6295_timing.v \
    ../modules/jt6295/hdl/jt6295_acc.v ../modules/jt6295/hdl/jt6295_ctrl.v ../modules/jt6295/hdl/jt6295_rom.v \
    ../modules/jt6295/hdl/jt6295_serial.v ../modules/jt6295/hdl/jt6295_sh_rst.v \
    sdram_model.sv tb_snd_top.sv tb_snd.cpp > "$B/build.log" 2>&1 || { grep -E "%Error|error:" "$B/build.log" | head -30; exit 1; }
fi
"$B/obj/Vtb_snd_top" "$IMG" "$EV" "$OUT" "$SEC"
