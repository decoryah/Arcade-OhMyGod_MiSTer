// End-to-end bench of the MiSTer top (OhMyGod.sv): plays the HPS.  It
//   * resets, waits for the PLL stand-in and the memory,
//   * loads the ROM image (MRA index 0): streamed through the ioctl port a byte per STRIDE clocks and held off by ioctl_wait, or
//     (FAST=1) the way Main_MiSTer does it for address= on the <rom>: the image copied into the DDR3 at byte 0x32000000 and a
//     download that carries no bytes, only a start address = the image's length; the core then replays it into the loader,
//   * compares every word of the image with the SDRAM chip's array (the loader's work),
//   * checks how the inputs reach the board's ports (joysticks, keyboard; BTN=1 prints the table),
//   * sets OSD options and runs frames, capturing the picture as the scaler gets it (VGA_*, 320 x 240) and checking the raster
//     (frame period, rows, geometry), also with the scandoubler on (FX / FSD),
//   * with SCALE / AR / HW / HH set, checks the size the core asks the HDMI scaler for (Scale option: framework's video_freak)
//     against the integer-scaling rule worked out here from the picture's rows and width,
//   * PICS=230,280: writes the picture of those MAME machine frames (the watchdog reset of the cold start numbers them: the
//     vertical blank that ends frame 180 + n is the n-th after the reset) as <prefix>.fNNNNN.ppm, for tools/omg_cmp.py.
//
//   tb_emu <image> <frames after load> <out-prefix>
// <image> is the flat image (work/<game>.rom, 0x380010 bytes).
#include "Vtb_emu_top.h"
#include "Vtb_emu_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>
#include <vector>

static Vtb_emu_top *dut;
static unsigned long long cycles = 0;
#define HPSV(n) dut->rootp->tb_emu_top__DOT__u_emu__DOT__hps_io__DOT__##n
#define EMUV(n) dut->rootp->tb_emu_top__DOT__u_emu__DOT__##n
static inline void tick() { dut->CLK_50M = 0; dut->eval(); dut->CLK_50M = 1; dut->eval(); cycles++; }

static const int VIS_W = 320, VIS_H = 240;
static const long IMG_LEN = 0x380010;
static const unsigned long long LINE_CLK = 16ull * 384, FRAME_CLK = LINE_CLK * 260;
static std::vector<unsigned> frame_now(VIS_W * VIS_H), frame_last(VIS_W * VIS_H);
// the picture as it comes, whatever its size (CRT Adjust changes it): rows of RAW_W pixels, the last finished frame and its size
static const int RAW_W = 700, RAW_H = 520;
static std::vector<unsigned> raw_now(RAW_W * RAW_H), raw_last(RAW_W * RAW_H);
static int raw_col = 0, raw_maxc = 0, raw_w = 0, raw_h = 0;
static int de_count = 0, frames_done = 0, de_last_count = 0;
// the framework's scandoubler (Scandoubler Fx, forced_scandoubler): every line twice, HQ2x also twice as wide
static int sd_mul = 1; static bool sd_hq = false;
static bool prev_vs = false;
static unsigned long long last_frame_cycle = 0, frame_period = 0;
static std::vector<unsigned long long> periods;
static bool record_periods = false;
static long long audio_nonzero = 0;
static unsigned errors = 0;
static std::set<int> pics;                      // machine frames to write
static bool wd_seen = false, prev_wd = false; static int vs_since_wd = 0;
static std::string prefix;

static void write_ppm(const char *path, const std::vector<unsigned> &px, int w, int h) {
    FILE *f = fopen(path, "wb"); if (!f) return;
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    for (int i = 0; i < w * h; i++) { unsigned v = px[i]; fputc((v >> 16) & 255, f); fputc((v >> 8) & 255, f); fputc(v & 255, f); }
    fclose(f);
}

// the geometry of the analog picture as the monitor gets it
static bool g_prev_hs = false, g_prev_de = false;
static unsigned long long g_hs_clk = 0, g_de_clk = 0;
static int g_rows = 0, g_lines_frame = 0; static long g_first = -1; static unsigned long long g_vs_clk = 0;
static long g_smin = 1 << 30, g_smax = -1, g_wmin = 1 << 30, g_wmax = -1;
static int geo_rows = 0, geo_lines = 0; static long geo_first = -1;
static long geo_smin = 0, geo_smax = 0, geo_wmin = 0, geo_wmax = 0;

// LINEDBG=<n>: the dots of one picture line at three places -- the core's output, CRT Adjust's output and the framework's VGA output
struct Dot { int blank; unsigned rgb; };
static std::vector<Dot> ld_core, ld_ca, ld_vga;
struct Edge { const char *name; long t; };
static std::vector<Edge> ld_edges; static unsigned long long ld_t0 = 0;
static int ld_line = -1, ld_frames = 0, ld_target = 4; static bool line_start_flag = false;
static void linedbg_report() {
    auto rep = [](const char *name, const std::vector<Dot> &v) {
        int first = -1, act = 0, nb0 = -1, nb1 = -1;
        for (size_t i = 0; i < v.size(); i++) {
            if (!v[i].blank) { if (first < 0) first = (int)i; act++; }
            if (v[i].rgb && !v[i].blank) { if (nb0 < 0) nb0 = (int)i; nb1 = (int)i; }
        }
        printf("  %-5s %4zu dots in the line, active from dot %d for %d dots, non-black picture dots %d .. %d (", name, v.size(), first, act, nb0, nb1);
        for (int i = (first < 0 ? 0 : first); i < (first < 0 ? 0 : first) + 10 && i < (int)v.size(); i++) printf("%s%06x", i ? " " : "", v[i].rgb);
        printf(" ...)\n");
    };
    printf("line %d of the frame:\n", ld_line);
    rep("core", ld_core); rep("crt", ld_ca); rep("vga", ld_vga);
    printf("  edges in clocks after the line start (16 clocks a dot):");
    for (auto &e : ld_edges) printf(" %s@%ld(%.2f)", e.name, e.t, e.t / 16.0);
    printf("\n");
}
static void linedbg_watch(bool hs_rise) {
    static bool on = false; static int line = 0;
    if (ld_line < 0) return;
    if (dut->VGA_VS && !prev_vs) { line = 0; ld_frames++; }
    if (hs_rise) { if (on) { on = false; if (ld_frames == ld_target) { linedbg_report(); ld_line = -1; return; } } line++; if (line == ld_line) { on = true; ld_t0 = cycles; line_start_flag = true; ld_core.clear(); ld_ca.clear(); ld_vga.clear(); } }
    if (!on) return;
    {   static int p_core = -1, p_ca = -1, p_de = -1;
        int c = (int)(EMUV(hblank) | EMUV(vblank)), a = (int)(EMUV(ca_hblank) | EMUV(ca_vblank)), d = dut->VGA_DE;
        long t = (long)(cycles - ld_t0);
        if (line_start_flag) { p_core = c; p_ca = a; p_de = d; line_start_flag = false; ld_edges.clear(); }
        if (c != p_core) ld_edges.push_back({c ? "core_blank_on" : "core_blank_off", t});
        if (a != p_ca)   ld_edges.push_back({a ? "crt_blank_on" : "crt_blank_off", t});
        if (d != p_de)   ld_edges.push_back({d ? "vga_de_on" : "vga_de_off", t});
        p_core = c; p_ca = a; p_de = d;
    }
    if (EMUV(ce_pix)) ld_core.push_back({(int)(EMUV(hblank) | EMUV(vblank)), (unsigned)EMUV(rgb)});
    if (EMUV(ca_ce)) ld_ca.push_back({(int)(EMUV(ca_hblank) | EMUV(ca_vblank)), (unsigned)EMUV(vid_rgb)});
    if (dut->CE_PIXEL) ld_vga.push_back({!dut->VGA_DE, ((unsigned)dut->VGA_R << 16) | ((unsigned)dut->VGA_G << 8) | dut->VGA_B});
}
static void video_watch() {
    if (audio_nonzero == 0 && (dut->AUDIO_L != 0 || dut->AUDIO_R != 0)) audio_nonzero = 1;
    {   // the watchdog reset of the cold start
        bool wd = EMUV(dbg_wdog);
        if (wd && !prev_wd && frames_done > 3) { wd_seen = true; vs_since_wd = 0; }
        prev_wd = wd;
    }
    {   // geometry at clock level (VGA_HS, VGA_DE, and the frame's end at VGA_VS)
        bool hs = dut->VGA_HS, de = dut->VGA_DE;
        linedbg_watch(hs && !g_prev_hs);
        if (hs && !g_prev_hs) { g_lines_frame++; g_hs_clk = cycles; }
        if (de && !g_prev_de) {
            long s = (long)(cycles - g_hs_clk); g_de_clk = cycles; g_rows++; raw_col = 0;
            if (g_first < 0) g_first = (long)(cycles - g_vs_clk);
            if (s < g_smin) g_smin = s; if (s > g_smax) g_smax = s;
        }
        if (!de && g_prev_de) { long w = (long)(cycles - g_de_clk); if (w < g_wmin) g_wmin = w; if (w > g_wmax) g_wmax = w; }
        g_prev_hs = hs; g_prev_de = de;
        if (dut->VGA_VS && !prev_vs) {
            geo_first = g_first; geo_rows = g_rows; geo_lines = g_lines_frame; geo_smin = g_smin; geo_smax = g_smax; geo_wmin = g_wmin; geo_wmax = g_wmax;
            g_vs_clk = cycles; g_lines_frame = 0; g_first = -1; g_rows = 0; g_smin = 1 << 30; g_smax = -1; g_wmin = 1 << 30; g_wmax = -1;
        }
    }
    bool vs = dut->VGA_VS;
    if (vs && !prev_vs) {                       // a frame ends
        raw_last = raw_now; raw_w = raw_maxc; raw_h = geo_rows; raw_maxc = 0;
        if (de_count == VIS_W * VIS_H * sd_mul) frame_last = frame_now;
        de_last_count = de_count;
        frame_period = cycles - last_frame_cycle; last_frame_cycle = cycles;
        if (record_periods) periods.push_back(frame_period);
        de_count = 0; frames_done++;
        if (wd_seen) {
            vs_since_wd++;
            int mf = 180 + vs_since_wd;
            if (pics.count(mf) && sd_mul == 1) {
                char name[512]; snprintf(name, sizeof name, "%s.f%05d.ppm", prefix.c_str(), mf);
                write_ppm(name, frame_last, VIS_W, VIS_H);
                printf("picture of machine frame %d written (%llu clocks)\n", mf, cycles);
            }
        }
    }
    prev_vs = vs;
    if (dut->CE_PIXEL && dut->VGA_DE) {
        unsigned px = ((unsigned)dut->VGA_R << 16) | ((unsigned)dut->VGA_G << 8) | dut->VGA_B;
        if (g_rows > 0 && g_rows <= RAW_H && raw_col < RAW_W) { raw_now[(g_rows - 1) * RAW_W + raw_col] = px; if (raw_col + 1 > raw_maxc) raw_maxc = raw_col + 1; }
        raw_col++;
        if (sd_mul == 1) { if (de_count < VIS_W * VIS_H) frame_now[de_count] = px; }
        else {   // scandoubled: keep the even rows (and the even columns of HQ2x's double width) as the 320 x 240 picture
            int w2 = VIS_W * (sd_hq ? 2 : 1), row = de_count / w2, col = de_count % w2;
            if (!(row & 1) && !(sd_hq && (col & 1)) && row / 2 < VIS_H) frame_now[(row / 2) * VIS_W + (sd_hq ? col / 2 : col)] = px;
        }
        de_count++;
    }
}
static void run(long n) { while (n--) { tick(); video_watch(); } }

static void set_status(int bit, int v) {
    int w = bit / 32, b = bit % 32;
    unsigned x = HPSV(r_status)[w];
    HPSV(r_status)[w] = v ? (x | (1u << b)) : (x & ~(1u << b));
}
static void field(int lo, int w, int v) { for (int i = 0; i < w; i++) set_status(lo + i, (v >> i) & 1); }

// stream bytes of data[0..n) as one download of the given index; stride = clocks per byte
static void download(int index, const unsigned char *data, long n, int stride, long addr0 = 0) {
    HPSV(r_index) = index; HPSV(r_download) = 1; HPSV(r_addr) = addr0;
    run(8);
    for (long i = 0; i < n; i++) {
        long guard = 0;
        while (HPSV(r_wait_seen) && guard++ < 1000000) run(1);
        HPSV(r_addr) = addr0 + i; HPSV(r_dout) = data[i]; HPSV(r_wr) = 1; run(1);
        HPSV(r_wr) = 0; run(stride - 1);
    }
    run(40);
    HPSV(r_download) = 0; HPSV(r_index) = 0;
    run(8);
}

// the board's ports as the top builds them (active low): which input reaches which bit
static void check_inputs() {
    struct T { const char *name; unsigned j0, j1; int key; unsigned p1, p2; };
    // bits of p1_in / p2_in: 0 up, 1 down, 2 left, 3 right, 4 button, 7 start, 8 coin, 9 service (P2: key 9) / test switch (P1: key F2)
    static const T t[] = {
        { "nothing",             0,       0,       0,     0x0000, 0x0000 },
        { "pad 1 up",            1u << 3, 0,       0,     0x0001, 0x0000 },
        { "pad 1 down",          1u << 2, 0,       0,     0x0002, 0x0000 },
        { "pad 1 left",          1u << 1, 0,       0,     0x0004, 0x0000 },
        { "pad 1 right",         1u << 0, 0,       0,     0x0008, 0x0000 },
        { "pad 1 button",        1u << 4, 0,       0,     0x0010, 0x0000 },
        { "pad 1 start",         1u << 5, 0,       0,     0x0080, 0x0000 },
        { "pad 1 coin",          1u << 6, 0,       0,     0x0100, 0x0000 },
        { "pad bit 7 (no entry)", 1u << 7, 1u << 7, 0,    0x0000, 0x0000 },     // the controller mapping has no Service / Test entry: nothing reaches the board
        { "pad bit 8 (no entry)", 1u << 8, 1u << 8, 0,    0x0000, 0x0000 },
        { "pad 2 up",            0, 1u << 3,       0,     0x0000, 0x0001 },
        { "pad 2 button",        0, 1u << 4,       0,     0x0000, 0x0010 },
        { "pad 2 start",         0, 1u << 5,       0,     0x0000, 0x0080 },
        { "pad 2 coin",          0, 1u << 6,       0,     0x0000, 0x0100 },
        { "key 1 (start 1)",     0, 0,          0x016,    0x0080, 0x0000 },
        { "key 2 (start 2)",     0, 0,          0x01E,    0x0000, 0x0080 },
        { "key 5 (coin 1)",      0, 0,          0x02E,    0x0100, 0x0000 },
        { "key 6 (coin 2)",      0, 0,          0x036,    0x0000, 0x0100 },
        { "key 9 (service)",     0, 0,          0x046,    0x0000, 0x0200 },
        { "key F2 (test)",       0, 0,          0x006,    0x0200, 0x0000 },
    };
    printf("input wiring (p1_in / p2_in as the board reads them, 1 = pressed):\n");
    int toggle = 0;
    for (const T &x : t) {
        HPSV(r_joy0) = x.j0; HPSV(r_joy1) = x.j1;
        if (x.key) { toggle ^= 1; HPSV(r_ps2) = (toggle << 10) | (1 << 9) | x.key; }
        run(8);
        unsigned p1 = (~(unsigned)EMUV(p1_in)) & 0xffff, p2 = (~(unsigned)EMUV(p2_in)) & 0xffff;
        bool ok = p1 == x.p1 && p2 == x.p2;
        printf("  %-18s P1 %04x P2 %04x%s\n", x.name, p1, p2, ok ? "" : "   <-- FAIL");
        if (!ok) errors++;
        if (x.key) { toggle ^= 1; HPSV(r_ps2) = (toggle << 10) | x.key; run(8); }     // the key goes up
        HPSV(r_joy0) = 0; HPSV(r_joy1) = 0; run(4);
    }
}

// Scale: the size the core asks the scaler for.  Worked out here from the picture as it leaves arcade_video (rows, pixels in a row), the OSD
// settings and the scaler's size, by the framework's documented rule: the picture is scaled up by the largest whole factor that fits the
// scaler's height; its width follows the aspect ratio (V-Integer) or is a whole multiple of the pixel row (the HV modes: narrower = the
// multiple below the aspect width, wider = the one above it, HV-Integer = whichever of the two is nearer, the wider one only if it
// still fits the width)
static void check_scale(int menu, int ar) {
        const int HW = dut->HDMI_WIDTH, HH = dut->HDMI_HEIGHT;
        const int rows = geo_rows, w = VIS_W * (sd_hq ? 2 : 1);
        static const int map[5] = {0, 1, 4, 2, 3};                    // the OSD's order -> video_freak's SCALE
        const int sel = (menu >= 0 && menu <= 4) ? map[menu] : 0;
        // Full Screen (0 / 0) has no proportions for the integer rule to work from: with an integer mode the core gives it
        // the scaler's own (OhMyGod.sv's fs_int), unless the scaler's size is unknown (direct video)
        const bool fs_int = ar == 1 && sel != 0 && HW != 0 && HH != 0;
        const int arx_in = fs_int ? HW : (ar == 0 ? 4 : ar - 1), ary_in = fs_int ? HH : (ar == 0 ? 3 : 0);
        int ex = arx_in, ey = ary_in; bool eabs = false, checked = true;
        if (sel && !(!ary_in && arx_in) && HH / rows > 0) {
            int oh = rows * (HH / rows), ht = 0, hi, dn;
            if (!ary_in) {                                            // no proportions at all: the framework's own rule, reported not judged
                int m = HW / w ? HW / w : 1; hi = w * m; oh = rows * m; dn = HW; checked = false;
            } else {
                ht = (int)((long)oh * arx_in / ary_in); int m0 = ht / w ? ht / w : 1; hi = w * m0; dn = ht;
                if (hi > HW) { int m1 = HW / w ? HW / w : 1; hi = w * m1; oh = rows * m1; dn = HW; }
            }
            const int wide = hi + w;
            const bool narrow = (((ht - hi) & 0xfff) <= ((wide - ht) & 0xfff)) || wide > HW;
            const int wres = hi == ht ? hi : wide;
            switch (sel) {
                case 2: ex = hi; break;
                case 3: ex = wres > HW ? hi : wres; break;
                case 4: ex = narrow ? hi : wres; break;
                default: ex = dn;
            }
            ey = oh; eabs = true;
        }
        const int gx = dut->VIDEO_ARX & 0xfff, gy = dut->VIDEO_ARY & 0xfff, gax = (dut->VIDEO_ARX >> 12) & 1, gay = (dut->VIDEO_ARY >> 12) & 1;
        printf("scale: Scale %d (SCALE %d) Aspect %d, picture %d rows of %d pixels, scaler %d x %d: core asks for %s%d x %s%d; rule gives %s%d x %s%d%s\n",
               menu, sel, ar, rows, w, HW, HH, gax ? "" : "ratio ", gx, gay ? "" : "ratio ", gy, eabs ? "" : "ratio ", ex, eabs ? "" : "ratio ", ey,
               checked ? "" : " (not checked)");
        if (checked && (gx != ex || gy != ey || gax != (int)eabs || gay != (int)eabs)) { printf("  FAIL: the size asked of the scaler\n"); errors++; }
        if (eabs && (HH - ey) < 0) printf("  note: the height asked for is %d pixels over the scaler's\n", ey - HH);
    }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: %s <image> <frames> <out-prefix>\n", argv[0]); return 2; }
    int frames = atoi(argv[2]); prefix = argv[3];
    std::vector<unsigned char> img(IMG_LEN);
    FILE *f = fopen(argv[1], "rb"); if (!f) { fprintf(stderr, "cannot open %s\n", argv[1]); return 1; }
    if (fread(img.data(), 1, IMG_LEN, f) != (size_t)IMG_LEN) { fprintf(stderr, "short image\n"); return 1; } fclose(f);
    if (getenv("PICS")) { std::string s = getenv("PICS"); size_t p = 0; while (p < s.size()) { pics.insert(atoi(s.c_str() + p)); p = s.find(',', p); if (p == std::string::npos) break; p++; } }

    dut = new Vtb_emu_top;
    dut->HDMI_WIDTH  = getenv("HW") ? atoi(getenv("HW")) : 1920;
    dut->HDMI_HEIGHT = getenv("HH") ? atoi(getenv("HH")) : 1080;
    if (getenv("LINEDBG")) ld_line = atoi(getenv("LINEDBG"));
    if (getenv("LINEFRAME")) ld_target = atoi(getenv("LINEFRAME"));
    dut->RESET = 1; run(40); dut->RESET = 0;
    {   // CRT Adjust (status[101] on, [100:96] H-Size -16..5, [85:79] H-Position -16..16, [78:74] V-Shift -12..3), values as the OSD menu counts them
        if (getenv("CRT") && atoi(getenv("CRT"))) set_status(101, 1);
        if (getenv("HSIZE")) { int v = atoi(getenv("HSIZE")); field(96, 5, v >= 0 ? v : 22 + v); }
        if (getenv("HPOS")) { int v = atoi(getenv("HPOS")); field(79, 7, v >= 0 ? v : 33 + v); }
        if (getenv("VSHIFT")) { int v = atoi(getenv("VSHIFT")); field(74, 5, v >= 0 ? v : 16 + v); }
    }
    {   // the framework's settings the OSD does not hold: forced_scandoubler (MiSTer.ini); Scandoubler Fx is OSD status[5:3]
        if (getenv("FSD") && atoi(getenv("FSD"))) HPSV(r_fsd) = 1;
        if (getenv("FX")) field(3, 3, atoi(getenv("FX")));
        const bool fsd = getenv("FSD") && atoi(getenv("FSD")); const int fx = getenv("FX") ? atoi(getenv("FX")) : 0;
        if (fsd || fx) { sd_hq = (fx == 1); sd_mul = sd_hq ? 4 : 2; printf("scandoubler on (Fx %d, forced %d): expect %d rows of %d pixels, %d lines a frame\n", fx, (int)fsd, 2 * VIS_H, VIS_W * (sd_hq ? 2 : 1), 2 * 260); }
    }
    {   // Scale (status[34:32]: 0 Normal, 1 V-Integer, 2 HV-Integer, 3 Narrower HV-Integer, 4 HV-Integer+), Aspect ratio (status[122:121])
        if (getenv("SCALE")) field(32, 3, atoi(getenv("SCALE")));
        if (getenv("AR")) field(121, 2, atoi(getenv("AR")));
    }
    if (getenv("SBL") && atoi(getenv("SBL"))) set_status(10, 1);          // Sprite bank flip: At vblank
    run(40000);                                  // SDRAM init, cache sweeps
    printf("up after %llu clocks; loading %ld bytes\n", cycles, IMG_LEN);
    unsigned long long t0 = cycles;
    const bool fast = getenv("FAST") && atoi(getenv("FAST"));
    if (fast) {
        // what Main_MiSTer does for address= on the MRA's index-0 <rom>: the whole assembled image is copied into the DDR3 at that
        // address, between the start and the end of a download that carries no bytes, only a start address (ioctl_addr) that is
        // the image's length; hps_io counts one more at the end.  The core then replays it
        auto &dd = dut->rootp->tb_emu_top__DOT__ddr__DOT__mem;
        const size_t FLB = 0x400000;                 // beats in the client's window: byte 0x32000000
        for (size_t i = 0; i < ((size_t)IMG_LEN + 7) / 8; i++) {
            unsigned long long v = 0;
            for (int b = 7; b >= 0; b--) v = (v << 8) | ((i * 8 + b) < (size_t)IMG_LEN ? img[i * 8 + b] : 0xEE);
            dd[FLB + i] = v;
        }
        HPSV(r_index) = 0; HPSV(r_addr) = IMG_LEN; HPSV(r_download) = 1; run(64);
        HPSV(r_addr) = IMG_LEN + 1; HPSV(r_download) = 0;
        unsigned long long t1 = cycles; long guard = 0;
        const long GUARD = 400000000;
        while (EMUV(fast_dl) && guard++ < GUARD) run(1);
        printf("fast load: the image replayed from the DDR3 in %llu clocks (%.3f s at 96 MHz)\n", cycles - t1, (cycles - t1) / 96e6);
        if (guard >= GUARD) { printf("  FAIL: the replay did not finish\n"); errors++; }
        run(8);
    } else {
        download(0, img.data(), IMG_LEN, 2);
        printf("image loaded in %llu clocks (streamed)\n", cycles - t0);
    }
    {   // the loader's work: every word of the image where the memory subsystem's ports read it
        long guard = 0;
        while (EMUV(dl_busy) && guard++ < 10000000) run(1);                 // the write FIFO drains
        run(4000);
        auto &sd = dut->rootp->tb_emu_top__DOT__chip__DOT__mem;
        unsigned long long words = 0, bad = 0;
        for (size_t wa = 0; wa < 0x1C0000; wa++) {                         // image words below the configuration bytes
            unsigned v = img[wa * 2] | ((unsigned)img[wa * 2 + 1] << 8);
            words++;
            if (sd[wa] != v) { if (bad < 6) printf("  SDRAM word %06zx: %04x, expected %04x\n", wa, (unsigned)sd[wa], v); bad++; }
        }
        printf("loader check: %llu words of the image compared with the SDRAM chip, %llu wrong; game byte %u (image %u)\n",
               words, bad, (unsigned)EMUV(cfg_game), (unsigned)img[0x380000] & 1);
        if (bad) { printf("  FAIL: the loaded image is not where the ports read it\n"); errors++; }
        if ((unsigned)EMUV(cfg_game) != ((unsigned)img[0x380000] & 1)) { printf("  FAIL: the game byte\n"); errors++; }
    }
    if (getenv("BTN") && atoi(getenv("BTN"))) check_inputs();

    // run frames: the first complete frame after the load
    int start_frames = frames_done;
    int target = start_frames + frames;
    unsigned long long guard = 0;
    record_periods = true;
    while (frames_done < target && guard++ < 4000000000ull) tick(), video_watch();
    printf("%d frames after the load, last frame had %d visible pixels (expect %d)\n", frames_done - start_frames, de_last_count, VIS_W * VIS_H * sd_mul);
    {   // CRT Adjust at 15 kHz with H-Size / H-Position away from zero changes the picture's width on purpose; everything else is exact
        const bool crt = getenv("CRT") && atoi(getenv("CRT")) && sd_mul == 1;
        const bool moved = (getenv("HSIZE") && atoi(getenv("HSIZE"))) || (getenv("HPOS") && atoi(getenv("HPOS")));
        if (de_last_count != VIS_W * VIS_H * sd_mul && !(crt && moved)) { printf("  FAIL: visible pixel count\n"); errors++; }
    }

    {   // the raster's period: 16 clocks a pixel, 384 x 260
        printf("frame period %llu clocks (expect %llu = %.4f Hz)\n", frame_period, FRAME_CLK, 96e6 / (double)FRAME_CLK);
        if (frame_period != FRAME_CLK) { printf("  FAIL: the frame period\n"); errors++; }
        // CRT Adjust's V-Shift moves the vertical sync by whole lines, so the frame in which it takes effect is a different length
        int ok = 0, bad = 0, trans = 0;
        const bool vshift = getenv("CRT") && atoi(getenv("CRT")) && getenv("VSHIFT") && atoi(getenv("VSHIFT")) != 0 && sd_mul == 1;
        for (size_t i = 1; i < periods.size(); i++) {    // [0] may span the load
            if (periods[i] == FRAME_CLK) ok++;
            else if (vshift && i <= 3) { trans++; printf("  frame %zu: period %llu clocks = %.3f lines (V-Shift taking effect)\n", i, periods[i], periods[i] / (double)LINE_CLK); }
            else { bad++; if (bad < 6) printf("  frame %zu: period %llu clocks = %.3f lines\n", i, periods[i], periods[i] / (double)LINE_CLK); }
        }
        printf("frame periods after the load: %d whole, %d at a V-Shift step, %d other\n", ok, trans, bad);
        if (bad) { printf("  FAIL: a frame of the wrong length\n"); errors++; }
    }
    unsigned nonblack = 0; for (unsigned v : frame_last) if (v) nonblack++;
    printf("last captured frame: %u non-black pixels\n", nonblack);
    printf("geometry (last frame): %d rows with picture, %d lines a frame; first row %ld clocks after the vsync pulse (%.3f lines);"
           " rows start %ld..%ld clocks after hsync, %ld..%ld clocks wide\n",
           geo_rows, geo_lines, geo_first, geo_first / (double)LINE_CLK, geo_smin, geo_smax, geo_wmin, geo_wmax);
    if (sd_mul > 1 && (geo_rows != 2 * VIS_H || geo_lines != 2 * 260)) {
        printf("  FAIL: the scandoubled raster should be %d rows in %d lines\n", 2 * VIS_H, 2 * 260); errors++;
    }
    check_scale(getenv("SCALE") ? atoi(getenv("SCALE")) : 0, getenv("AR") ? atoi(getenv("AR")) : 0);
    if (getenv("SCALEMATRIX") && atoi(getenv("SCALEMATRIX"))) {   // every Scale x Aspect ratio x scaler size, set live, two frames each
        static const int sizes[][2] = { {1920, 1080}, {1280, 720}, {3840, 2160}, {1366, 768} };
        unsigned e0 = errors; int n = 0;
        for (auto &z : sizes) for (int sc = 0; sc <= 4; sc++) for (int ar = 0; ar <= 2; ar++) {
            field(32, 3, sc); field(121, 2, ar); dut->HDMI_WIDTH = z[0]; dut->HDMI_HEIGHT = z[1];
            int f0 = frames_done; while (frames_done < f0 + 3) tick(), video_watch();
            check_scale(sc, ar); n++;
        }
        printf("scale matrix: %d settings, %u failed\n", n, errors - e0);
    }
    write_ppm((prefix + "_scaler.ppm").c_str(), frame_last, VIS_W, VIS_H);
    {   // the last picture whatever its size
        std::vector<unsigned> px((size_t)raw_w * raw_h);
        for (int y = 0; y < raw_h; y++) for (int x = 0; x < raw_w; x++) px[(size_t)y * raw_w + x] = raw_last[y * RAW_W + x];
        write_ppm((prefix + "_raw.ppm").c_str(), px, raw_w, raw_h);
        printf("raw picture: %d x %d pixels\n", raw_w, raw_h);
    }
    if (getenv("CRT") && atoi(getenv("CRT")))   // inside rmonic79's module: where the active window of the written line sits (dots after the line reference)
        printf("crt_adjust: window written [hb1 %u, hb0 %u) = %d dots, line length hmax %u; hoffset %d\n", (unsigned)EMUV(u_crtadj__DOT__u_adj__DOT__hb1),
               (unsigned)EMUV(u_crtadj__DOT__u_adj__DOT__hb0), (int)EMUV(u_crtadj__DOT__u_adj__DOT__hb0) - (int)EMUV(u_crtadj__DOT__u_adj__DOT__hb1),
               (unsigned)EMUV(u_crtadj__DOT__u_adj__DOT__hmax), (int)(signed char)EMUV(u_crtadj__DOT__hpos_s));
    printf("audio: %s\n", audio_nonzero ? "non-zero samples seen" : "silent");
    printf("DDR3: reads %d, writes %d, protocol errors %d\n", (int)dut->rootp->tb_emu_top__DOT__ddr__DOT__rd_cmds,
           (int)dut->rootp->tb_emu_top__DOT__ddr__DOT__wr_cmds, (int)dut->rootp->tb_emu_top__DOT__ddr__DOT__protocol_errors);
    if (dut->rootp->tb_emu_top__DOT__ddr__DOT__protocol_errors) errors++;
    if (dut->rootp->tb_emu_top__DOT__ddr__DOT__wr_cmds) { printf("  FAIL: the core wrote to the DDR3\n"); errors++; }
    printf("%s (%u error%s)\n", errors ? "FAIL" : "PASS", errors, errors == 1 ? "" : "s");
    delete dut;
    return errors ? 1 : 0;
}
