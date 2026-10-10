#!/bin/bash
# Whole-machine / frozen-state bench (sim/tb_top.sv, sim/tb_main.cpp):
#   sim/run.sh <game.rom> <frames> <out-prefix> [bench arguments: +state=<prefix> +load=rtl +every=N +first=N +inputs=F +coin=N +trace +wav ...]
# Writes <out-prefix>.fNNNN.ppm (+ .wav, .trace).  Build directory: $HOME/build_omg (NOBUILD=1 reuses it).
set -e
cd "$(dirname "$0")"
ROM="$1"; FRAMES="${2:-3}"; OUT="$3"; shift 3 || true
[ -f "$ROM" ] || { echo "usage: $0 <game.rom> <frames> <out-prefix> [args]" >&2; exit 2; }
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
B="${BDIR:-$HOME/build_omg}"; mkdir -p "$B"
if [ -z "$NOBUILD" ]; then
verilator --cc --exe --build -j 8 -O3 --x-assign fast --x-initial fast -CFLAGS "-O3 -march=native" --public-flat-rw \
    -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-WIDTH -Wno-CASEINCOMPLETE \
    -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-INITIALDLY -Wno-UNDRIVEN -Wno-SYNCASYNCNET -Wno-MULTIDRIVEN -Wno-LATCH -Wno-BLKSEQ \
    -Wno-UNSIGNED -Wno-CMPCONST -Wno-VARHIDDEN -Wno-BLKANDNBLK --no-assert-case -Wno-PROCASSINIT -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
    $VFLAGS --top-module tb_top -Mdir "$B/obj" \
    ../rtl/omg_ram.sv ../rtl/omg_cen.sv ../rtl/omg_cache.sv ../rtl/omg_main.sv ../rtl/omg_video.sv ../rtl/omg_render.sv \
    ../rtl/omg_sound.sv ../rtl/omg_core.sv ../rtl/omg_mem.sv ../rtl/sdram_ctrl.sv \
    ../modules/cpu-fx68k/fx68kAlu.sv ../modules/cpu-fx68k/uaddrPla.sv ../modules/cpu-fx68k/fx68k.sv \
    ../modules/jt6295/hdl/jt6295.v ../modules/jt6295/hdl/jt6295_adpcm.v ../modules/jt6295/hdl/jt6295_timing.v \
    ../modules/jt6295/hdl/jt6295_acc.v ../modules/jt6295/hdl/jt6295_ctrl.v ../modules/jt6295/hdl/jt6295_rom.v \
    ../modules/jt6295/hdl/jt6295_serial.v ../modules/jt6295/hdl/jt6295_sh_rst.v \
    sdram_model.sv tb_top.sv tb_main.cpp > "$B/build.log" 2>&1 || { grep -E "%Error|error:" "$B/build.log" | head -40; exit 1; }
fi
cp ../microrom.mem ../nanorom.mem "$B/"
cd "$B"
./obj/Vtb_top "$ROM" "$FRAMES" "$OUT" "$@"
