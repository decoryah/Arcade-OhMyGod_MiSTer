# Status and measurements (2026-10-10)

The core has been on a real MiSTer: the owner found the picture, the sound, the controls and the OSD options right. Every number
below is from MAME 0.289 and Verilator / Quartus runs on the owner's machine (the scripts are in `sim/bench/`, the tools in `tools/`).

## ROM path

| check | result |
|---|---|
| `tools/omg_rom.py check` (the builder's regions vs MAME's loaded regions, `tools/lua/dump_regions.lua`) | ohmygod and naname: maincpu, chars, sprites, oki identical |
| `tools/mra_build.py` on `mra/*.mra` vs `omg_rom.py build` | both sets byte-identical (3,670,032 bytes) |

## Reference renderer (`tools/omg_ref.py`, MAME's `screen_update` literally)

`tools/omg_corpus.py`: 60 states per game, scripted play (coin 150, start 210, random joystick / button from 280, frames 60..5960 step 100):
**120 of 120 states pixel-identical to `screen:pixels()`** once the harness pairing is right (see below).
Sprite load seen: Oh My God! at most 179 entries touching the picture and 30 on one line (the title / intro scene), Naname de Magic!
142 / 26.

Harness findings (they cost an hour; `docs/hardware.md` has the short version):

* MAME's frame notifier runs *before* the screen update, so `screen:pixels()` there is the previous frame's picture. State dumped at
  callback N pairs with the pixels read at callback N + 1.
* `screen:pixels()` converts pen indexes to RGB with the palette *at the time of the call*, so a fade (the palette changes every
  frame) needs the palette of callback N + 1 (`f<N>.pal1`).
* A read tap on the input ports did not report every read, although the machine state was identical; inputs are logged from the
  script's own decisions with the lag measured once (a value set in notifier N is read during frame N + 1).

## The game's use of the sprite RAM (`tools/lua/bankuse.lua`, `ramwrites.lua`)

The write logs (`WRLOG` of `tools/lua/dump_state.lua`) count raster lines from the **start of vertical blank**: MAME's vblank
begins at line 240 of its 256-line frame and the IRQ comes with it, so the picture's own line is `(logged + 240) mod 256` (the logs
were first read as picture lines, which put every figure below 16 lines too late; found when the RTL's own picture disagreed).

Every frame, from the IRQ at the start of vertical blank, the game writes a complete list (1600 words = 400 sprites) into the
*hidden* sprite bank, then flips the bank flag: 46 line times after the start of vblank on Oh My God! (picture line 30 of the next
frame; the core's raster, with a 20-line vblank, puts it at line 29), 47 on one Naname scene (line 31) and 61 / 62 on the other
(lines 45 / 46). The bank displayed at the start of a frame is the other one. A chip that reads the flag live shows the previous
list above the flip line and the new one below it; MAME, drawing the frame at its end, shows the new list throughout. The core
has an OSD option (`Sprite bank flip`: *Live* default / *At vblank*) because the board's behaviour is not known.
Scroll registers are written at the IRQ (logged line 0, picture line 240) and sometimes 15 line times later; the palette RAM is
not written during play at all (colour fades are done through it only at scene changes); Naname updates tile RAM from
line time 51 to 161 after vblank start, i.e. picture lines 35..145.

What the option changes (`tools/omg_bank_effect.py`, the 60 MAME states per game, every pixel counted that differs from MAME's
picture of the frame): *At vblank* differs in 18 of Oh My God!'s and 35 of Naname's, typically ~1 % of the pixels, at most 13 %
(a scene change); *Live* in 7 (at most 1,111 px) and 10 to 18 (at most 206 to 641 px, for flip lines 30 / 44) -- only above the
flip line.  Through the whole RTL (`sim/bench/sysbench_sb.sh`, Oh My God! from reset with MAME's inputs): frame 580 *Live* 0 px,
*At vblank* 3,456 px; frame 680 *Live* 1,084 px (rows 1..28), *At vblank* 4,825 px -- the reference renderer with the flip at
line 29 gives exactly those numbers, so the option is wired as described.  *At vblank* also shows the sprites one frame behind
the scroll registers written at the same IRQ; *Live* keeps them together below the flip line, which is why it is the default.

## RTL, frozen states (`sim/bench/corpus_rtl.sh`)

The RTL's picture of each MAME state (RAMs and registers loaded, 68000 held in reset) against MAME's pixels, through the real
SDRAM controller and loader-less preloaded chip model:

* Oh My God!: **60 of 60 states pixel-identical** to MAME's pixels (frames 60..5960 of the scripted play, `sim/bench/corpus_rtl.sh`)
* Naname de Magic!: **60 of 60 states pixel-identical** (same frames, same script)

Line budget: the longest line render is 3,424 clocks of the 6,144 a line has (Oh My God!; Naname 3,267) (tile pass ~1,000,
sprite scan 1,024 + about 40 per hit; 30 sprites on the busiest line).

A bench pitfall that looked like an RTL bug for a while: the video registers are forced by DPI after elaboration, because an
`initial` block in the testbench raced with the RTL's own power-up values (the picture came out shifted by the 116-dot offset
that scroll 0 gives).

## Whole machine from reset (`sim/bench/sysbench.sh`)

**Cold start.** Both games begin with a routine that fills RAM (0x300000-0x30FFFF, sprite RAM ...) with a pattern, writes the
signature 0x12345678 at 0x703FFC and spins until the watchdog resets the machine; the warm boot then runs the game. With MAME's
3 s watchdog that is 180 frames of a black / grid picture (the tile RAM holds the fill pattern) before anything happens, on the
board as in MAME. The core's watchdog is 3 s too (288,000,000 clocks), so the RTL does the same.

**Harness consequence.** MAME re-runs the autoboot script at that reset, so a frame counter of the script restarts at 180. All
replay data is numbered by *machine frame* (the vertical blank that ends frame N: `tools/lua/dump_state.lua` derives it from the
machine time; the RTL bench names its pictures by its vertical-blank count), schedule: coin 330, start 390, random play 460.

**Result, Oh My God!** (`+fast`: the 3 s watchdog is shortened to ten frames until the first reset, and the picture numbering is
re-based to MAME's frame 180 at that reset; 115 frames, 185 million clocks, no line overran its budget, longest render 2,627
clocks): **frames 230 and 280 pixel-identical to MAME's** (0 of 76,800 pixels differ), with the inputs replayed from MAME's own log.

**Result, Naname de Magic!** (same run: 115 frames, no overruns, longest render 2,227 clocks): **frames 230 and 280
pixel-identical** (0 of 76,800 differ).

Only frames 230 and 280 are compared: those are what the fast cold-start run covers (a full 3 s start-up per game in
Verilator is ~25 minutes). Later frames are covered by the frozen-state corpus above (60 states per game, frames 60..5960,
through the same RTL), which includes the coin / start / play scenes; what the whole-machine runs add over it is the CPU, the
ROM cache and the power-up path, and those are exercised by the 230 / 280 frames reaching MAME's picture.

## Sound (`sim/bench/snd.sh`, `sim/bench/snd3.sh`, `tools/omg_oki_fit.py`)

MAME's own OKI writes (machine time, bank changes included) replayed into the RTL's sound path (`jt6295` plus the 68000-side
write / ROM bank logic, SDRAM model, no CPU), against the recording MAME made in the same run.

| check | result |
|---|---|
| level, Oh My God! and Naname | MAME's output = exactly **16 x** the core's 14-bit sum of voices (clipped to 16 bit). The top level applies x16 with saturation at *Normal* |
| envelope, 0.5 s windows, 48 kHz recording | correlation 1.000 (Oh My God!) / 0.999 (Naname) |
| **sample for sample**, Oh My God! 5.4..8.5 s (7 writes) and Naname 12.5..15.5 s (4 writes) | MAME recorded at 500 kHz (`-samplerate 500000`: 33 x the chip's rate, so no band-limiting is applied to the chip's samples); fitting MAME's stream as a 7-tap FIR of the RTL's native samples x 16 leaves **0.008 % (Oh My God!) / 0.015 % (Naname) of the signal rms**; tap sum 0.9999 |

Findings of that check that look like mismatches in a 48 kHz recording but are not:

* MAME's OKI runs at **15151 Hz**, the integer-truncated 2,000,000 / 132 (stream rates are integers), 34 ppm slower than the
  chip's real 15151.515 Hz, which is what the core does. Over a 3 s window MAME drifts by ~100 us against a clock-exact model,
  and a fit that ignores it leaves a 30 % residual.
* MAME's resampler to 48 kHz is a smoothing interpolation; the core's output at 48 kHz is the chip's sample-and-hold (what the
  board's DAC does between samples). The rms of the two differs by ~3 % (-23.8 dB instead of -24.0) for that reason alone.

## Build (Quartus Prime Lite 17.0.2, `quartus_sh --flow compile OhMyGod`, 32 min)

| | |
|---|---|
| ALMs | 11,505 / 41,910 (27 %) |
| registers | 17,131 |
| block memory | 1,747,533 bits, 232 / 553 RAM blocks (42 %) |
| DSP | 34 / 112 (fx68k) |
| PLLs | 3 / 6 |
| setup slack, core clock (96 MHz) | +1.414 ns; the framework's HDMI clock +0.461 ns; all hold slacks > 0.24 ns |
| `tools/check_ram_depth.py` | 0 problems (every memory built as deep as the RTL declares it) |

`releases/ohmygod_20261010.rbf` is that build.
