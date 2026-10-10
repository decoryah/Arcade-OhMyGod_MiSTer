#!/usr/bin/env python3
"""omg_diff.py <state prefix> <rom image> [out-prefix]: renders the state with omg_ref and reports where it differs from MAME's pixels
(bounding box, rows, a few pixels) and writes MAME's frame, ours and the difference as PNGs."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import omg_ref, pngio

def main(argv):
    prefix, rom = argv[1], argv[2]
    outp = argv[3] if len(argv) > 3 else prefix + "_d"
    gfx = omg_ref.load_image(rom)
    st = omg_ref.load_state(prefix)
    ours = omg_ref.render(st, gfx)
    ref = open(prefix + "." + os.environ.get("OMG_RGB", "rgb"), "rb").read()
    W, H = omg_ref.W, omg_ref.H
    pts = [(i // W, i % W) for i in range(W * H) if ref[i * 3:i * 3 + 3] != bytes(ours[i * 3:i * 3 + 3])]
    print("%d pixels differ; regs: scrollx=%04x scrolly=%04x spritebank=%d" % (len(pts), st["scrollx"], st["scrolly"], st["spritebank"]))
    if pts:
        ys = [p[0] for p in pts]; xs = [p[1] for p in pts]
        print("bbox: x %d..%d  y %d..%d" % (min(xs), max(xs), min(ys), max(ys)))
        rows = {}
        for y, x in pts:
            rows[y] = rows.get(y, 0) + 1
        print("rows with differences: %d; first rows: %s" % (len(rows), sorted(rows.items())[:12]))
        for y, x in pts[:8]:
            i = y * W + x
            print("  (%d,%d) MAME %s ours %s" % (x, y, tuple(ref[i * 3:i * 3 + 3]), tuple(ours[i * 3:i * 3 + 3])))
    d = bytearray(W * H * 3)
    for y, x in pts:
        d[(y * W + x) * 3:(y * W + x) * 3 + 3] = b"\xff\x00\xff"
    pngio.write(outp + "_mame.png", W, H, ref)
    pngio.write(outp + "_ours.png", W, H, bytes(ours))
    pngio.write(outp + "_diff.png", W, H, bytes(d))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
