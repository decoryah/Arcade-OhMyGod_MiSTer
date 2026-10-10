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

Ports (all active low): P1 bit 0 up, 1 down, 2 left, 3 right, 4 button 1, 7 start 1, 8 coin 1, 9 service (no toggle);
P2 the same with start 2, coin 2, service 1; the other bits unused. DSW1 bits 15:12 coin B, 11:8 coin A; DSW2 as in the
MRA (`tools/make_mra.py`).

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
