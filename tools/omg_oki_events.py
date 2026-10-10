#!/usr/bin/env python3
"""omg_oki_events.py <writes.log> <game> <t_start s> <t_end s>: the OKI M6295's write events of a MAME run
(tools/lua/dump_state.lua WRLOG) between two machine times, as "<96 MHz clock since t_start> W <byte>" / "<clock> B <bank>" lines
for sim/tb_snd.  The bank in force at t_start is emitted first, at clock 0.

A log line is "<machine frame> <raster line 0..255, from the start of vertical blank> <kind> <address> <data> <mask>"; kind OK = a write into B00000-B00001, CT = the
control register 900000 (the bank is bits 7:4 of the low byte on Oh My God!, 3:0 on Naname de Magic!).  `frame` is the frame
notifier's machine frame (it steps at line 240) and the raster line is taken from the machine time modulo 1/60 s, so the time of
a write is (frame - (line >= 240)) + line / 256 frames of 1/60 s."""
import sys


def main():
    path, game = sys.argv[1], sys.argv[2]
    t0, t1 = float(sys.argv[3]), float(sys.argv[4])
    shift = 0 if game == "naname" else 4
    bank = 0
    out = []
    n = 0
    for line in open(path):
        p = line.split()
        if len(p) != 6:
            continue
        try:
            f, ln = int(p[0]), int(p[1])
            kind, data, mask = p[2], int(p[4], 16), int(p[5], 16)
        except ValueError:
            continue
        k = f - (1 if ln >= 240 else 0)
        t = (k + ln / 256.0) / 60.0
        if kind == "CT" and (mask & 0x00ff):
            b = (data >> shift) & 15
            if t < t0:
                bank = b
                continue
        elif kind != "OK" or not (mask & 0x00ff):
            continue
        if t < t0:
            continue
        if t >= t1:
            break
        clk = int(round((t - t0) * 96e6))
        if kind == "OK":
            out.append("%d W %d" % (clk, data & 0xff))
        else:
            out.append("%d B %d" % (clk, (data >> shift) & 15))
        n += 1
    print("0 B %d" % bank)
    for l in out:
        print(l)
    sys.stderr.write("%d events in [%.3f, %.3f) s, bank %d at the start\n" % (n, t0, t1, bank))


if __name__ == "__main__":
    main()
