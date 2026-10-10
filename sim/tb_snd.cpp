// OKI bench driver: tb_snd <image> <events> <out.wav> [seconds]
//   events: "<96 MHz clock> W <byte>" and "<clock> B <bank>" lines (tools/omg_oki_events.py)
// Writes a 48 kHz mono WAV of the chip's 14-bit output as it is (MAME's level), plus a summary.
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include "Vtb_snd_top.h"
#include "Vtb_snd_top__Dpi.h"
#include "verilated.h"
#include "svdpi.h"

struct Ev { uint64_t clk; char kind; int val; };

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: tb_snd image events out.wav [seconds]\n"); return 2; }
    double seconds = argc > 4 ? atof(argv[4]) : 10.0;
    FILE* f = fopen(argv[1], "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", argv[1]); return 2; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> img(n);
    if (fread(img.data(), 1, n, f) != (size_t)n) return 2;
    fclose(f);
    std::vector<Ev> ev;
    f = fopen(argv[2], "r");
    if (!f) { fprintf(stderr, "cannot open %s\n", argv[2]); return 2; }
    unsigned long long c; char k; int v;
    while (fscanf(f, "%llu %c %d", &c, &k, &v) == 3) ev.push_back({c, k, v});
    fclose(f);

    Vtb_snd_top* t = new Vtb_snd_top;
    svSetScope(svGetScopeFromName("TOP.tb_snd_top"));
    t->clk = 0; t->init = 1; t->rst = 1; t->wr = 0; t->din = 0; t->bank = 0;
    auto tick = [&]() { t->clk = 1; t->eval(); t->clk = 0; t->eval(); };
    for (int i = 0; i < 200; i++) tick();
    t->init = 0;
    while (!t->mem_ready) tick();
    for (int i = 0; i < 100; i++) tick();
    for (long wa = 0; wa < 0x1C0000 && (size_t)(2 * wa + 1) < img.size(); wa++)
        tb_sdram_write((int)wa, img[2 * wa] | (img[2 * wa + 1] << 8));
    t->rst = 0;

    std::vector<int16_t> audio;
    uint64_t total = (uint64_t)(seconds * 96e6);
    size_t ei = 0;
    long writes = 0;
    int peak = 0;
    int last_dout = -1;
    uint64_t next_wr = 0;
    const bool dbg = getenv("SNDDBG") != nullptr;
    const char* natpath = getenv("SNDNATIVE");              // the chip's own samples (one per 6336 clocks), for exact comparisons
    std::vector<std::pair<uint64_t,int>> chg;
    int prev_snd = 0;
    for (uint64_t cl = 0; cl < total; cl++) {
        t->wr = 0;
        while (ei < ev.size() && ev[ei].clk <= cl && cl >= next_wr) {
            if (ev[ei].kind == 'W') {                                                            // one write per clock
                t->wr = 1; t->din = ev[ei].val; writes++;
                if (getenv("SNDDBG")) fprintf(stderr, "clk %llu (%.4f s): write %02x\n", (unsigned long long)cl, cl / 96e6, ev[ei].val);
                next_wr = cl + 300;                                                              // the 68000 cannot write twice within 300 clocks
                ei++; break;
            }
            t->bank = ev[ei].val; ei++;
        }
        tick();
        if (natpath) {
            int sv = t->snd & 0x3fff; if (sv & 0x2000) sv -= 0x4000;
            if (sv != prev_snd) { chg.push_back({cl, sv}); prev_snd = sv; }
        }
        if (dbg) {
            if ((int)t->dout != last_dout) {
                last_dout = t->dout;
                fprintf(stderr, "clk %llu (%.4f s): status %02x\n", (unsigned long long)cl, cl / 96e6, last_dout);
            }
        }
        if (cl % 2000 == 1999) {
            int s = t->snd & 0x3fff;
            if (s & 0x2000) s -= 0x4000;
            audio.push_back((int16_t)s);
            if (abs(s) > peak) peak = abs(s);
        }
    }
    if (natpath && !chg.empty()) {
        // the chip updates its output every 6336 clocks; sample in the middle of each hold
        uint64_t phase = chg[0].first % 6336;
        FILE* nf = fopen(natpath, "w");
        size_t ci = 0; int cur = 0;
        for (uint64_t k = 0; phase + 3168 + 6336 * k < total; k++) {
            uint64_t c = phase + 3168 + 6336 * k;
            while (ci < chg.size() && chg[ci].first <= c) cur = chg[ci++].second;
            fprintf(nf, "%llu %d\n", (unsigned long long)c, cur);
        }
        fclose(nf);
    }
    FILE* w = fopen(argv[3], "wb");
    uint32_t nb = audio.size() * 2, rate = 48000, br = rate * 2, sixteen = 16, riff = 36 + nb;
    uint16_t one = 1, bits = 16, ba = 2, fmt = 1;
    fwrite("RIFF", 1, 4, w); fwrite(&riff, 4, 1, w); fwrite("WAVEfmt ", 1, 8, w); fwrite(&sixteen, 4, 1, w);
    fwrite(&fmt, 2, 1, w); fwrite(&one, 2, 1, w); fwrite(&rate, 4, 1, w); fwrite(&br, 4, 1, w); fwrite(&ba, 2, 1, w); fwrite(&bits, 2, 1, w);
    fwrite("data", 1, 4, w); fwrite(&nb, 4, 1, w); fwrite(audio.data(), 2, audio.size(), w);
    fclose(w);
    fprintf(stderr, "%zu samples, %ld OKI writes played, peak %d\n", audio.size(), writes, peak);
    delete t;
    return 0;
}
