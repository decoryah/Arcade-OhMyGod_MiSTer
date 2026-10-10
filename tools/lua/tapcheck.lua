-- does a read tap see every read of P1? counts reads per frame of 0x800000, and what the CPU is given, around the coin
local mach = manager.machine
local sp = mach.devices[":maincpu"].spaces["program"]
local K = {}; _G.K = K
local f, n, vals = 0, 0, {}
K.t = sp:install_read_tap(0x800000, 0x800001, "p1", function(off, data, mask) n = n + 1; vals[#vals + 1] = string.format("%04x", data & 0xffff) end)
local coin = mach.ioport.ports[":P1"].fields["Coin 1"]
K.n = emu.add_machine_frame_notifier(function()
  f = f + 1
  if f >= 148 and f <= 160 then print(string.format("frame %d: %d tap reads: %s | port:read() = %04x", f - 1, n, table.concat(vals, ","), mach.ioport.ports[":P1"]:read() & 0xffff)) end
  n, vals = 0, {}
  coin:set_value((f >= 150 and (f - 150) % 1800 < 6) and 1 or 0)
  if f >= 162 then mach:exit() end
end)
