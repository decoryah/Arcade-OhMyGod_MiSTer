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

**Tested on a real MiSTer** by the repository owner: the picture, the sound, the controls and the OSD options (20261010), and
the new features of 20261023 (fast loading, Scale, named buttons) and, in 20261023b, the Flip Screen of Naname de Magic!, which
did not flip in 20261023 and now does. 20261023b also removes Service and Test from the button mapping.

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
* The real MiSTer top (`sim/emu/`, with `hps_io` and the PLL stubbed): the image loaded the fast way in 0.135 s (every word in
  the SDRAM), the machine then run through the real 3 s cold start and compared with MAME (frames 230 and 280 of both games
  pixel-identical); the joysticks and the keyboard reach exactly their bits of the board's ports; the size
  asked of the HDMI scaler by all 60 Scale / Aspect ratio / scaler size combinations tried; the scandoubler's raster; CRT Adjust
  on at zero = off, to the clock.
* The Flip Screen DIP of Naname de Magic!: the game's own data (MAME does not emulate the hardware's flip) give MAME's normal
  picture exactly once the flip's fixed offsets are taken out; the core's flipped picture equals that picture turned 180 degrees on
  16 of 16 game states, in the reference renderer and in the RTL.
* Quartus Prime Lite 17.0 compiles the design without errors, timing met.

## Install

1. Put `releases/ohmygod_YYYYMMDD.rbf` in `/media/fat/_Arcade/cores/` and the two `.mra` files of `mra/` in `/media/fat/_Arcade/`
   (or unzip the release zip over the root of the SD card). Keep the RBF's `ohmygod_` name and date: MiSTer finds the core by
   the MRA's `<rbf>` name plus the date. Use the MRAs of the same release as the RBF, and delete older `ohmygod_*.rbf` files.
2. Put your MAME 0.289 `ohmygod.zip` and `naname.zip` in `/media/fat/games/mame/`.
3. Start a game from the Arcade menu. With a recent Main_MiSTer the 3.6 MB ROM image loads in a fraction of a second (**fast
   loading**: the MRAs carry `address="0x32000000"`, which makes Main_MiSTer copy the whole image into the DDR3 at once, and the
   core plays it from there into the SDRAM); an older Main_MiSTer ignores the attribute and streams the image as before, which
   takes a few seconds. **A cold start shows a grid-patterned / black screen for 3 seconds** before the ATLUS logo: the game
   fills its RAM, writes a signature and waits for the watchdog to reset it (MAME does the same, with the same 3 s). The OSD's
   Reset keeps the RAM, so the signature survives it and the game restarts without the wait.
4. **Buttons:** if you mapped the controller with an earlier build, redo "Define joystick buttons" (the list now names the game's
   action; the Service and Test entries of 20261023 are gone again), or delete this core's `*_input_*.map` files in
   `/media/fat/config/inputs/`.

## Controls

One joystick and one button per player, Start and Coin each. MiSTer's button mapping names them by what they do (the names
come from the MRA):

| Button | Oh My God! | Naname de Magic! | Default on a gamepad |
|---|---|---|---|
| first | **Drop**: the falling chain falls faster (it does what Down does, and nothing while the chain is swung sideways) | **Rotate**: turns the falling piece | A |
| Start, Coin | Start, Coin | the same | Start, Select |

The joystick moves the piece (in Oh My God! left / right swing the chain to that side). The keyboard has MAME's defaults: 1 / 2
start, 5 / 6 coin, **9 service** (a service credit, MAME's *Service 1*) and **F2 test** (the game's test menu, MAME's *Service
Mode*: monitor, switch and sound tests and the DIP switch list; in it the 1P Start button selects and F2 returns to the menu). The
two are separate switches on the board and the program treats them differently; they are keys only, not in the button mapping.

## OSD

* **Aspect ratio**, **Scandoubler Fx**: the framework's.
* **Scale**: Normal, V-Integer, HV-Integer, Narrower HV-Integer, HV-Integer+: integer scaling on the HDMI scaler (the framework's
  `video_freak`). With Aspect ratio *Full Screen* an integer Scale is given the screen's own proportions, so the picture is a
  whole-number size in the screen's aspect.
* **CRT Adjust** (H-Size, H-Position, V-Shift): for the 15 kHz output, through rmonic79's line buffer; the horizontal sync stays
  native so the CRT keeps its lock. It does nothing while the scandoubler is in use (Scandoubler Fx, or `forced_scandoubler` in
  MiSTer.ini).
* **DIP switches**: the MRA's, per game (coinage, difficulty, VS matches per credit, demo sounds, "Balls Have Eyes" / flip
  screen, test mode / freeze). Naname de Magic!'s **Flip Screen** turns the whole picture, tiles and sprites, through 180 degrees:
  the game then sets bit 14 of the sprite bank register (which MAME ignores, so MAME's picture of it is broken) and writes its
  scroll words and sprite positions moved by fixed amounts; taking those out gives MAME's normal picture exactly, and the core turns
  that picture (`docs/hardware.md`).
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

`sim/emu/run_emu.sh <image>` is the end-to-end bench of the real MiSTer top (`OhMyGod.sv`, with `hps_io` and the PLL stubbed and
a behavioural SDRAM and DDR3 on the pins): it loads the image streamed or the fast way (`FAST=1`), compares the SDRAM with the
image, checks how the joysticks and the keyboard reach the board's ports (`BTN=1`), the raster with the scandoubler on (`FX`,
`FSD`), CRT Adjust (`CRT`), the size asked of the HDMI scaler for every Scale / Aspect ratio setting (`SCALEMATRIX=1`), and
writes the pictures of chosen MAME frames (`PICS=230,280`) for `tools/omg_cmp.py`. Its header lists the options.

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
