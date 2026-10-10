-- the 68000's PC at each frame notifier for the first N frames; also whether this script is started again (a soft reset
-- re-runs the autoboot script).  PCOUT=<file> N=<frames>
local mach = manager.machine
local cpu = mach.devices[":maincpu"]
local out = assert(io.open(os.getenv("PCOUT") or "pc.txt", "a"))
local t0 = mach.time
t0 = (type(t0) == "number") and t0 or t0:as_double()
out:write(string.format("SCRIPT START at machine time %.4f s (frame %d)\n", t0, math.floor(t0 * 60 + 0.5)))
local n, N = 0, tonumber(os.getenv("N") or "60")
emu.add_machine_frame_notifier(function()
  n = n + 1
  local t = mach.time
  t = (type(t) == "number") and t or t:as_double()
  if n % 10 == 0 or n < 5 or (n > 175 and n < 200) then
    out:write(string.format("n=%d abs=%d pc=%06x sr=%04x a0=%08x d0=%08x\n", n, math.floor(t * 60 + 0.5), cpu.state["PC"].value, cpu.state["SR"].value, cpu.state["A0"].value, cpu.state["D0"].value))
  end
  if n >= N then out:close(); mach:exit() end
end)
