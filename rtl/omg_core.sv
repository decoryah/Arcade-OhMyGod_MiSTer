// The whole machine, without its memory (SDRAM) and the platform: the 68000 board, the OKI, the video renderer and the raster.
// One clock: clk 96 MHz (68000 12 MHz, OKI 2 MHz, dots 6 MHz).
`default_nettype none
module omg_core (
    input  logic        clk,
    input  logic        rst,                  // the machine (CPU, sound, renderer)
    input  logic        cpu_hold,             // simulation: keep the 68000 and the sound in reset (frozen-state benches)
    input  logic [31:0] wdog_limit,

    // program load
    input  logic        cache_inval,          // a ROM load starts
    input  logic        cfg_game,             // 0 Oh My God!, 1 Naname de Magic!
    input  logic        sb_latch,             // 1: the sprite bank flag takes effect at the next vertical blank (0: at once)

    // memory clients (rtl/omg_mem.sv)
    output logic        p_req,  output logic [18:4] p_addr,
    input  logic        p_wr,   input logic [2:0] p_idx,  input logic [15:0] p_data,  input logic p_done,
    output logic        t_req,  output logic [24:1] t_addr,
    input  logic        t_wr,   input logic [1:0] t_idx,  input logic [15:0] t_data,  input logic t_done,
    output logic        s_req,  output logic [24:1] s_addr,
    input  logic        s_wr,   input logic [1:0] s_idx,  input logic [15:0] s_data,  input logic s_done,
    output logic        pcm_req, output logic [20:0] pcm_addr,
    input  logic        pcm_ack, input logic [7:0] pcm_q,

    // controls (active low, the board's bit order)
    input  logic [15:0] p1_in, p2_in, dsw1_in, dsw2_in,

    // picture and sound
    output logic        ce_pix,
    output logic        hblank, vblank, hsync, vsync,
    output logic [23:0] rgb,
    output logic signed [13:0] snd,

    // debug
    output logic        dbg_ovr,              // a line was not finished in time
    output logic        dbg_irq,
    output logic        dbg_halted,
    output logic        dbg_wdog,
    output logic        dbg_render_busy,
    output logic [23:1] dbg_addr,
    output logic        trc_stb, output logic trc_rw, output logic [15:0] trc_data, output logic [1:0] trc_be
);
    // ---------------------------------------------------------------- reset: the input and the watchdog
    logic        wd_pulse;
    logic [7:0]  wd_stretch = 8'd0;
    always_ff @(posedge clk) begin
        if (wd_pulse) wd_stretch <= 8'hff;
        else if (wd_stretch != 8'd0) wd_stretch <= wd_stretch - 8'd1;
    end
    wire mreset = rst | cpu_hold | (wd_stretch != 8'd0);
    assign dbg_wdog = wd_stretch != 8'd0;

    logic cen_phi1, cen_phi2, cen_oki;
    omg_cen u_cen (.clk(clk), .cen_phi1(cen_phi1), .cen_phi2(cen_phi2), .cen_oki(cen_oki));

    // ---------------------------------------------------------------- raster
    logic        line_start, line_bank, vbl_pulse;
    logic  [7:0] line_no;
    logic        lb_we;
    logic  [9:0] lb_addr, lb_data;
    logic  [9:0] pal_addr;
    logic [15:0] pal_data;
    // The screen flip (bit 14 of the sprite bank register) is taken over at the start of vertical blanking: a frame is drawn and shown one
    // way throughout (the lines of the next frame are drawn from the last blank line on, after this).
    logic        flipscreen, flip_f;
    initial flip_f = 1'b0;
    always_ff @(posedge clk) if (vbl_pulse) flip_f <= flipscreen;
    omg_video u_video (
        .clk(clk), .flip(flip_f),
        .ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .rgb(rgb),
        .line_start(line_start), .line_no(line_no), .line_bank(line_bank), .vbl_pulse(vbl_pulse),
        .lb_we(lb_we), .lb_addr(lb_addr), .lb_data(lb_data),
        .pal_addr(pal_addr), .pal_data(pal_data)
    );

    // ---------------------------------------------------------------- the 68000 board
    logic        rom_req, rom_ack;
    logic [18:1] rom_addr;
    logic [15:0] rom_data;
    logic [11:0] vr_addr;
    logic [31:0] vr_data;
    logic [10:0] sr_addr;
    logic [63:0] sr_data;
    logic [15:0] scrollx, scrolly;
    logic        spritebank;
    logic        oki_wr;
    logic  [7:0] oki_din, oki_dout;
    logic  [3:0] oki_bank;

    omg_main u_main (
        .clk(clk), .reset(mreset), .hard_reset(rst), .wdog_limit(wdog_limit), .cen_phi1(cen_phi1), .cen_phi2(cen_phi2),
        .cfg_game(cfg_game),
        .rom_req(rom_req), .rom_addr(rom_addr), .rom_ack(rom_ack), .rom_data(rom_data),
        .p1_in(p1_in), .p2_in(p2_in), .dsw1_in(dsw1_in), .dsw2_in(dsw2_in),
        .vblank_irq(vbl_pulse),
        .vr_addr(vr_addr), .vr_data(vr_data), .sr_addr(sr_addr), .sr_data(sr_data),
        .pal_addr(pal_addr), .pal_data(pal_data),
        .scrollx(scrollx), .scrolly(scrolly), .spritebank(spritebank), .flipscreen(flipscreen),
        .oki_wr(oki_wr), .oki_din(oki_din), .oki_dout(oki_dout), .oki_bank(oki_bank),
        .wdog_reset(wd_pulse), .wdog_kick_o(),
        .trc_stb(trc_stb), .trc_addr(dbg_addr), .trc_rw(trc_rw), .trc_data(trc_data), .trc_be(trc_be),
        .cpu_halted(dbg_halted)
    );
    assign dbg_irq = vbl_pulse;

    omg_cache u_cache (
        .clk(clk), .inval(cache_inval), .busy(),
        .req(rom_req), .addr(rom_addr), .ack(rom_ack), .data(rom_data),
        .fill_req(p_req), .fill_addr(p_addr), .fill_wr(p_wr), .fill_idx(p_idx), .fill_data(p_data), .fill_done(p_done)
    );

    // ---------------------------------------------------------------- the sound
    omg_sound u_sound (
        .clk(clk), .rst(mreset), .cen_oki(cen_oki),
        .wr(oki_wr), .din(oki_din), .dout(oki_dout), .bank(oki_bank),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .snd(snd)
    );

    // ---------------------------------------------------------------- the line renderer
    // From the IRQ at the start of vertical blank the game builds the next sprite list into the hidden bank and flips the bank
    // flag 46..62 line times later (picture line ~29 here), i.e. while the picture is being drawn.  A chip that reads the flag
    // live shows the old list above the flip and the new one below it; MAME, drawing the frame at its end, shows the new one
    // throughout.  `sb_latch` samples the flag at the start of vertical blanking instead (the whole next frame shows the list
    // the previous flip selected).
    logic sb_l;
    always_ff @(posedge clk) if (vbl_pulse) sb_l <= spritebank;
    wire  sb_eff = sb_latch ? sb_l : spritebank;
    omg_render u_render (
        .clk(clk), .rst(rst),
        .start(line_start), .line(line_no), .bank(line_bank), .busy(dbg_render_busy), .overrun(dbg_ovr),
        .scrollx(scrollx), .scrolly(scrolly), .spritebank(sb_eff), .flip(flip_f),
        .vr_addr(vr_addr), .vr_data(vr_data), .sr_addr(sr_addr), .sr_data(sr_data),
        .t_req(t_req), .t_addr(t_addr), .t_wr(t_wr), .t_idx(t_idx), .t_data(t_data), .t_done(t_done),
        .s_req(s_req), .s_addr(s_addr), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
        .lb_we(lb_we), .lb_addr(lb_addr), .lb_data(lb_data)
    );
endmodule
`default_nettype wire
