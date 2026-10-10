#!/usr/bin/env python3
"""Check the RAMs Quartus actually built against the depths the RTL declares.

    check_ram_depth.py <OhMyGod.fit.rpt> [--list]

A simulator evaluates an array exactly as declared; Quartus 17 does not always. A two-dimensional
unpacked array such as `logic [11:0] lbuf [2][288]` (576 words) was built 512 words deep, so bank 1's
pixels 224..287 landed on bank 0's pixels 0..63 -- invisible in every bench, and on the board each text
line's first eight characters reappeared at the right edge on alternate lines. Run this on every fit
report; it exits 1 if a listed memory is shallower than its minimum, or is missing.
"""
import re
import sys

# (instance name fragment, minimum words, minimum width)
EXPECT = [
    # the line buffer: {bank, x[8:0]} = 1024 words of 10 bits (a 2-D unpacked array would be built half as deep: see below)
    ("omg_video:u_video|omg_sdp:u_lb|altsyncram", 1024, 10),
    # the 68000 board's RAMs (omg_ram16: two byte-wide halves each)
    ("omg_main:u_main|omg_ram16:u_rama|altsyncram", 8192, 8),
    ("omg_main:u_main|omg_ram16:u_attr|altsyncram", 4096, 8),
    ("omg_main:u_main|omg_ram16:u_code|altsyncram", 4096, 8),
    ("omg_main:u_main|omg_ram16:u_ramb|altsyncram", 16384, 8),
    ("omg_main:u_main|omg_ram16:u_pal|altsyncram", 1024, 8),
    ("omg_main:u_main|omg_ram16:u_s0|altsyncram", 2048, 8),
    ("omg_main:u_main|omg_ram16:u_s1|altsyncram", 2048, 8),
    ("omg_main:u_main|omg_ram16:u_s2|altsyncram", 2048, 8),
    ("omg_main:u_main|omg_ram16:u_s3|altsyncram", 2048, 8),
    ("omg_main:u_main|omg_ram16:u_ramc|altsyncram", 8192, 8),
    ("omg_main:u_main|omg_ram16:u_ramd|altsyncram", 16384, 8),
    # the program cache
    ("omg_cache:u_cache|omg_sdp:u_dat|altsyncram", 8192, 16),
    ("omg_cache:u_cache|omg_sdp:u_tag|altsyncram", 1024, 6),
]


def main():
    path = sys.argv[1]
    ram = []
    for line in open(path, errors="replace"):
        if "|ALTSYNCRAM" not in line or not line.startswith(";"):
            continue
        f = [c.strip() for c in line.split(";")]
        # ; name ; type ; mode ; clocks ; words ; width ; words ; width ; ...
        try:
            ram.append((f[1], int(f[5]), int(f[6])))
        except (IndexError, ValueError):
            continue
    if "--list" in sys.argv:
        for n, w, b in ram:
            print("%6d x %-3d %s" % (w, b, n))
    bad = 0
    for frag, wmin, bmin in EXPECT:
        hits = [(n, w, b) for n, w, b in ram if frag in n]
        if not hits:
            print("MISSING  %-52s (expected >= %d x %d)" % (frag, wmin, bmin))
            bad += 1
            continue
        for n, w, b in hits:
            # a wide RAM may be split into several blocks side by side; only depth matters here
            ok = w >= wmin
            if not ok:
                bad += 1
            print("%s  %-52s %6d x %-3d (>= %d)" % ("ok     " if ok else "TOO SHALLOW", frag, w, b, wmin))
    print("%d problem(s)" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
