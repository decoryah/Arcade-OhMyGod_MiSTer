-- per frame: writes into each sprite RAM bank, the sprite bank value at the start / end of the frame, flips and the line of each flip
local mach = manager.machine
local sp = mach.devices[":maincpu"].spaces["program"]
local K = {}
_G.K = K
local function line()
  local t = mach.time; t = (type(t) == "number") and t or t:as_double()
  return math.floor(((t * 60) % 1) * 256)
end
local f, sb = 0, 0
local w0, w1, flips = 0, 0, ""
local first0, last0, first1, last1 = 999, -1, 999, -1
K.a = sp:install_write_tap(0x700000, 0x701fff, "s0", function() local l = line(); w0 = w0 + 1; if l < first0 then first0 = l end; if l > last0 then last0 = l end end)
K.b = sp:install_write_tap(0x702000, 0x703fff, "s1", function() local l = line(); w1 = w1 + 1; if l < first1 then first1 = l end; if l > last1 then last1 = l end end)
K.c = sp:install_write_tap(0xd00000, 0xd00001, "sb", function(off, data, mask)
  if (mask & 0xff00) ~= 0 then sb = (data >> 15) & 1; flips = flips .. string.format(" ->%d@%d", sb, line()) end end)
local function field(port, name) local p = mach.ioport.ports[port]; return p and p.fields[name] end
local coin, start = field(":P1", "Coin 1"), field(":P1", "1 Player Start")
local START = tonumber(os.getenv("START") or "1500")
local out = assert(io.open(os.getenv("OUT"), "w"))
local sbstart = 0
K.n = emu.add_machine_frame_notifier(function()
  if f >= START and f < START + 16 then
    out:write(string.format("frame %d: bank0 writes %d (lines %d-%d)  bank1 writes %d (lines %d-%d)  displayed at frame start %d, flips:%s\n",
      f, w0, first0, last0, w1, first1, last1, sbstart, flips))
  end
  f = f + 1
  w0, w1, flips = 0, 0, ""; first0, last0, first1, last1 = 999, -1, 999, -1
  sbstart = sb
  local ph = (f - 150) % 1800
  coin:set_value((f >= 150 and ph < 6) and 1 or 0)
  start:set_value((f >= 210 and (f - 210) % 1800 < 6) and 1 or 0)
  if f >= START + 17 then out:close(); mach:exit() end
end)
