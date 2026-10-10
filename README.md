# Oh My God! / Naname de Magic! (Atlus) for MiSTer

Atlus' **Oh My God!** (1993) and **Naname de Magic!** (1994), the two games of MAME's `atlus/ohmygod.cpp` driver (68000 at 12 MHz,
one OKI M6295, one 64 x 64 tile layer and 1024 sprites), for the MiSTer FPGA platform.

Written for MiSTer from MAME 0.289's driver. The 68000 is [fx68k](https://github.com/ijor/fx68k) (Jorge Cwik), the OKI M6295 is
[jt6295](https://github.com/jotego/jt6295) (Jose Tejada), the CRT Adjust page is rmonic79's
[MiSTer-CRT-Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust). The platform layer (SDRAM controller, loader, program cache)
is the owner's, from the MCatAdv and Metro cores; the SDRAM controller descends from the Gaiapolis core that **plasticbugs** wrote
for the Analogue Pocket (`rtl/UPSTREAM.md`, `modules/VENDOR.md`). No ROMs or other copyrighted data are in this repository; you
supply your own MAME romsets.

## Status

**Tested on a real MiSTer** by the repository owner: the picture, the sound, the controls and the OSD options all behave
as they should.

What was checked besides, in simulation and in the Quartus tool flow, against MAME 0.289 (details and numbers in
`docs/status.md`):

* The ROM path: both sets' images are byte-identical to the regions MAME loaded (`tools/omg_rom.py check`), and the MRAs
  assemble to the same images (`tools/mra_build.py`).
* The video, against a reference renderer (`tools/omg_ref.py`) that is MAME's `screen_update` written out literally: pixel-exact
  on 120 MAME frames of scripted play (both games), including the busiest frames (179 sprites on screen); the RTL's frozen-state
  bench (`sim/bench/corpus_rtl.sh`) against the same MAME pixels: 60 of 60 states per game identical.
* The whole machine from reset (68000, cache, SDRAM controller, cold-start watchdog reset) with MAME's inputs replayed: frames
  230 and 280 of both games pixel-identical.
* The sound path against MAME's own OKI samples: same samples, MAME's level (x16), residual 0.01 %.
* Quartus Prime Lite 17.0 compiles the design without errors; timing met (+1.4 ns at 96 MHz), 27 % of the ALMs.

## Install

1. Put `releases/ohmygod_YYYYMMDD.rbf` in `/media/fat/_Arcade/cores/` and the two `.mra` files of `mra/` in `/media/fat/_Arcade/`.
   Keep the RBF's `ohmygod_` name and date: MiSTer finds the core by the MRA's `<rbf>` name plus the date.
2. Put your MAME 0.289 `ohmygod.zip` and `naname.zip` in `/media/fat/games/mame/`.
3. Start a game from the Arcade menu. The ROM takes a few seconds to load. **A cold start shows a grid-patterned / black screen
   for 3 seconds** before the ATLUS logo: the game fills its RAM, writes a signature and waits for the watchdog to reset it
   (MAME does the same, with the same 3 s). The OSD's Reset keeps the RAM, so the signature survives it and the game
   restarts without the wait.

## Controls

One joystick, one button per player; the keyboard has MAME's defaults (1 / 2 start, 5 / 6 coin, 9 service).
The OSD's `Button, Start, Coin, Service` follow the MRA's `<buttons>`.

## OSD

* **Aspect ratio**, **Scandoubler Fx**: the framework's.
* **CRT Adjust** (H-Size, H-Position, V-Shift): for the 15 kHz output, through rmonic79's line buffer; the horizontal sync stays
  native so the CRT keeps its lock.
* **DIP switches**: the MRA's, per game (coinage, difficulty, VS matches per credit, demo sounds, "Balls Have Eyes" / flip
  screen, test mode / freeze).
* **Volume**: Normal is MAME's level (the OKI's output is exactly 16 times jt6295's 14-bit sum of voices, clipped to 16 bits; fitted against MAME's own samples, residual 0.01 %), then 6 / 12 / 18 dB lower.
* **Sprite bank flip**: from the IRQ at the start of vertical blank the game builds the next sprite list into the hidden half
  of the sprite RAM and flips the bank flag about 46 line times later, i.e. at line ~30 of the picture (Naname: 31, or 45 / 46 in
  some scenes) *while the picture is being drawn*. *Live* (default) lets the flag act at once, as a chip that reads it live
  would: the previous list above the flip line, the new one below it (so the sprites are in step with the scroll registers the
  game writes at the same IRQ). *At vblank* samples the flag at the start of vertical blanking: the whole next frame shows the
  previous frame's list. MAME, drawing a frame at its end, shows the new list throughout. The two differ by one frame (16.7 ms)
  of sprite timing and are hard to tell apart by eye; the board's real behaviour is not known. On MAME's own states
  (`tools/omg_bank_effect.py`) *At vblank* differs from MAME's picture in 18 of 60 sampled frames of Oh My God! and 35 of
  Naname de Magic! (typically about 1 % of the pixels, only while sprites move; at most 13 %, on a scene change), *Live* in 7
  and 10 to 18 (at most 1,111 px; only in the lines above the flip).
* **SDRAM read capture**: a diagnostic for SDRAM modules that answer late.

## Timing

96 MHz machine clock; 68000 12 MHz (/8), OKI 2 MHz (/48), dot clock 6 MHz (/16); 384 x 260 total, 320 x 240 visible, 60.096 Hz,
15.625 kHz. MAME's own totals are 512 x 256 at exactly 60 Hz; the board's real timing is not known.

## Build

Quartus Prime Lite 17.0 (MiSTer's toolchain): open `OhMyGod.qpf` or `quartus_sh --flow compile OhMyGod`. The MRAs are written by
`python tools/make_mra.py`.

## Simulation (Verilator 5 in WSL)

```
sim/run.sh <image> <frames> <out> +state=<MAME state prefix> +first=2          # one frozen state, vs MAME's pixels
sim/run.sh <image> <frames> <out> +inputs=<replay> +every=50 +first=49 +wav    # the whole machine from reset
```
`tools/lua/dump_state.lua` makes the states and the replay inputs with MAME 0.289 (see its header); `tools/omg_ref.py`,
`tools/omg_diff.py`, `tools/omg_corpus.py`, `tools/omg_cmp.py` compare.

`sim/bench/` holds the scripts that run the whole chain: MAME's dumps (`mame/run_states.sh`, `run_replay.sh`, `run_sr.sh`; set
`MAME_EXE` and `ROM_PATH`), the ROM check (`check_rom.sh`, `mra.sh`; `ROM_DIR` is the romset folder), the reference renderer (`ref.sh`, `corpus.sh`), the RTL's
frozen-state corpus (`corpus_rtl.sh`), the whole machine from reset (`sysbench.sh`, `sysbench_sb.sh` for the sprite bank
option) and the sound (`snd.sh`, `snd3.sh`, with `tools/omg_oki_fit.py`). They expect a scratch folder `work/` next to the
repository (MAME's dumps and the ROM images; never committed).

## Release

`python tools/release.py` copies a finished build into `releases/` with its fitter / timing / RAM-depth reports;
`python tools/package.py` writes `dist/OhMyGod_MiSTer_<date>.zip` (the SD card structure: `_Arcade/*.mra`, `_Arcade/cores/*.rbf`;
no ROMs).

## Credits

fx68k (Jorge Cwik), jt6295 (Jose Tejada), MiSTer-CRT-Adjust (rmonic79), the Pocket Gaiapolis core's SDRAM controller
(plasticbugs), the MiSTer framework (Sorgelig and contributors), MAME (Nicola Salmoria wrote the Atlus driver).

## Licence

GPL-3.0-or-later (fx68k and jt6295 are GPL-3.0).
