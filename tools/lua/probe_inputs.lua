-- Plays Oh My God! / Naname de Magic! with scripted inputs and saves pictures: what does a button do, what do the two service inputs do.
--
--   OUT=<dir>              where the pictures go (shot<frame>.rgb: 320 x 240 x 3 bytes, the picture of that frame)
--   ACTIONS=<f:name:n,...> press <name> for n frames from machine frame f; names: coin, coin2, start, start2, up, down, left, right,
--                          b1 (P1 button), b2 (P2 button), svc (P2 "Service 1", key 9), test (P1 "Service Mode", key F2),
--                          p2up, p2down, p2left, p2right
--   SHOTS=<f,f,a-b/s,...>  frames to save
--   LAST=<f>               exit after this frame
--   WRSUM=1                write <OUT>/writes.txt: every distinct value the 68000 wrote to the scroll registers (SX, SY), the control register (CT) and the
--                          sprite bank register (SB), with how often
--   DIPSET=<port|field|value;...>  set DIP switches (the setting's value, e.g. ":DSW2|Flip Screen|0" = On in Naname de Magic!)
--
-- Frames are absolute machine frames (the 3 s watchdog reset at the cold start restarts this script, as in dump_state.lua).
local mach = manager.machine
local scr  = mach.screens[":screen"]
local KEEP = {}
_G.PROBEKEEP = KEEP

local function absframe()
  local t = mach.time
  t = (type(t) == "number") and t or t:as_double()
  return math.floor(t * 60 + 0.5)
end

local DIR  = os.getenv("OUT") or "."
local LAST = tonumber(os.getenv("LAST") or "1500")

local SHOTS = {}
for item in string.gmatch(os.getenv("SHOTS") or "", "[^,]+") do
  local a, b, s = string.match(item, "^(%d+)%-(%d+)/(%d+)$")
  if a then for n = tonumber(a), tonumber(b), tonumber(s) do SHOTS[n] = true end else SHOTS[tonumber(item)] = true end
end

local function field(port, name) local p = mach.ioport.ports[port]; return p and p.fields[name] end
local F = {
  coin  = field(":P1", "Coin 1"),            coin2  = field(":P2", "Coin 2"),
  start = field(":P1", "1 Player Start"),    start2 = field(":P2", "2 Players Start"),
  up = field(":P1", "P1 Up"), down = field(":P1", "P1 Down"), left = field(":P1", "P1 Left"), right = field(":P1", "P1 Right"),
  p2up = field(":P2", "P2 Up"), p2down = field(":P2", "P2 Down"), p2left = field(":P2", "P2 Left"), p2right = field(":P2", "P2 Right"),
  b1 = field(":P1", "P1 Button 1"),          b2 = field(":P2", "P2 Button 1"),
  svc = field(":P2", "Service 1"),           test = field(":P1", "Service Mode"),
}
local ACT = {}
for item in string.gmatch(os.getenv("ACTIONS") or "", "[^,]+") do
  local f, name, n = string.match(item, "^(%d+):(%w+):(%d+)$")
  assert(f and F[name], "bad action " .. item)
  ACT[#ACT + 1] = { f = tonumber(f), name = name, n = tonumber(n) }
end

for item in string.gmatch(os.getenv("DIPSET") or "", "[^;]+") do
  local port, name, val = string.match(item, "^([^|]+)|([^|]+)|(%d+)$")
  local fld = port and field(port, name)
  assert(fld, "bad DIPSET " .. item)
  fld.user_value = tonumber(val)
end

local wrseen = {}
if os.getenv("WRSUM") then
  local sp = mach.devices[":maincpu"].spaces["program"]
  local function tap(lo, hi, kind)
    return sp:install_write_tap(lo, hi, kind, function(off, data, mask)
      local k = string.format("%s data %04x mask %04x", kind, data & 0xffff, mask & 0xffff)
      wrseen[k] = (wrseen[k] or 0) + 1
    end)
  end
  KEEP.w1 = tap(0x400000, 0x400001, "SX"); KEEP.w2 = tap(0x400002, 0x400003, "SY")
  KEEP.w3 = tap(0x900000, 0x900001, "CT"); KEEP.w4 = tap(0xd00000, 0xd00001, "SB")
end
local function write_summary()
  if not os.getenv("WRSUM") then return end
  local keys = {}
  for k in pairs(wrseen) do keys[#keys + 1] = k end
  table.sort(keys)
  local o = assert(io.open(DIR .. "/writes.txt", "w"))
  for _, k in ipairs(keys) do o:write(string.format("%6d  %s\n", wrseen[k], k)) end
  o:close()
end

local pending
local function dump_pixels(path)
  local px = scr:pixels()
  local out = {}
  for i = 0, #px // 4 - 1 do
    local b, g, r = px:byte(i * 4 + 1, i * 4 + 3)
    out[i + 1] = string.char(r, g, b)
  end
  local o = assert(io.open(path, "wb")); o:write(table.concat(out)); o:close()
end

KEEP.n = emu.add_machine_frame_notifier(function()
  local f = absframe()
  if pending then dump_pixels(pending); pending = nil end
  for name, fld in pairs(F) do
    local on = false
    for _, a in ipairs(ACT) do if a.name == name and f >= a.f and f < a.f + a.n then on = true end end
    fld:set_value(on and 1 or 0)
  end
  if SHOTS[f] then pending = string.format("%s/shot%05d.rgb", DIR, f) end
  if f >= LAST then write_summary(); mach:exit() end
end)
