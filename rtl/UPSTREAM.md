# Files in this directory derived from other projects

| File | Derived from | Licence | Changes for this core |
|---|---|---|---|
| `sdram_ctrl.sv` | the owner's `mcatadv-mister/mister/target/mister/sdram_ctrl.sv` (itself the Pocket Gaiapolis core's multi-port controller by plasticbugs, carried to MiSTer, with the Punch-Out!! core's `sdram16.sv` pin-level behaviour) | GPL-3.0-or-later (`../LICENSE`) | none: byte-identical; used with two clients (OKI byte reads and the loader) and the burst port |
| `omg_cache.sv` | `mcatadv_cache.sv` (the owner's MCatAdv core) | same | renamed; narrowed to this board's 512 KB program (16 KB direct mapped, 8-word lines) |
| `omg_cen.sv` | `mcatadv_cen.sv` | same | renamed; the 68000 at 12 MHz (96 / 8, phases four clocks apart) and the OKI's 2 MHz (96 / 48) |
| `omg_ram.sv` | `mcatadv_ram.sv` (block RAM building blocks written the way Quartus 17 infers M10K) | same | renamed; the RAMs this board needs |
| `omg_mem.sv` | `mcatadv_mem.sv` (loader, burst arbiter) | same | renamed; this board's image layout (program / characters / sprites / OKI samples / configuration byte) and clients |
| `omg_crtadj.sv` | the Metro core's `metro_crtadj.sv` (glue for rmonic79's CRT Adjust, `../modules/crt_adjust`) | same | renamed; `VTOTAL` 260, `HTOTAL` 384; then reworked after the Gaiapolis / Monster Maulers glue (sync delayed one line with the picture, -1 dot of H-Position, ranges from this raster's blanking, no OSD-anchor DE window): see `../docs/status.md` |
| `omg_fastload.sv` | the Metro core's `metro_fastload.sv` (reads the image Main_MiSTer puts into the DDR3 back into the loader) | same | renamed; the DDR3 port goes straight to the framework (no other user), the read data and valid are registered once before the block buffer (hold timing of the f2sdram -> MLAB path) |
| `pll.v`, `pll.qip`, `pll/` | the Metro core's PLL (reference 50 MHz: 96 MHz machine clock, 96 MHz shifted -5078 ps for the SDRAM chip) | same | none |

The top-level bench (`../sim/emu/`) follows the owner's Monster Maulers one: `../sim/ddr_model.sv` (the Avalon DDR3 model) and
`sim/emu/sync_fix.sv` (the framework's, which `sys_top` cannot provide here) are copied, `hps_io_stub.sv`, `pll_stub.sv`,
`tb_emu_top.sv`, `tb_emu.cpp` and `run_emu.sh` are adapted to this core.

Written for this core (not derived): `omg_main.sv` (the 68000 board: memory map, RAMs, controls, watchdog, OKI port; bus-cycle
structure after `mcatadv_main.sv`), `omg_render.sv` (the line renderer), `omg_video.sv` (raster, line buffer, palette),
`omg_sound.sv` (jt6295 and its ROM port) and `omg_core.sv` (wiring). The 68000 core (`../modules/cpu-fx68k`), the OKI
(`../modules/jt6295`) and the CRT Adjust page (`../modules/crt_adjust`) are vendored: `../modules/VENDOR.md`.
