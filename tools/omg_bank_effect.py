#!/usr/bin/env python3
"""How much does the OSD's "Sprite bank flip" option change the picture?

    omg_bank_effect.py <game> <flip line> [states folder]       (default folder: work/states/<game>)

From the IRQ at the start of vertical blank the game builds the next sprite list into the hidden half of the sprite RAM and
flips the bank flag ~46 line times later: picture line 30 of Oh My God! (use 29 for the core's own raster), 31 or 45 / 46 for
Naname de Magic! (tools/lua/ramwrites.lua; its log lines count from the start of vblank, true line = (logged + 240) % 256).  MAME draws the frame at its end, so its picture (A) has the new list (the displayed bank at the end of the
frame) throughout.  A chip reading the flag live (the core's default, "Live") shows the previous list above the flip line and
the new one below it (C); the core's "At vblank" option shows the previous list for the whole frame (B).  For every MAME state of
the folder (taken at the end of a frame, the flag already flipped; the hidden bank then holds the previous frame's list) this
renders A, B and C with the reference renderer and counts the pixels of B and C that differ from A.
"""
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # <root>/mister/tools -> <root>
sys.path.insert(0, HERE)
import omg_ref


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    game, flip_line = argv[0], int(argv[1])
    folder = argv[2] if len(argv) > 2 else os.path.join(ROOT, 'work', 'states', game)
    gfx = omg_ref.load_image(os.path.join(ROOT, 'work', game + '.rom'))
    W, H = omg_ref.W, omg_ref.H
    rows = []
    for reg in sorted(glob.glob(os.path.join(folder, 'f*.regs'))):
        st = omg_ref.load_state(reg[:-5])
        a = omg_ref.render(st, gfx, 1)
        st2 = dict(st)
        st2["spritebank"] = 1 - st["spritebank"]
        b = omg_ref.render(st2, gfx, 1)
        c = bytearray(a)
        c[:flip_line * W * 3] = b[:flip_line * W * 3]

        def count(p, q):
            diff = [i // 3 for i in range(0, len(p), 3) if p[i:i + 3] != q[i:i + 3]]
            return len(diff), len(set(i // W for i in diff))
        (nb, lb), (nc, lc) = count(a, b), count(a, c)
        rows.append((st["frame"], nb, nc))
        print("frame %5d: At vblank vs MAME %5d px (%3d lines)   Live vs MAME %5d px (%3d lines)" % (st["frame"], nb, lb, nc, lc), flush=True)
    nb = sum(1 for r in rows if r[1])
    nc = sum(1 for r in rows if r[2])
    print("%s: %d states; At vblank differs from MAME in %d, Live in %d; most %d / %d px of %d" % (
        game, len(rows), nb, nc, max(r[1] for r in rows), max(r[2] for r in rows), W * H))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
