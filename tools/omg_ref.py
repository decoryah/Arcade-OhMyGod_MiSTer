#!/usr/bin/env python3
"""Reference renderer for ohmygod.cpp (Oh My God!, Naname de Magic!): MAME's screen_update written out literally.

    omg_ref.py <rom image> <state prefix> [out.png]       renders <prefix>.{ram300,ram700,pal,regs}, compares with <prefix>.rgb

The driver (src/mame/atlus/ohmygod.cpp, MAME 0.289):
  - one tilemap, 64 x 64 tiles of 8 x 8 (TILEMAP_SCAN_ROWS), opaque; tile word pair at 0x304000 + 4 * index:
    attr = word 0 (palette group = bits 11:8), code = word 1 (a 16384-tile ROM: the low 14 bits count);
    scroll x = scrollx_reg - 0x81ec, y = scrolly_reg - 0x81ef; palette index = group * 16 + pen (0..255)
  - sprites after the tilemap: 1024 entries of 4 words at 0x700000 (+ 0x2000 bytes with the sprite bank flag):
    x = word0 - 29, y = signed word1, colour = word2 & 15, code = word3 & 0xFFF, flip x = word3 bit 15;
    16 x 16, 4bpp, pen 0 transparent, palette index 512 + colour * 16 + pen; drawn in entry order (the last one wins)
  - the picture is the 320 x 240 window at x 96..415, y 0..239 of the 512 x 256 bitmap
  - palette: 1024 words, xGRB555
"""
import sys, os

W, H = 320, 240
X0 = 96                       # left edge of the visible window in the 512-pixel bitmap


def hexwords(path):
    return [int(l, 16) for l in open(path) if l.strip()]


def load_state(prefix):
    s = {}
    s["ram300"] = hexwords(prefix + ".ram300")
    s["ram700"] = hexwords(prefix + ".ram700")
    s["pal"] = hexwords(prefix + ".pal")
    # MAME converts the frame's pen indexes with the palette of the NEXT callback (see tools/lua/dump_state.lua)
    s["pal1"] = hexwords(prefix + ".pal1") if os.path.exists(prefix + ".pal1") else s["pal"]
    regs = [int(x) for x in open(prefix + ".regs").read().split()]
    s["frame"], s["scrollx"], s["scrolly"], s["spritebank"], s["sndbank"], s["ctrl"], s["wdog"] = regs[:7]
    s["flip"] = regs[7] if len(regs) > 7 else 0       # bit 14 of the sprite bank register (older dumps: not recorded)
    return s


def load_image(path):
    img = open(path, "rb").read()
    return {"chars": img[0x080000:0x100000], "sprites": img[0x100000:0x180000]}


def pal_rgb(w):
    r = (w >> 5) & 31
    g = (w >> 10) & 31
    b = w & 31
    return ((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2))


def render(st, gfx, scroll_sign=1, pal_key="pal1"):
    pal = [pal_rgb(w) for w in st[pal_key]]
    chars, sprites = gfx["chars"], gfx["sprites"]
    vram = st["ram300"][0x2000:0x4000]
    # the bitmap's visible window only: index = pal index
    idx = [[0] * W for _ in range(H)]

    # The screen flip (the hardware turns the picture 180 degrees; MAME does not implement it): the game then writes the scroll words
    # 39 / 273 higher and the sprite words 57 lower (x) and 17 higher (y) than for the unflipped picture, tile RAM and sprite codes as
    # they are (measured with MAME on Naname de Magic!'s Flip Screen DIP: with the constants taken out its picture equals MAME's
    # unflipped one pixel for pixel, tools/lua/probe_inputs.lua, docs/hardware.md); the picture is that one turned 180 degrees.
    flip = st.get("flip", 0)
    sx_eff = (st["scrollx"] - 0x81ec - (39 if flip else 0)) & 0x1ff
    sy_eff = (st["scrolly"] - 0x81ef - (273 if flip else 0)) & 0x1ff
    for y in range(H):
        my = (y + scroll_sign * sy_eff) & 0x1ff
        ty, fy = my >> 3, my & 7
        row = idx[y]
        for x in range(W):
            mx = (x + X0 + scroll_sign * sx_eff) & 0x1ff
            tx, fx = mx >> 3, mx & 7
            t = ty * 64 + tx
            attr, code = vram[2 * t], vram[2 * t + 1]
            code &= 0x3fff
            b = chars[code * 32 + fy * 4 + (fx >> 1)]
            pen = (b >> 4) if (fx & 1) == 0 else (b & 15)
            row[x] = ((attr >> 8) & 15) * 16 + pen

    base = 0x1000 if st["spritebank"] else 0
    spr = st["ram700"]
    for i in range(1024):
        o = base + 4 * i
        w0, w1, w2, w3 = spr[o], spr[o + 1], spr[o + 2], spr[o + 3]
        if flip:
            w0 = (w0 + 57) & 0xffff
            w1 = (w1 - 17) & 0xffff
        code = w3 & 0x0fff
        color = w2 & 15
        sx = w0 - 29
        sy = w1 - 65536 if w1 >= 32768 else w1
        flipx = w3 & 0x8000
        for r in range(16):
            y = sy + r
            if y < 0 or y >= H:
                continue
            for c in range(16):
                x = sx + c                       # bitmap x
                vx = x - X0
                if vx < 0 or vx >= W:
                    continue
                cc = 15 - c if flipx else c
                b = sprites[code * 128 + r * 8 + (cc >> 1)]
                pen = (b >> 4) if (cc & 1) == 0 else (b & 15)
                if pen:
                    idx[y][vx] = 512 + color * 16 + pen

    if flip:
        idx = [row[::-1] for row in idx[::-1]]
    out = bytearray(W * H * 3)
    for y in range(H):
        for x in range(W):
            out[(y * W + x) * 3:(y * W + x) * 3 + 3] = bytes(pal[idx[y][x]])
    return out


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    gfx = load_image(argv[1])
    st = load_state(argv[2])
    best = None
    for sign in (1, -1):
        out = render(st, gfx, sign)
        if os.path.exists(argv[2] + "." + os.environ.get("OMG_RGB", "rgb")):
            ref = open(argv[2] + "." + os.environ.get("OMG_RGB", "rgb"), "rb").read()
            diff = sum(1 for i in range(0, len(ref), 3) if ref[i:i + 3] != bytes(out[i:i + 3]))
            print("scroll sign %+d: %d of %d pixels differ" % (sign, diff, W * H))
            if best is None or diff < best[0]:
                best = (diff, sign, out)
        else:
            best = (0, sign, out)
            break
    if len(argv) > 3:
        import pngio
        pngio.write(argv[3], W, H, best[2])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
