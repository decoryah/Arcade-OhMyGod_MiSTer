// Whole-machine bench: omg_core behind omg_mem and a behavioural SDRAM chip, one clock (96 MHz).
// The C++ side preloads the chip (DPI) with the ROM image, or pushes it through the loader (dl_*), and can preload the RAMs from a
// MAME state dump (+state=<prefix> reads <prefix>.{ram300,ram700,pal1,regs}) with the 68000 held in reset.
`default_nettype none
module tb_top (
    input  logic        clk,
    input  logic        rst,                // the machine (CPU, sound, renderer)
    input  logic        cpu_hold,           // keep the 68000 and the sound in reset
    input  logic        init,               // the SDRAM controller
    input  logic        sb_latch,

    input  logic        dl_we,
    input  logic [24:0] dl_addr,
    input  logic [7:0]  dl_data,
    output logic        dl_wait,
    output logic        dl_busy,
    output logic        mem_ready,

    input  logic [15:0] p1_in, p2_in, dsw1_in, dsw2_in,
    input  logic [31:0] wdog_limit,

    output logic        ce_pix,
    output logic        hblank, vblank, hsync, vsync,
    output logic [23:0] rgb,
    output logic signed [13:0] snd,

    output logic        dbg_ovr, dbg_irq, dbg_halted, dbg_wdog, dbg_render_busy,
    output logic [23:1] dbg_addr,
    output logic        trc_stb, trc_rw,
    output logic [15:0] trc_data,
    output logic [1:0]  trc_be,
    output logic        oki_wr,
    output logic [7:0]  oki_din,
    output logic [3:0]  oki_bank,
    output logic        cfg_game_o
);
    wire  [15:0] dram_dq;
    wire  [12:0] dram_a;
    wire  [1:0]  dram_ba;
    wire         dram_dqml, dram_dqmh, dram_ncs, dram_nras, dram_ncas, dram_nwe, dram_cke, dram_clk;

    logic        p_req, t_req, s_req, pcm_req;
    logic [18:4] p_addr;
    logic [24:1] t_addr, s_addr;
    logic [20:0] pcm_addr;
    logic        p_wr, t_wr, s_wr, p_done, t_done, s_done, pcm_ack;
    logic [2:0]  p_idx;
    logic [1:0]  t_idx, s_idx;
    logic [15:0] p_data, t_data, s_data;
    logic [7:0]  pcm_q;
    logic        cfg_game;

    omg_mem u_mem (
        .clk(clk), .clk_sdram(clk), .init(init), .rd_late(1'b0), .ready(mem_ready),
        .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data), .dl_wait(dl_wait), .dl_busy(dl_busy), .cfg_game(cfg_game),
        .p_req(p_req), .p_addr(p_addr), .p_wr(p_wr), .p_idx(p_idx), .p_data(p_data), .p_done(p_done),
        .t_req(t_req), .t_addr(t_addr), .t_wr(t_wr), .t_idx(t_idx), .t_data(t_data), .t_done(t_done),
        .s_req(s_req), .s_addr(s_addr), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .SDRAM_DQ(dram_dq), .SDRAM_A(dram_a), .SDRAM_DQML(dram_dqml), .SDRAM_DQMH(dram_dqmh), .SDRAM_BA(dram_ba),
        .SDRAM_nCS(dram_ncs), .SDRAM_nWE(dram_nwe), .SDRAM_nRAS(dram_nras), .SDRAM_nCAS(dram_ncas),
        .SDRAM_CKE(dram_cke), .SDRAM_CLK(dram_clk)
    );

    sdram_model #(.PHASE_LAG(0), .AW(23)) chip (
        .clk(clk), .dq(dram_dq), .a(dram_a), .ba(dram_ba), .dqml(dram_dqml), .dqmh(dram_dqmh),
        .cs_n(dram_ncs), .ras_n(dram_nras), .cas_n(dram_ncas), .we_n(dram_nwe), .cke(dram_cke)
    );

    omg_core u_core (
        .clk(clk), .rst(rst), .cpu_hold(cpu_hold), .wdog_limit(wdog_limit),
        .cache_inval(init | dl_busy), .cfg_game(cfg_game), .sb_latch(sb_latch),
        .p_req(p_req), .p_addr(p_addr), .p_wr(p_wr), .p_idx(p_idx), .p_data(p_data), .p_done(p_done),
        .t_req(t_req), .t_addr(t_addr), .t_wr(t_wr), .t_idx(t_idx), .t_data(t_data), .t_done(t_done),
        .s_req(s_req), .s_addr(s_addr), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .p1_in(p1_in), .p2_in(p2_in), .dsw1_in(dsw1_in), .dsw2_in(dsw2_in),
        .ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .rgb(rgb),
        .snd(snd),
        .dbg_ovr(dbg_ovr), .dbg_irq(dbg_irq), .dbg_halted(dbg_halted), .dbg_wdog(dbg_wdog), .dbg_render_busy(dbg_render_busy),
        .dbg_addr(dbg_addr), .trc_stb(trc_stb), .trc_rw(trc_rw), .trc_data(trc_data), .trc_be(trc_be)
    );
    assign oki_wr   = u_core.u_main.oki_wr;
    assign oki_din  = u_core.u_main.oki_din;
    assign oki_bank = u_core.u_main.bank_r;
    assign cfg_game_o = cfg_game;

    // ---------------------------------------------------------------- backdoors for the C++ side
    export "DPI-C" function tb_sdram_write;
    function void tb_sdram_write(input int idx, input int w);
        chip.mem[idx[22:0]] = w[15:0];
    endfunction
    export "DPI-C" function tb_sdram_read;
    function int tb_sdram_read(input int idx);
        return {16'd0, chip.mem[idx[22:0]]};
    endfunction
    // the configuration the loader would have captured (a preloaded image does not go through it)
    export "DPI-C" function tb_cfg;
    function void tb_cfg(input int game);
        u_mem.cfg_game = game[0];
    endfunction

    // ---------------------------------------------------------------- RAMs from a MAME state dump
    string pre;
    logic [15:0] t32k [0:32767];
    integer fi, fc;
    integer sx_, sy_, sb_, a_, b_, c_, d_, e_;
    initial begin
        if ($value$plusargs("state=%s", pre)) begin
            $readmemh({pre, ".ram300"}, t32k);
            for (int i = 0; i < 8192; i++) begin
                u_core.u_main.u_rama.hi[i] = t32k[i][15:8];  u_core.u_main.u_rama.lo[i] = t32k[i][7:0];
            end
            for (int i = 0; i < 4096; i++) begin
                u_core.u_main.u_attr.hi[i] = t32k[8192 + 2*i][15:8];     u_core.u_main.u_attr.lo[i] = t32k[8192 + 2*i][7:0];
                u_core.u_main.u_code.hi[i] = t32k[8192 + 2*i + 1][15:8]; u_core.u_main.u_code.lo[i] = t32k[8192 + 2*i + 1][7:0];
            end
            for (int i = 0; i < 16384; i++) begin
                u_core.u_main.u_ramb.hi[i] = t32k[16384 + i][15:8];  u_core.u_main.u_ramb.lo[i] = t32k[16384 + i][7:0];
            end
            $readmemh({pre, ".ram700"}, t32k);
            for (int w = 0; w < 8192; w++) begin
                case (w & 3)
                    0: begin u_core.u_main.u_s0.hi[w >> 2] = t32k[w][15:8]; u_core.u_main.u_s0.lo[w >> 2] = t32k[w][7:0]; end
                    1: begin u_core.u_main.u_s1.hi[w >> 2] = t32k[w][15:8]; u_core.u_main.u_s1.lo[w >> 2] = t32k[w][7:0]; end
                    2: begin u_core.u_main.u_s2.hi[w >> 2] = t32k[w][15:8]; u_core.u_main.u_s2.lo[w >> 2] = t32k[w][7:0]; end
                    3: begin u_core.u_main.u_s3.hi[w >> 2] = t32k[w][15:8]; u_core.u_main.u_s3.lo[w >> 2] = t32k[w][7:0]; end
                endcase
            end
            for (int i = 0; i < 8192; i++) begin
                u_core.u_main.u_ramc.hi[i] = t32k[8192 + i][15:8];  u_core.u_main.u_ramc.lo[i] = t32k[8192 + i][7:0];
            end
            for (int i = 0; i < 16384; i++) begin
                u_core.u_main.u_ramd.hi[i] = t32k[16384 + i][15:8];  u_core.u_main.u_ramd.lo[i] = t32k[16384 + i][7:0];
            end
            // the palette MAME converted the frame with (see tools/lua/dump_state.lua)
            $readmemh({pre, ".pal1"}, t32k, 0, 1023);
            for (int i = 0; i < 1024; i++) begin
                u_core.u_main.u_pal.hi[i] = t32k[i][15:8];  u_core.u_main.u_pal.lo[i] = t32k[i][7:0];
            end
        end
    end
    // the video registers are forced by the C++ side after elaboration (an initial block here would race with the
    // module's own power-up values)
    export "DPI-C" function tb_regs;
    function void tb_regs(input int sx, input int sy, input int sb);
        u_core.u_main.scrollx    = sx[15:0];
        u_core.u_main.scrolly    = sy[15:0];
        u_core.u_main.spritebank = sb[0];
    endfunction
endmodule
