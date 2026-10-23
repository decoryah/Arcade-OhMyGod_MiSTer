-- Freezes frames of Oh My God! / Naname de Magic! and writes everything the frame bench needs, together with the exact
-- pixels MAME drew for that frame (screen:pixels(), 320 x 240).
--
--   GAME=ohmygod|naname    sets the ADPCM bank shift of the control register (4 / 0), as the driver's init does
--   DUMPFRAMES=<f,f,f...>  machine frames to capture (the vertical blank that ends frame f; also a range a-b/step as "a-b/s")
--   DUMPDIR=<dir>          output directory
--   SCHEDULE=play|none     scripted inputs: play = coin / start / random joystick and button (default)
--   SEED=<n>               seed of the random play
--   COIN_FRAME=<n>         first coin (default 330), START_FRAME (default 390), PLAY_FRAME (default 460): machine frames, after the 3 s cold-start wait
--   INPUTLOG=<file>        the port values the 68000 reads, per frame, as "frame p1 p2" lines when they change (replay: sim/run.sh +inputs=)
--   WRLOG=<file>           log of the 68000's writes to the control / OKI / sprite bank registers: frame vpos addr data mask
--
-- For every captured frame <N>:
--   f<N>.regs     frame scrollx scrolly spritebank sndbank ctrl wdog flip (as the driver holds them; wdog = reads so far; flip = bit 14 of the
--                 sprite bank register, which MAME ignores and Naname de Magic! sets with its Flip Screen DIP switch; older files have 7 fields)
--   f<N>.ram300   0x300000-0x30FFFF, one 16-bit word per line (hex); the tile RAM is words 0x2000..0x3FFF
--   f<N>.ram700   0x700000-0x70FFFF; the sprite RAM is words 0..0x1FFF
--   f<N>.pal      0x600000-0x6007FF (1024 words)
--   f<N>.rgb      320 x 240 x 3 bytes, the frame MAME drew from exactly this state (taken one callback later)
--   f<N>.pal1     the palette one callback later: MAME converts the frame's pen indexes to RGB when the pixels are read,
--                 so a fade shows up as a different palette than the state's own (use it to compare with f<N>.rgb)
local mach = manager.machine
local sp   = mach.devices[":maincpu"].spaces["program"]
local scr  = mach.screens[":screen"]
local KEEP = {}
_G.DUMPKEEP = KEEP

local GAME  = os.getenv("GAME") or "ohmygod"
local SHIFT = (GAME == "naname") and 0 or 4
local DIR   = os.getenv("DUMPDIR") or "."

local reg = { scrollx = 0, scrolly = 0, spritebank = 0, sndbank = 0, ctrl = 0, wdog = 0, flip = 0 }

-- ABSOLUTE machine frame: both games start with a cold-start routine that fills the RAM, writes a signature and then waits for
-- the watchdog (MAME: 3 s) to reset the machine; MAME runs the autoboot script again on that reset, so a counter of this script's
-- own would restart at 0 at machine frame 180.  Everything is numbered by the machine time instead (frame k is the vertical
-- blank that ends k frames of 1/60 s), which is what the RTL's vertical-blank count is.
local function absframe()
  local t = mach.time
  t = (type(t) == "number") and t or t:as_double()
  return math.floor(t * 60 + 0.5)
end
local f = absframe()
local first_life = (f == 0)                      -- the files are truncated by the first life only, appended to by the one after the reset

local wrlog
if os.getenv("WRLOG") then wrlog = assert(io.open(os.getenv("WRLOG"), first_life and "w" or "a")) end
-- raster line (0..255) from the machine time: 512 x 256 pixels in exactly 1/60 s from time zero.  The count starts at the START OF
-- VERTICAL BLANK (the IRQ), not at the top of the picture: the picture's line is (v + 240) % 256.
local function vpos()
  local t = mach.time
  t = (type(t) == "number") and t or t:as_double()
  local frac = (t * 60) % 1
  return math.floor(frac * 256)
end
local function logw(kind, off, data, mask)
  if wrlog then
    local ok, err = pcall(function()
      wrlog:write(string.format("%d %d %s %06x %04x %04x\n", f, vpos(), kind, off, data & 0xffff, mask & 0xffff))
    end)
    if not ok then print("WRLOG error: " .. tostring(err)) end
  end
end

-- COMBINE_DATA(&m_scrollx) ...
local function combine(old, data, mask) return ((old & ~mask) | (data & mask)) & 0xffff end

KEEP.t1 = sp:install_write_tap(0x400000, 0x400001, "scrollx", function(off, data, mask)
  reg.scrollx = combine(reg.scrollx, data, mask); logw("SX", off, data, mask) end)
KEEP.t2 = sp:install_write_tap(0x400002, 0x400003, "scrolly", function(off, data, mask)
  reg.scrolly = combine(reg.scrolly, data, mask); logw("SY", off, data, mask) end)
KEEP.t3 = sp:install_write_tap(0xd00000, 0xd00001, "spritebank", function(off, data, mask)
  if (mask & 0xff00) ~= 0 then reg.spritebank = (data >> 15) & 1; reg.flip = (data >> 14) & 1 end     -- bit 14: the hardware's screen flip (MAME ignores it)
  logw("SB", off, data, mask) end)
KEEP.t4 = sp:install_write_tap(0x900000, 0x900001, "ctrl", function(off, data, mask)
  reg.ctrl = combine(reg.ctrl, data, mask)
  if (mask & 0x00ff) ~= 0 then reg.sndbank = (data >> SHIFT) & 0x0f end
  logw("CT", off, data, mask) end)
KEEP.t5 = sp:install_read_tap(0xc00000, 0xc00001, "wdog", function(off, data, mask)
  reg.wdog = reg.wdog + 1 end)
if wrlog then
  KEEP.t6 = sp:install_write_tap(0xb00000, 0xb00001, "oki", function(off, data, mask) logw("OK", off, data, mask) end)
  KEEP.t7 = sp:install_read_tap(0xb00000, 0xb00001, "okir", function(off, data, mask) logw("OR", off, data, mask) end)
end

-- the port values the CPU reads, per frame, as "frame p1 p2" lines when they change (replay: sim/run.sh +inputs=).  They come from
-- the script's own decisions: a value set in notifier N is what the CPU reads during frame N + 1 (measured with the P1 read tap,
-- which is not reliable enough to log from: the machine state is identical whether or not it reports a read).
local inlog
if os.getenv("INPUTLOG") then inlog = assert(io.open(os.getenv("INPUTLOG"), first_life and "w" or "a")) end
local last1, last2 = -1, -1

-- frame list
local FRAMES = {}
local LAST = 0
for item in string.gmatch(os.getenv("DUMPFRAMES") or "600", "[^,]+") do
  local a, b, s = string.match(item, "^(%d+)%-(%d+)/(%d+)$")
  if a then
    for n = tonumber(a), tonumber(b), tonumber(s) do FRAMES[n] = true; if n > LAST then LAST = n end end
  else
    local n = tonumber(item); FRAMES[n] = true; if n > LAST then LAST = n end
  end
end

local function words(base, count, path)
  local o = assert(io.open(path, "w"))
  local t = {}
  for i = 0, count - 1 do t[i + 1] = string.format("%04x", sp:read_u16(base + i * 2)) end
  o:write(table.concat(t, "\n"), "\n")
  o:close()
end

-- screen:pixels() is 32-bit ARGB, little-endian (bytes B, G, R, A)
local pending
local function dump_pixels(path)
  local px = scr:pixels()
  local out = {}
  local n = #px // 4
  for i = 0, n - 1 do
    local b, g, r = px:byte(i * 4 + 1, i * 4 + 3)
    out[i + 1] = string.char(r, g, b)
  end
  local o = assert(io.open(path, "wb"))
  o:write(table.concat(out))
  o:close()
end

local function dump()
  local pre = string.format("%s/f%05d", DIR, f)
  local o = assert(io.open(pre .. ".regs", "w"))
  o:write(string.format("%d %d %d %d %d %d %d %d\n", f, reg.scrollx, reg.scrolly, reg.spritebank, reg.sndbank, reg.ctrl, reg.wdog, reg.flip))
  o:close()
  words(0x300000, 0x8000, pre .. ".ram300")
  words(0x700000, 0x8000, pre .. ".ram700")
  words(0x600000, 0x400,  pre .. ".pal")
  -- the frame notifier runs before the screen is updated, so screen:pixels() still holds the PREVIOUS frame here:
  -- the picture MAME draws from this RAM state is the one seen by the next callback
  pending = pre
  print("DUMPED frame " .. tostring(f))
  io.stdout:flush()
end

-- scripted inputs
local function field(port, name) local p = mach.ioport.ports[port]; return p and p.fields[name] end
-- DIPSET="<port>|<field>|<value>;..." sets DIP switches before the run (the setting's value, e.g. ":DSW2|Flip Screen|0" = On in Naname de Magic!)
for item in string.gmatch(os.getenv("DIPSET") or "", "[^;]+") do
  local port, name, val = string.match(item, "^([^|]+)|([^|]+)|(%d+)$")
  local fld = port and field(port, name)
  assert(fld, "bad DIPSET " .. item)
  fld.user_value = tonumber(val)
end
local coin, start = field(":P1", "Coin 1"), field(":P1", "1 Player Start")
local up, dn, lf, rt, b1 = field(":P1", "P1 Up"), field(":P1", "P1 Down"), field(":P1", "P1 Left"), field(":P1", "P1 Right"), field(":P1", "P1 Button 1")
local SCHED       = os.getenv("SCHEDULE") or "play"
local COIN_FRAME  = tonumber(os.getenv("COIN_FRAME") or "330")
local START_FRAME = tonumber(os.getenv("START_FRAME") or "390")
local PLAY_FRAME  = tonumber(os.getenv("PLAY_FRAME") or "460")
local rng = tonumber(os.getenv("SEED") or "12345")
local function rnd(n) rng = (rng * 1103515245 + 12345) & 0x7fffffff; return (rng >> 8) % n end
local dir = 0
-- ACTIONS="<frame>:<name>:<frames>,..." (names coin, start, up, down, left, right, b1) with SCHEDULE=actions: press <name> for <frames> frames from <frame>
local ACT = {}
for item in string.gmatch(os.getenv("ACTIONS") or "", "[^,]+") do
  local af, an, ad = string.match(item, "^(%d+):(%w+):(%d+)$")
  assert(af, "bad action " .. item)
  ACT[#ACT + 1] = { f = tonumber(af), name = an, n = tonumber(ad) }
end
local function act_on(f, name)
  for _, a in ipairs(ACT) do if a.name == name and f >= a.f and f < a.f + a.n then return true end end
  return false
end

KEEP.notif = emu.add_machine_frame_notifier(function()
  f = absframe()
  if pending then
    -- screen:pixels() converts the indexed bitmap with the palette AS IT IS NOW, so the palette of this callback
    -- (one frame later than the state) belongs to the picture: <N>.pal1 (a fade changes the palette every frame)
    dump_pixels(pending .. ".rgb")
    words(0x600000, 0x400, pending .. ".pal1")
    pending = nil
  end
  local cn, st, du, dd, dl, dr, bt = false, false, false, false, false, false, false
  if SCHED == "play" then
    cn = (f >= COIN_FRAME) and ((f - COIN_FRAME) % 1800 < 6)
    st = (f >= START_FRAME) and ((f - START_FRAME) % 1800 < 6)
    if f >= PLAY_FRAME then
      if f % 10 == 0 then dir = rnd(9) end
      du = (dir == 1 or dir == 5 or dir == 8)
      dd = (dir == 2 or dir == 6 or dir == 7)
      dl = (dir == 3 or dir == 5 or dir == 6)
      dr = (dir == 4 or dir == 7 or dir == 8)
      bt = (f % 23 < 5)
    end
    coin:set_value(cn and 1 or 0); start:set_value(st and 1 or 0)
    up:set_value(du and 1 or 0); dn:set_value(dd and 1 or 0); lf:set_value(dl and 1 or 0); rt:set_value(dr and 1 or 0)
    b1:set_value(bt and 1 or 0)
  elseif SCHED == "actions" then
    cn, st, du, dd, dl, dr, bt = act_on(f, "coin"), act_on(f, "start"), act_on(f, "up"), act_on(f, "down"), act_on(f, "left"), act_on(f, "right"), act_on(f, "b1")
    coin:set_value(cn and 1 or 0); start:set_value(st and 1 or 0)
    up:set_value(du and 1 or 0); dn:set_value(dd and 1 or 0); lf:set_value(dl and 1 or 0); rt:set_value(dr and 1 or 0)
    b1:set_value(bt and 1 or 0)
  end
  if inlog then
    local v1 = 0xffff
    if cn  then v1 = v1 & ~0x0100 end
    if st  then v1 = v1 & ~0x0080 end
    if du  then v1 = v1 & ~0x0001 end
    if dd  then v1 = v1 & ~0x0002 end
    if dl  then v1 = v1 & ~0x0004 end
    if dr  then v1 = v1 & ~0x0008 end
    if bt  then v1 = v1 & ~0x0010 end
    if v1 ~= last1 then inlog:write(string.format("%d %04x ffff\n", f + 1, v1)); last1 = v1 end
  end
  if FRAMES[f] then dump() end
  if f >= LAST + 1 then if wrlog then wrlog:close() end; if inlog then inlog:close() end; mach:exit() end
end)
