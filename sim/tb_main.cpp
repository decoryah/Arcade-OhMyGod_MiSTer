// Whole-machine bench driver (sim/tb_top.sv).
//   Vtb_top <game.rom> <frames> <out-prefix> [+state=<MAME state prefix>] [+load=rtl] [+every=N] [+first=N]
//           [+inputs=<file>] [+coin=<frame>] [+trace] [+wav] [+audio_from=<frame>] [+dly=<frames>]
// Writes <out>.fNNNN.ppm (the 320 x 240 picture of every frame from +first, every +every-th), a status line per frame and
// <out>.wav (48 kHz) with +wav.
//   +state=P   preload the RAMs from P.{ram300,ram700,pal1,regs} and keep the 68000 in reset (frozen-state bench)
//   +load=rtl  push the image through the RTL loader instead of preloading the SDRAM
//   +inputs=F  replay MAME's port values: lines "<frame> <p1 hex> <p2 hex>" (tools/lua/dump_state.lua INPUTLOG), taking effect
//              at that frame's vertical blank
//   +coin=N    scripted coin at frame N, start at N+60 (when there is no input file)
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include "Vtb_top.h"
#include "Vtb_top__Dpi.h"
#include "verilated.h"
#include "svdpi.h"

static std::vector<uint8_t> load_file(const char* p) {
    std::vector<uint8_t> v;
    FILE* f = fopen(p, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", p); exit(2); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    v.resize(n);
    if (fread(v.data(), 1, n, f) != (size_t)n) exit(2);
    fclose(f);
    return v;
}

static void write_ppm(const char* path, const uint8_t* rgb, int w, int h) {
    FILE* f = fopen(path, "wb");
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    fwrite(rgb, 1, (size_t)w * h * 3, f);
    fclose(f);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: tb_top game.rom frames out-prefix [+state=..]\n"); return 2; }
    const char* rom = argv[1];
    int frames = atoi(argv[2]);
    std::string outp = argv[3];
    bool state_mode = false, load_rtl = false, trace = false, wav = false, sb_latch_arg = false, fast = false;
    int every = 1, first = 1, coin_frame = -1, audio_from = 0, dly = 0;
    const char* inputs = nullptr;
    for (int i = 4; i < argc; i++) {
        if (!strncmp(argv[i], "+state=", 7)) state_mode = true;
        else if (!strcmp(argv[i], "+load=rtl")) load_rtl = true;
        else if (!strcmp(argv[i], "+trace")) trace = true;
        else if (!strcmp(argv[i], "+wav")) wav = true;
        else if (!strcmp(argv[i], "+sblatch")) sb_latch_arg = true;
        else if (!strncmp(argv[i], "+every=", 7)) every = atoi(argv[i] + 7);
        else if (!strncmp(argv[i], "+first=", 7)) first = atoi(argv[i] + 7);
        else if (!strncmp(argv[i], "+coin=", 6)) coin_frame = atoi(argv[i] + 6);
        else if (!strncmp(argv[i], "+inputs=", 8)) inputs = argv[i] + 8;
        else if (!strncmp(argv[i], "+audio_from=", 12)) audio_from = atoi(argv[i] + 12);
        else if (!strncmp(argv[i], "+dly=", 5)) dly = atoi(argv[i] + 5);
        else if (!strcmp(argv[i], "+fast")) fast = true;
    }
    auto img = load_file(rom);
    Vtb_top* t = new Vtb_top;
    svSetScope(svGetScopeFromName("TOP.tb_top"));

    // MAME's recorded port values, by frame
    std::vector<std::pair<int, std::pair<uint16_t, uint16_t>>> inlog;
    if (inputs) {
        FILE* f = fopen(inputs, "r");
        if (!f) { fprintf(stderr, "cannot open %s\n", inputs); return 2; }
        int fr; unsigned a, b;
        while (fscanf(f, "%d %x %x", &fr, &a, &b) == 3) inlog.push_back({fr, {(uint16_t)a, (uint16_t)b}});
        fclose(f);
    }
    size_t inpos = 0;
    uint16_t p1 = 0xFFFF, p2 = 0xFFFF;

    t->p1_in = 0xFFFF; t->p2_in = 0xFFFF; t->dsw1_in = 0xFFFF; t->dsw2_in = 0xFFFF;
    t->wdog_limit = fast ? 16000000 : 288000000;      // +fast: the first watchdog (the cold start's wait for it) is 10 frames instead of 3 s
    t->dl_we = 0; t->dl_addr = 0; t->dl_data = 0;
    t->clk = 0;
    t->init = 1; t->rst = 1; t->cpu_hold = 1; t->sb_latch = 0;

    auto step = [&]() { t->clk = !t->clk; t->eval(); };
    auto run_cycles = [&](int n) { for (int i = 0; i < n; i++) { step(); step(); } };

    run_cycles(200);
    t->init = 0;
    while (!t->mem_ready) run_cycles(1);
    run_cycles(100);

    const int ROMWORDS = 0x1C0000;                       // the image's words that live in the SDRAM
    if (!load_rtl) {
        for (long wa = 0; wa < ROMWORDS && (size_t)(2 * wa + 1) < img.size(); wa++) {
            uint16_t w = img[2 * wa] | (img[2 * wa + 1] << 8);
            tb_sdram_write((int)wa, w);
        }
        tb_cfg(img.size() > 0x380000 ? (img[0x380000] & 1) : 0);
        fprintf(stderr, "image preloaded (%zu bytes)\n", img.size());
    } else {
        size_t n = img.size();
        for (size_t i = 0; i < n; ) {
            if (!t->dl_wait) { t->dl_we = 1; t->dl_addr = i; t->dl_data = img[i]; i++; }
            else t->dl_we = 0;
            run_cycles(1);
            t->dl_we = 0;
            run_cycles(2);
        }
        while (t->dl_busy) run_cycles(1);
        run_cycles(100);
        long bad = 0;
        for (long wa = 0; wa < ROMWORDS; wa++) {
            uint16_t w = img[2 * wa] | (img[2 * wa + 1] << 8);
            if ((uint16_t)tb_sdram_read((int)wa) != w) { if (bad < 10) fprintf(stderr, "mismatch at word %lx\n", wa); bad++; }
        }
        fprintf(stderr, "image loaded through the RTL loader: %ld of %d words differ\n", bad, ROMWORDS);
    }

    if (state_mode) {
        // the state's registers: "<frame> <scrollx> <scrolly> <spritebank> <sndbank> <ctrl> <wdog>"
        std::string rp;
        for (int i = 4; i < argc; i++) if (!strncmp(argv[i], "+state=", 7)) rp = std::string(argv[i] + 7) + ".regs";
        FILE* rf = fopen(rp.c_str(), "r");
        if (!rf) { fprintf(stderr, "cannot open %s\n", rp.c_str()); return 2; }
        int fr, sx, sy, sb, a, b, c;
        if (fscanf(rf, "%d %d %d %d %d %d %d", &fr, &sx, &sy, &sb, &a, &b, &c) != 7) { fprintf(stderr, "bad %s\n", rp.c_str()); return 2; }
        fclose(rf);
        tb_regs(sx, sy, sb);
        fprintf(stderr, "state of frame %d: scroll %04x / %04x, sprite bank %d\n", fr, sx, sy, sb);
    }
    t->sb_latch = sb_latch_arg ? 1 : 0;
    t->rst = 0;
    t->cpu_hold = state_mode ? 1 : 0;
    if (dly > 0) { t->cpu_hold = 1; }

    std::vector<uint8_t> fb(320 * 240 * 3, 0);
    std::vector<int16_t> audio;
    int col = 0, row = 0, nframe = 0;
    bool prev_hblank = true, prev_vblank = true;
    long ovr = 0, irqs = 0, wd = 0, irq_off = 0;      // irq_off re-bases the vertical-blank count to MAME's machine frame after a +fast cold start
    bool pirq = false, pwd = false, povr = false;
    long clocks = 0, busy_run = 0, busy_max = 0, snd_div = 0, oki_writes = 0;
    bool poki = false;
    FILE* tf = trace ? fopen((outp + ".trace").c_str(), "w") : nullptr;
    uint64_t guard = (uint64_t)(frames + 4) * 1600000ULL;

    auto set_inputs_for_frame = [&](int fr) {
        if (inputs) {
            while (inpos < inlog.size() && inlog[inpos].first <= fr) { p1 = inlog[inpos].second.first; p2 = inlog[inpos].second.second; inpos++; }
        } else if (coin_frame >= 0) {
            p1 = 0xFFFF;
            if (fr >= coin_frame && fr < coin_frame + 6) p1 &= ~0x0100;
            if (fr >= coin_frame + 60 && fr < coin_frame + 66) p1 &= ~0x0080;
        }
        t->p1_in = p1; t->p2_in = p2;
    };

    while (nframe < frames + 1 && (uint64_t)clocks < guard) {
        step();                                          // clk 1 -> rising edge evaluated
        if (t->clk) {
            clocks++;
            if (dly > 0 && nframe >= dly) { t->cpu_hold = state_mode ? 1 : 0; dly = 0; }
            if (t->dbg_ovr && !povr) ovr++;
            povr = t->dbg_ovr;
            if (t->dbg_irq && !pirq) { irqs++; set_inputs_for_frame((int)(irqs + irq_off)); }
            pirq = t->dbg_irq;
            if (t->dbg_wdog && !pwd) {
                wd++;
                if (fast && wd == 1) {       // the cold start's wait is over: from here on the frame numbers are MAME's (it resets at 3.000 s)
                    irq_off = 180 - irqs;
                    t->wdog_limit = 288000000;
                    fprintf(stderr, "cold start: watchdog reset after %ld vertical blanks, numbering re-based to MAME frame 180\n", irqs);
                }
            }
            pwd = t->dbg_wdog;
            if (t->oki_wr && !poki) { oki_writes++; if (tf) fprintf(tf, "OKI %d %02x bank %x\n", nframe, t->oki_din, t->oki_bank); }
            poki = t->oki_wr;
            busy_run = t->dbg_render_busy ? busy_run + 1 : 0;
            if (busy_run > busy_max) busy_max = busy_run;
            if (tf && t->trc_stb) fprintf(tf, "%c %06x %04x %d%d\n", t->trc_rw ? 'R' : 'W', (uint32_t)t->dbg_addr << 1, t->trc_data, (t->trc_be >> 1) & 1, t->trc_be & 1);
            if (t->dbg_halted) { fprintf(stderr, "CPU HALTED at frame %d\n", nframe); break; }
            if (wav && nframe >= audio_from && ++snd_div == 2000) {          // 96 MHz / 2000 = 48 kHz
                snd_div = 0;
                int s = t->snd & 0x3fff;
                if (s & 0x2000) s -= 0x4000;                                 // the 14-bit signed sample, MAME's level as it is
                audio.push_back((int16_t)s);
            }
            if (t->ce_pix) {
                bool hb = t->hblank, vb = t->vblank;
                if (!hb && !vb) {
                    if (col < 320 && row < 240) {
                        uint32_t c = t->rgb;
                        fb[(row * 320 + col) * 3 + 0] = (c >> 16) & 255;
                        fb[(row * 320 + col) * 3 + 1] = (c >> 8) & 255;
                        fb[(row * 320 + col) * 3 + 2] = c & 255;
                    }
                    col++;
                }
                if (hb && !prev_hblank && !vb) { row++; col = 0; }
                if (vb && !prev_vblank) {
                    const long mf = irqs + irq_off;                                     // MAME's machine frame: the picture that ends at vertical blank mf
                    if (mf >= first && ((mf - first) % every) == 0) {
                        char p[512]; snprintf(p, sizeof p, "%s.f%05ld.ppm", outp.c_str(), mf);
                        write_ppm(p, fb.data(), 320, 240);
                    }
                    if (state_mode || nframe % 50 == 0 || nframe < 4)
                        fprintf(stderr, "frame %d: rows %d, overruns %ld, irqs %ld, watchdog resets %ld, longest render %ld clocks, OKI writes %ld\n",
                                nframe, row, ovr, irqs, wd, busy_max, oki_writes);
                    busy_max = 0;
                    nframe++;
                    row = 0; col = 0;
                }
                if (vb) { row = 0; col = 0; }
                prev_hblank = hb; prev_vblank = vb;
            }
        }
    }
    if (wav && !audio.empty()) {
        FILE* f = fopen((outp + ".wav").c_str(), "wb");
        uint32_t n = audio.size() * 2, rate = 48000, br = rate * 2;
        uint16_t one = 1, bits = 16, ba = 2, fmt = 1; uint32_t sixteen = 16, riff = 36 + n;
        fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f); fwrite(&sixteen, 4, 1, f);
        fwrite(&fmt, 2, 1, f); fwrite(&one, 2, 1, f); fwrite(&rate, 4, 1, f); fwrite(&br, 4, 1, f); fwrite(&ba, 2, 1, f); fwrite(&bits, 2, 1, f);
        fwrite("data", 1, 4, f); fwrite(&n, 4, 1, f); fwrite(audio.data(), 2, audio.size(), f);
        fclose(f);
        fprintf(stderr, "audio: %zu samples\n", audio.size());
    }
    if (tf) fclose(tf);
    fprintf(stderr, "done: %d frames, %ld clocks, overruns %ld\n", nframe, clocks, ovr);
    delete t;
    return 0;
}
