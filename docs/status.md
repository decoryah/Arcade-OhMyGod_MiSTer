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

## The MiSTer top level (`sim/emu/`, 20261023)

`sim/emu/run_emu.sh` builds the real top (`OhMyGod.sv`: the framework's `arcade_video` / `video_mixer` / scandoubler / `video_freak`,
the SDRAM controller, the loader, the machine) with `hps_io` and the PLL stubbed and a behavioural SDRAM and Avalon DDR3 on the pins,
and plays the HPS: it loads the image, presses buttons and keys, sets OSD options and captures the picture as the scaler gets it.

| check | result |
|---|---|
| **Fast loading** (`FAST=1`: the image in the DDR3 at byte 0x32000000, a download that carries only its length) | the 3,670,032-byte image is replayed in 12,982,471 clocks (**0.135 s** at 96 MHz, DDR3 with 24 clocks of latency and 10 % of the clocks busy); all 1,835,008 words of the SDRAM chip equal the image; the game byte is right (0 / 1); 14,337 DDR3 reads, no write, no protocol error |
| the streamed load (an older Main_MiSTer), both games | 12,982,152 clocks for the same image (the SDRAM write path, about 7 clocks a byte, is what limits both; on the board the HPS's transfer is what makes a streamed load slow); all 1,835,008 words right, 0 DDR3 reads |
| **Whole machine after a fast load**, the real 3 s watchdog (both games, 380 / 460 million clocks) | machine frames 230 and 280: **0 of 76,800 pixels differ from MAME's, both games**, through the top level's own video path (this is also the first check of the cold start at its real length) |
| **inputs** (`BTN=1`) | 22 inputs (pad 1 / 2: directions, button, start, coin, service, test; keys 1 2 5 6 9 F2) each reach exactly their bit of P1 / P2: *Service* and key 9 only P2 bit 9 (a credit), *Test* and key F2 only P1 bit 9 (the test menu); an earlier build tied both to one input |
| **Scale** (`SCALEMATRIX=1`) | 4 scaler sizes (1920 x 1080, 1280 x 720, 3840 x 2160, 1366 x 768) x 5 Scale x 3 Aspect ratio, set live: **60 of 60** sizes asked of the scaler equal the framework's integer rule, worked out independently in the bench from the picture's rows and width |
| **scandoubler** (Scandoubler Fx HQ2x / CRT 25 %, `forced_scandoubler`) | 480 rows of 320 (640 with HQ2x) in 520 lines, a vertical sync every frame, each frame 1,597,440 clocks = 60.096 Hz: the picture does not freeze (the Gaiapolis symptom: the framework's scandoubler needs the horizontal blank alone, on every line; this raster's `hblank` is, and CRT Adjust, whose blank includes the vertical one, is now bypassed while the scandoubler is in use) |
| **CRT Adjust** (`CRT=1`), 15 kHz | on at 0 / 0 / 0 = off to the clock: the same picture byte for byte, the first row 15.125 lines after the vertical sync, rows starting 768 clocks after the horizontal sync, 5,120 wide; H-Position +8 / -16 / +16 moves the rows 128 / -256 / +256 clocks and nothing else; H-Size -16 is 3,840 clocks wide (75 %), +5 with H-Position -16 5,520 (full width, clear of the sync pulse); V-Shift +3 / -12 moves the first row to 18.125 / 3.125 lines after the sync, always 240 rows in 260 lines |

What CRT Adjust did before (20261010, found by this bench): the glue gave `video_freak` the module's OSD-anchor DE window, which
bypasses the framework's data pipeline, so the picture content sat 6 dots to the right of that window and its last 4 dots were
cut off, and "on at zero" delayed the picture one line behind the vertical sync; the ranges (H-Position +-48, V-Shift -8..+23)
let the sync pulse into the picture (this raster has 4 lines of blanking before the sync, Metro's has 8). Now `video_freak` gets
`arcade_video`'s own DE (as in the Gaiapolis and Monster Maulers cores; the OSD menu moves with the picture when H-Position
moves it), the vertical sync is delayed one line with the picture (`voffset = 1 - V-Shift`, positive = down), H-Position carries
-1 dot (the module's own delay), and the ranges are what the blanking leaves: H-Size -16..+5, H-Position -16..+16, V-Shift -12..+3.

## Build 20261010 (Quartus Prime Lite 17.0.2, `quartus_sh --flow compile OhMyGod`, 32 min)

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

## Build 20261023 (fast loading, Scale, new CRT Adjust glue, new inputs)

| | |
|---|---|
| ALMs | 11,781 / 41,910 (28 %) |
| registers | 18,129 |
| block memory | 1,747,533 bits, 232 / 553 RAM blocks (42 %) |
| DSP / PLLs | 34 / 112, 3 / 6 |
| setup slack, core clock (96 MHz) | +1.633 ns; the framework's HDMI clock +0.301 ns |
| hold slack, core clock | +0.246 ns (the tightest of all clocks); recovery +5.0 ns, removal +0.62 ns; no negative slack anywhere |
| `tools/check_ram_depth.py` | 0 problems |

`releases/ohmygod_20261023.rbf` is that build (Quartus 17.0.2, seed 1, 13 minutes), `dist/OhMyGod_MiSTer_20261023.zip` the SD card zip. **Not yet
tested on a real MiSTer.**

The first compile of this RTL (seed 1) missed hold by 0.052 ns (six paths, TNS -0.217): the HPS port's DDR3 read data went from the framework's
`f2sdram` flip-flops straight into the fast loader's block buffer (an MLAB's write port). Seed 4 missed by 0.064 ns, seeds 2 and 3 met it (+0.213
and +0.091 ns), so it was placement noise on a path with no register of ours in it. `omg_fastload` now registers the read data and valid once
before the buffer (two clocks more on a 12,982,471-clock load, re-checked in the bench for both games); seed 1 then meets everything with the
margins above, and the seed stays at 1.

## Screen flip, Service / Test out of the mapping (20261023b)

Naname de Magic!'s Flip Screen DIP did not flip (reported on the board: the background colours gone and nothing turned): MAME's picture of
it is broken in the same way, because the hardware's flip (bit 14 of the sprite bank register) is not emulated by MAME
(`MACHINE_NO_COCKTAIL`). Measured in MAME with the DIP on and off (same scripted play, `sim/bench/mame/run_flip.sh`; details and
the constants in `docs/hardware.md`): with the DIP on the game writes the sprite bank register with bit 14 set, the scroll words
39 / 273 higher and the sprite positions moved by -57 / +17, tile RAM and sprite codes unchanged. Taking those constants out gives
MAME's unflipped picture; the picture the hardware shows is that one turned through 180 degrees.

| check | result |
|---|---|
| **reference renderer** (`tools/omg_ref.py`, flip model) on the 16 flip-mode states of `tools/omg_flipstates.py` | each equals MAME's unflipped picture of the same game moment turned 180 degrees: **16 of 16, 0 of 76,800 pixels differ** |
| **the RTL** (`sim/bench/corpus_rtl.sh naname_flip`, frozen flip-mode states through `omg_main` / `omg_core` / `omg_render` / `omg_video`) | **16 of 16 pixel-identical** to the same expected pictures; longest line render 2,856 of 6,144 clocks |

The flip is taken over at the start of vertical blank (a frame is drawn and shown one way); the lines are drawn from the bottom up and read
out from the right, the tile scroll and the sprite positions are corrected by the constants; nothing changes when the bit is clear. It is
what the hardware does in the sense that the game's own numbers come out exactly; nothing has been seen on a real board. Oh My God! never
sets the bit.

The Service and Test entries are gone from the controller mapping (J1 and the MRAs list only the button, Start and Coin): Service (key 9, a
credit) and Test (key F2, the test menu) are keys only. The bench's input table shows pad bits 7 / 8 reach nothing.

## Build 20261023b (flip, no pad Service / Test)

| | |
|---|---|
| ALMs | 11,733 / 41,910 (28 %) |
| registers | 18,099 |
| block memory | 1,747,533 bits, 232 / 553 RAM blocks (42 %) |
| DSP / PLLs | 34 / 112, 3 / 6 |
| setup slack, core clock (96 MHz) | +0.918 ns; the framework's HDMI clock +0.391 ns |
| hold slack | +0.250 ns on the core clock, +0.251 HDMI (the tightest of all clocks); no negative slack anywhere |
| `tools/check_ram_depth.py` | 0 problems |

`releases/ohmygod_20261023b.rbf` is that build (Quartus 17.0.2, seed 2), `dist/OhMyGod_MiSTer_20261023b.zip` the SD card zip (the letter
numbers the day's second build: MiSTer takes the newest by name). Seeds 1 and 2 both met timing; seed 1's margins were smaller
(core clock setup +0.467 ns, hold +0.246, HDMI hold +0.221), so `OhMyGod.qsf` now carries `SEED 2`. **Not yet tested on a real MiSTer.**

Regression of the unchanged picture on this RTL: the frozen-state corpus (`sim/bench/corpus_rtl.sh`) is **60 of 60 identical to MAME for both games**
(longest line render 3,424 / 3,267 clocks, as before); the top-level bench (`sim/emu/run_emu.sh`, fast load) again gives machine frames 230 and 280
of both games after the real 3 s cold start **0 of 76,800 pixels different from MAME's**, the input table (pad bits 7 / 8 reach nothing, keys 9 and
F2 reach P2 bit 9 and P1 bit 9), the scandoubler and CRT Adjust runs (on at 0 / 0 / 0 = off, byte for byte) and all 60 Scale / Aspect ratio /
scaler size settings.
