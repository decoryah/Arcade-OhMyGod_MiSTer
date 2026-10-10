#!/usr/bin/env python3
"""omg_corpus.py <rom image> <states dir> [more dirs]: runs omg_ref on every state (f*.regs) and compares with MAME's pixels;
also reports the sprite load per frame (entries that touch the picture, the busiest line)."""
import sys, os, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import omg_ref

def sprite_load(st):
    base = 0x1000 if st["spritebank"] else 0
    spr = st["ram700"]
    per_line = [0] * omg_ref.H
    onscreen = 0
    for i in range(1024):
        o = base + 4 * i
        w0, w1, w3 = spr[o], spr[o + 1], spr[o + 3]
        sx = w0 - 29 - omg_ref.X0
        sy = w1 - 65536 if w1 >= 32768 else w1
        if sx <= -16 or sx >= omg_ref.W or sy <= -16 or sy >= omg_ref.H:
            continue
        onscreen += 1
        for r in range(16):
            y = sy + r
            if 0 <= y < omg_ref.H:
                per_line[y] += 1
    return onscreen, max(per_line)

def main(argv):
    gfx = omg_ref.load_image(argv[1])
    bad = 0
    n = 0
    worst_line = worst_on = 0
    for d in argv[2:]:
        for regs in sorted(glob.glob(os.path.join(d, "f*.regs"))):
            prefix = regs[:-5]
            st = omg_ref.load_state(prefix)
            out = omg_ref.render(st, gfx)
            ref = open(prefix + ".rgb", "rb").read() if os.path.exists(prefix + ".rgb") else None
            diff = -1 if ref is None else sum(1 for i in range(0, len(ref), 3) if ref[i:i + 3] != bytes(out[i:i + 3]))
            on, ml = sprite_load(st)
            worst_line = max(worst_line, ml); worst_on = max(worst_on, on)
            n += 1
            if diff != 0:
                bad += 1
            print("%-12s frame %5d  scroll %04x/%04x bank %d  diff %6d  sprites on screen %4d  busiest line %3d" %
                  (os.path.basename(d.rstrip("/")), st["frame"], st["scrollx"], st["scrolly"], st["spritebank"], diff, on, ml))
    print("%d states, %d with differences; most sprites on screen %d, most on one line %d" % (n, bad, worst_on, worst_line))
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
