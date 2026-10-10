-- Lists the I/O ports and fields, the screen geometry and what screen:pixels() returns (run for a few frames).
local m = manager.machine
for tag, port in pairs(m.ioport.ports) do
  for name, field in pairs(port.fields) do
    print(string.format("PORT %-8s FIELD %-24s mask=%04x", tag, name, field.mask))
  end
end
local scr = m.screens[":screen"]
local n = 0
emu.add_machine_frame_notifier(function()
  n = n + 1
  if n == 5 then
    local px = scr:pixels()
    print(string.format("SCREEN %dx%d frame=%d  pixels=%d bytes  refresh=%.4f",
      scr.width, scr.height, scr:frame_number(), #px, 1 / scr.frame_period))
    m:exit()
  end
end)
