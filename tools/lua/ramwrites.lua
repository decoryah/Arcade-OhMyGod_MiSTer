-- Histogram of the raster line (0..255, counted from the start of vertical blank: picture line = (v + 240) % 256) at which the 68000 writes tile RAM, sprite RAM (both banks),
-- palette RAM and the registers, by frame range.   OUT=<file>  START=<frame>  FRAMES=<n>  GAME=...
-- Coin / start / random play as dump_state.lua.
local mach = manager.machine
local sp = mach.devices[":maincpu"].spaces["program"]
local scr = mach.screens[":screen"]
local KEEP = {}
_G.K = KEEP
local function line()
  local t = mach.time
  t = (type(t) == "number") and t or t:as_double()
  return math.floor(((t * 60) % 1) * 256)
end
local hist = { vram = {}, spr0 = {}, spr1 = {}, pal = {}, ram = {} }
for _, h in pairs(hist) do for i = 0, 255 do h[i] = 0 end end
local sbank = 0
local f = 0
local START, N = tonumber(os.getenv("START") or "600"), tonumber(os.getenv("FRAMES") or "600")
local function inrange() return f >= START and f < START + N end
KEEP.a = sp:install_write_tap(0x304000, 0x307fff, "vram", function() if inrange() then local l = line(); hist.vram[l] = hist.vram[l] + 1 end end)
KEEP.b = sp:install_write_tap(0x700000, 0x701fff, "spr0", function() if inrange() then local l = line(); hist.spr0[l] = hist.spr0[l] + 1 end end)
KEEP.c = sp:install_write_tap(0x702000, 0x703fff, "spr1", function() if inrange() then local l = line(); hist.spr1[l] = hist.spr1[l] + 1 end end)
KEEP.d = sp:install_write_tap(0x600000, 0x6007ff, "pal", function() if inrange() then local l = line(); hist.pal[l] = hist.pal[l] + 1 end end)
KEEP.e = sp:install_write_tap(0xd00000, 0xd00001, "sb", function(off, data, mask)
  if (mask & 0xff00) ~= 0 then sbank = (data >> 15) & 1 end end)
-- which bank is the game writing sprites into: log (frame, bank displayed, first sprite write line)
local function field(port, name) local p = mach.ioport.ports[port]; return p and p.fields[name] end
local coin, start = field(":P1", "Coin 1"), field(":P1", "1 Player Start")
local up, dn, lf, rt, b1 = field(":P1", "P1 Up"), field(":P1", "P1 Down"), field(":P1", "P1 Left"), field(":P1", "P1 Right"), field(":P1", "P1 Button 1")
local rng = 1
local function rnd(n) rng = (rng * 1103515245 + 12345) & 0x7fffffff; return (rng >> 8) % n end
local dir = 0
KEEP.n = emu.add_machine_frame_notifier(function()
  f = f + 1
  local ph = (f - 150) % 1800
  coin:set_value((f >= 150 and ph < 6) and 1 or 0)
  start:set_value((f >= 210 and (f - 210) % 1800 < 6) and 1 or 0)
  if f >= 280 then
    if f % 10 == 0 then dir = rnd(9) end
    up:set_value((dir == 1 or dir == 5 or dir == 8) and 1 or 0); dn:set_value((dir == 2 or dir == 6 or dir == 7) and 1 or 0)
    lf:set_value((dir == 3 or dir == 5 or dir == 6) and 1 or 0); rt:set_value((dir == 4 or dir == 7 or dir == 8) and 1 or 0)
    b1:set_value((f % 23 < 5) and 1 or 0)
  end
  if f >= START + N then
    local o = assert(io.open(os.getenv("OUT") or "ramwrites.txt", "w"))
    for _, name in ipairs({ "vram", "spr0", "spr1", "pal" }) do
      local t, tot = {}, 0
      for i = 0, 255 do if hist[name][i] > 0 then t[#t + 1] = string.format("%d:%d", i, hist[name][i]); tot = tot + hist[name][i] end end
      o:write(string.format("%s total %d: %s\n", name, tot, table.concat(t, " ")))
    end
    o:close()
    mach:exit()
  end
end)
