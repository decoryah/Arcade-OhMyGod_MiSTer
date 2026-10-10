#!/usr/bin/env python3
"""Compare the RTL's OKI output with MAME's, sample for sample.

    omg_oki_fit.py <mame.wav at 500000 Hz> <rtl.nat> <window start s> <taps J> <MAME native rate, 15151>

  1. MAME is run with `-samplerate 500000 -wavwrite` (33 x the chip's rate, so its resampler hands out the chip's own
     samples with a smooth curve between): work/mame/run_sr.sh.
  2. sim/tb_snd with SNDNATIVE=<file> writes the chip's samples, one per 6336 clocks (mid-hold).
  3. This fits MAME's stream as a short FIR of the RTL's samples (x16) and prints the residual.  A residual of ~0.01 % and
     a tap sum of 1.000 mean the two chips decode the same samples at the same level.

MAME's OKI runs at 15151 Hz, the clock / 132 truncated to an integer stream rate (the chip itself is 15151.515 Hz, which is
what the RTL does); give 15151 here or the fit drifts by 34 ppm and fails.
"""
import wave, struct, sys, math
yw = wave.open(sys.argv[1]); ny = yw.getnframes()
y = struct.unpack('<%dh' % ny, yw.readframes(ny))
t0 = float(sys.argv[3]); rate = yw.getframerate()
nat = [tuple(map(int, l.split())) for l in open(sys.argv[2])]
J = int(sys.argv[4]); mame_rate = float(sys.argv[5])            # MAME's native sample rate (integer-truncated clock / 132)
def solve(A, b):
    n = len(b); M = [row[:] + [b[i]] for i, row in enumerate(A)]
    for i in range(n):
        p = max(range(i, n), key=lambda r: abs(M[r][i])); M[i], M[p] = M[p], M[i]
        for r in range(i+1, n):
            f = M[r][i] / M[i][i]
            for c in range(i, n+1): M[r][c] -= f * M[i][c]
    x = [0.0]*n
    for i in range(n-1, -1, -1):
        x[i] = (M[i][n] - sum(M[i][c]*x[c] for c in range(i+1, n))) / M[i][i]
    return x
xs = [16.0 * v for c, v in nat]
n0 = (t0 + nat[0][0] / 96e6) * rate
step = rate / mame_rate
def yat(p):
    i = int(math.floor(p)); f = p - i
    return y[i] * (1 - f) + y[i + 1] * f
def fit(d, w0, w1):
    n = 2*J + 1
    A = [[0.0]*n for _ in range(n)]; bb = [0.0]*n; rows = []
    for k in range(w0, w1):
        r = [xs[k + j] for j in range(-J, J + 1)]
        t = yat(n0 + k * step + d)
        rows.append((r, t))
        for i in range(n):
            bb[i] += r[i] * t
            for j in range(i, n): A[i][j] += r[i] * r[j]
    for i in range(n):
        for j in range(i): A[i][j] = A[j][i]
    h = solve(A, bb)
    e = sum((t - sum(hi * ri for hi, ri in zip(h, r))) ** 2 for r, t in rows)
    tot = sum(t * t for r, t in rows)
    return math.sqrt(e / tot), h
N = len(nat)
best = min((fit(d, J + 100, N - J - 100)[0], d) for d in [x * 0.5 for x in range(-120, 121)])
rel, d = best
rel, h = fit(d, J + 100, N - J - 100)
print("mame native rate %.1f Hz: best delay %+.1f y-samples, residual %.3f%% of signal rms" % (mame_rate, d, 100 * rel))
print("taps:", " ".join("%.4f" % v for v in h), " sum %.4f" % sum(h))
