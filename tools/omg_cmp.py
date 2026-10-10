#!/usr/bin/env python3
"""omg_cmp.py <rtl.ppm> <MAME .rgb> [diff.png]: pixel comparison of an RTL frame with MAME's frame (320 x 240).
Prints the number of differing pixels, their bounding box and the first few; exit status 1 if any differ."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

def read_ppm(path):
    d = open(path, "rb").read()
    # P6\nW H\n255\n
    parts = d.split(b"\n", 3)
    assert parts[0] == b"P6"
    w, h = [int(x) for x in parts[1].split()]
    return w, h, parts[3]

def main(argv):
    w, h, a = read_ppm(argv[1])
    b = open(argv[2], "rb").read()
    n = min(len(a), len(b)) // 3
    pts = [(i // w, i % w) for i in range(n) if a[i*3:i*3+3] != b[i*3:i*3+3]]
    print("%s: %d of %d pixels differ" % (os.path.basename(argv[1]), len(pts), w * h))
    if pts:
        ys = [p[0] for p in pts]; xs = [p[1] for p in pts]
        print("  bbox x %d..%d  y %d..%d" % (min(xs), max(xs), min(ys), max(ys)))
        rows = {}
        for y, x in pts:
            rows[y] = rows.get(y, 0) + 1
        print("  %d rows; first: %s" % (len(rows), sorted(rows.items())[:10]))
        for y, x in pts[:5]:
            i = y * w + x
            print("  (%d,%d) RTL %s MAME %s" % (x, y, tuple(a[i*3:i*3+3]), tuple(b[i*3:i*3+3])))
    if len(argv) > 3:
        import pngio
        d = bytearray(w * h * 3)
        for y, x in pts:
            d[(y*w+x)*3:(y*w+x)*3+3] = b"\xff\x00\xff"
        pngio.write(argv[3], w, h, bytes(d))
    return 1 if pts else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
