# Atlus ohmygod.cpp hardware (MAME 0.289): Oh My God! (1993), Naname de Magic! (1994)

Source: `src/mame/atlus/ohmygod.cpp` at tag `mame0289` (one file, 19,602 bytes; `ref/mame/src/mame/atlus/` of the working tree).
Everything below is from that file and MAME's own output (`-listxml`, Lua dumps); nothing is measured on a board.

## Machine

| | |
|---|---|
| CPU | MC68000, 12 MHz (`M68000(..., 12000000)`); level 1 autovector interrupt at the start of vertical blanking (`irq1_line_hold`) |
| Sound | one OKI M6295, 12 MHz / 6 = 2 MHz, pin 7 high (sample rate clock / 132 = 15.15 kHz), mono, route gain 1.0 |
| Video | 320 x 240 visible of a 512 x 256 bitmap, 60.000 Hz (MAME's `set_refresh_hz(60)`, `set_vblank_time(0)`; visible window x 96..415, y 0..239); xGRB555 palette of 1024 entries |
| Watchdog | 3 s, read of 0xC00000 resets it; MAME's comment: "a guess, and certainly wrong". The game reads it once a frame. |
| ROM | 512 K program, 512 K tiles, 512 K sprites, 2 MB ADPCM (16 banks of 128 K) |
| Sets | `ohmygod` (omg-p.114, omg-b.117, omg-s.120, omg-g.107), `naname` (036-prg.114, 036-bg.117, 036-spr.120, 036-snd.107) |

## 68000 memory map (`ohmygod_state::main_map`)

| range | |
|---|---|
| 000000-07FFFF | program ROM |
| 300000-303FFF | RAM (unknown use: "lots of unknown RAM, maybe other GFX planes not used by these games") |
| 304000-307FFF | tile RAM: 64 x 64 tiles, tile index = row * 64 + column, two words each: word 0 attr (palette group = bits 11:8), word 1 code |
| 308000-30FFFF | RAM |
| 400000 / 400002 | scroll x / scroll y (write only, words) |
| 600000-6007FF | palette RAM, xGRB555, 1024 entries |
| 700000-703FFF | sprite RAM: two banks of 1024 entries x 4 words |
| 704000-707FFF, 708000-70FFFF | RAM (708000 is the work RAM) |
| 800000 / 800002 | P1 / P2 (16 bit, active low) |
| 900000 | control (write): low byte = OKI bank `(data >> shift) & 15`, shift 4 (Oh My God!) / 0 (Naname); bits 12 / 13 = coin counters |
| A00000 / A00002 | DSW1 / DSW2 |
| B00001 | OKI M6295 (byte, low lane) |
| C00000 | watchdog (read) |
| D00000 | sprite bank (write): bit 15 of the word, i.e. bit 7 of the high byte |

Unmapped reads give 0; the mapped ranges are exact (no mirrors).

Ports (all active low): P1 bit 0 up, 1 down, 2 left, 3 right, 4 button 1, 7 start 1, 8 coin 1, 9 service mode (MAME's
`PORT_SERVICE_NO_TOGGLE`, key F2: the test switch); P2 the same with start 2, coin 2 and bit 9 = service 1 (key 9); the other bits
unused. DSW1 bits 15:12 coin B, 11:8 coin A; DSW2 as in the MRA (`tools/make_mra.py`).

The two bit-9 inputs are different switches and the program (checked in the 68000 listing, `unidasm`) treats them differently:
the vertical-blank interrupt handler reads P1 and, with bit 9 low, sets the main state variable (0x704000) to 2, the test menu
(MONITOR TEST, SWITCH TEST, SOUND TEST, DIP SW LIST, EXIT; "PUSH 1P SELECT BUTTON" -- the game's own word for Start is SELECT,
for the action button BUTTON; the switch test screen lists COIN 1 / 2, SERVICE, TEST SW, SELECT, BUTTON and STICK, and "PUSH TEST
SW RETURN TO MENU"); the coin routine (0x1b256) adds a credit for a new edge on P1 bit 8 (coin 1), P2 bit 8 (coin 2) or P2 bit 9
(service 1). The core therefore keeps them apart: pad *Service* and key 9 drive P2 bit 9 only, pad *Test* and key F2 drive P1 bit 9
only (an earlier build tied both to one input, so pressing Service also opened the test menu).

The one button (observed in MAME 0.289 with `tools/lua/probe_inputs.lua`): in **Oh My God!** it makes the falling chain of
balls fall like Down does and does nothing while the chain is swung sideways (Left / Right swing the chain to that side, Up does
nothing); in **Naname de Magic!** it turns the falling piece. The MRAs name it Drop and Rotate.

## Screen flip (bit 14 of the sprite bank register)

MAME ignores it (both games are `MACHINE_NO_COCKTAIL`), so with Naname de Magic!'s **Flip Screen** DIP (DSW2 bit 14, On = 0) MAME
shows a broken picture: no background and the sprites in other places. What the game does with the DIP on (compared frame for frame
with the DIP off, same inputs, `tools/lua/probe_inputs.lua` `DIPSET`, `WRSUM`; `tools/lua/dump_state.lua` `DIPSET`, `ACTIONS`):

* It writes the sprite bank register (D00000) as 0x4000 / 0xC000 instead of 0x0000 / 0x8000: **bit 14 is the flip**.
* Tile RAM is identical, in place. The scroll registers differ: 0x01B3 / 0x0301 instead of 0x818C / 0x81F0, i.e. the unflipped value
  (mod 512) plus **39 (x) and 273 (y)**.
* The sprite list has the same entries (codes, colours, flip x bits); the positions are the unflipped ones moved by **-57 in word 0
  (x) and +17 in word 1 (y)**, every sprite alike.

Take those constants out and the flip-mode state renders (the ordinary renderer) to MAME's unflipped picture, pixel for pixel, at
every frame tried (16 of 16 states of one play script: `sim/bench/mame/run_flip.sh`, `tools/omg_flipstates.py`). So the hardware turns
the whole picture, tiles and sprites together, through 180 degrees (both axes change, and the game pre-compensates for the
board's own mirroring constants), and this is what the core does: `omg_main` keeps bit 14, `omg_core` takes it over at the start of
vertical blank (a frame is drawn and shown one way), `omg_render` takes the constants out of the scroll words and the sprite
positions, `omg_video` draws the lines from the bottom up and reads the line buffer from its right end. The game sets the bit only
for Naname's DIP; Oh My God!'s program never does (its DSW2 bit 14 is "Balls Have Eyes"). The two sprite copy routines show it: Naname's
(the routine at 0x1310) tests DSW2 bit 14, and with the DIP on subtracts 0x39 from every sprite x, adds 0x11 to y (mod 0x400) and ORs 0x4000
into the bank word -- the constants measured above; Oh My God!'s (0x1a952) copies the list as it is and writes only the bank bit.
The 180 degrees are the reading that makes the game's own numbers come out exactly, and on a real MiSTer (20261023b, the owner's test) the
picture turns correctly with Naname's Flip Screen DIP on.

## Video

* Tile layer: 64 x 64 tiles of 8 x 8, 4 bits per pixel, opaque, `TILEMAP_SCAN_ROWS`. Character ROM: 16384 tiles of 32 bytes; a
  row is 4 bytes, two pixels per byte, the left pixel in the high nibble (`gfx_8x8x4_packed_msb`). Code = the word's low 14 bits.
  Palette index = group * 16 + pen (0..255).
* Scroll: source x = x + (scrollx - 0x81ec), source y = y + (scrolly - 0x81ef), modulo 512, in the 512-pixel bitmap whose
  visible window starts at x = 96. The game writes 0x8000 + position, so `scrollx_reg[8:0] + 116` is the source x of the first
  visible pixel (96 + 20) and `scrolly_reg[8:0] + 17` the source y of line 0.
* Sprites: 1024 entries, four words: 0 x (screen x = word - 29), 1 y (signed 16 bit), 2 colour (bits 3:0), 3 flip x (bit 15)
  and code (bits 11:0). 16 x 16, 4 bpp (`gfx_16x16x4_packed_msb`: a row is 8 bytes, left pixel in the high nibble), pen 0
  transparent, palette index 512 + colour * 16 + pen, drawn after the tiles in entry order (the last one on top). No y flip, no
  priority bits, no zoom. The sprite bank flag selects the second 8 KB of the sprite RAM; the game double-buffers with it.
* Clipping: the visible window only (no wrap of sprite coordinates: MAME works with ints).
* Palette: `xGRB_555`: bits 14:10 green, 9:5 red, 4:0 blue; 5 -> 8 bits as `{c, c[4:2]}`.

## Timing used by the core (the board's real timing is not known)

96 MHz machine clock; 68000 = /8; dots = /16 = 6 MHz; 384 dots x 260 lines = 60.096 Hz, 320 x 240 visible, vertical blank
interrupt at line 240. (MAME's own totals are 512 x 256 at exactly 60 Hz; a 15 kHz monitor wants the usual 15.6 kHz line.)

## Reading MAME's output (harness notes)

* The frame notifier runs before the screen update, so `screen:pixels()` inside it is the previous frame's picture, and MAME
  converts a frame's pen indexes to RGB with the palette *at the time the pixels are read*: the picture of the state dumped at
  callback N is `pixels()` and the palette at callback N+1 (`f<N>.rgb`, `f<N>.pal1`). A fade changes the palette every frame,
  which showed up as a uniform one-step colour difference in a naive comparison.
* `screen:vpos()` is not available in 0.289's Lua; the write log derives the raster line from the machine time, and that count
  starts at the *start of vertical blank* (MAME's line 240): the picture's line is `(logged + 240) mod 256`.
