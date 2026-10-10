#!/usr/bin/env python3
"""wav_slice.py <in.wav> <out.wav> <t_start s> <t_end s>: a time slice of a 16-bit WAV (any channel count)."""
import sys, wave

def main():
    src, dst, t0, t1 = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
    with wave.open(src, "rb") as w:
        rate, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
        a, b = int(t0 * rate), int(t1 * rate)
        w.setpos(min(a, w.getnframes()))
        data = w.readframes(max(0, min(b, w.getnframes()) - a))
    with wave.open(dst, "wb") as o:
        o.setnchannels(ch); o.setsampwidth(sw); o.setframerate(rate)
        o.writeframes(data)
    print("%s: %.2f s of %d channel(s) at %d Hz" % (dst, len(data) / (sw * ch * rate), ch, rate))

if __name__ == "__main__":
    main()
