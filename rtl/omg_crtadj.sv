// CRT Adjust for every game: H-Size, H-Position and V-Shift of the analog picture from the OSD.
//
// The picture goes through the one-line buffer of rmonic79's crt_adjust (modules/crt_adjust, GPL-3.0-or-later, MiSTer-CRT-Adjust): the CONTENT is stretched / shifted in the buffer and
// the horizontal sync stays native, the vertical sync is delayed by whole lines, so the CRT keeps its lock while the picture is moved.  This file is the glue the upstream's
// docs/core-side-integration.md and examples/core_side_snippet.v describe: it decodes the OSD fields, makes the read clock enable of the buffer (every `4 * dot + hsize` quarters of a
// clock, restarted on the module's hs_ref_out), switches between the native stream and the adjusted one and builds the window the OSD is placed by (the OSD centres itself on the
// rising edge of the DE signal: with the adjusted DE it would slide with the picture).
//
//   i_on = 0: the stream passes untouched (the module is not in the path).
//   i_pdot : clocks of the 96 MHz machine clock per dot of the stream (16 native, 14 for the re-timed 360-pixel boards, 12 for the 384-pixel one): one step of H-Size is one quarter
//            of a clock, 1/(4 * dot) of the dot (1.6 / 1.8 / 2.1 %).
//   H-Size   : i_hsize_f = signed 5 bits, -16 .. +15 quarters of a clock per dot (positive = wider picture).
//   H-Position: i_hpos_f = OSD index 0 .. 96: 0 .. 48 are +0 .. +48 dots to the right, 49 .. 96 are -48 .. -1 (to the left).
//   V-Shift  : i_vshift_f = OSD index 0 .. 31: 0 .. 23 are +0 .. +23 lines, 24 .. 31 are -8 .. -1 (positive = down).  The native vertical sync sits 8 lines behind the picture, so a
//              shift earlier than -8 would put the sync pulse into the picture (a scaler such as the RT4K tears there); later has 27 lines of room.
`default_nettype none
module omg_crtadj #(
    parameter VTOTAL = 260,                     // lines of the video chip's frame (sizes the vertical-sync shift register)
    parameter HTOTAL = 384                      // dots of the longest line (the 384-pixel board: 522): sizes the horizontal-sync register, which the content-shift mode does not use
) (
    input  logic               clk,
    input  logic               i_on,
    input  logic        [4:0]  i_hsize_f,
    input  logic        [6:0]  i_hpos_f,
    input  logic        [4:0]  i_vshift_f,
    input  logic        [4:0]  i_pdot,
    input  logic               i_ce, i_hblank, i_vblank, i_hs, i_vs,
    input  logic        [23:0] i_rgb,
    output logic               o_ce, o_hblank, o_vblank, o_hs, o_vs,
    output logic        [23:0] o_rgb,
    output logic               o_de_osd         // the window the OSD is centred on (use it instead of the mixer's DE while i_on)
);
    // ---- the OSD values, taken over at the dot rate
    logic               on_q;
    logic signed [4:0]  hsize_s;
    logic signed [8:0]  hpos_s;
    logic signed [5:0]  vshift_s;
    always_ff @(posedge clk) if (i_ce) begin
        on_q     <= i_on;
        hsize_s  <= $signed(i_hsize_f);
        hpos_s   <= (i_hpos_f <= 7'd48) ? $signed({2'b00, i_hpos_f}) : ($signed({2'b00, i_hpos_f}) - 9'sd97);
        vshift_s <= (i_vshift_f <= 5'd23) ? {1'b0, i_vshift_f} : ({1'b0, i_vshift_f} - 6'd32);       // OSD index 0 .. 23 = +0 .. +23 lines, 24 .. 31 = -8 .. -1
    end

    // ---- the read clock enable: one source dot every (4 * pdot + hsize) quarters of a clock, restarted on the module's horizontal sync reference
    logic hs_ref, hs_ref_d;
    always_ff @(posedge clk) hs_ref_d <= hs_ref;
    wire  hs_ref_rise = hs_ref && !hs_ref_d;

    wire  [8:0] base      = {2'b00, i_pdot, 2'b00};                                  // quarters of a clock per dot: 48 / 56 / 64
    wire  [8:0] rd_period = base + {{4{hsize_s[4]}}, hsize_s};                       // 32 .. 79
    logic [8:0] rd_acc;
    wire        rd_tick   = ({1'b0, rd_acc} + 10'd4) >= {1'b0, rd_period};
    always_ff @(posedge clk) begin
        if      (hs_ref_rise) rd_acc <= '0;
        else if (rd_tick)     rd_acc <= rd_acc + 9'd4 - rd_period;
        else                  rd_acc <= rd_acc + 9'd4;
    end
    wire rd_ce = on_q ? rd_tick : i_ce;

    // ---- the buffer
    logic [7:0] str_r, str_g, str_b;
    logic       str_hs, str_vs, str_hb, str_vb;
    crt_adjust #(.VTOTAL(VTOTAL), .HTOTAL(HTOTAL), .HPOS_MODE(1)) u_adj (       // 1 = the content moves, the horizontal sync stays native (wide / centred pictures)
        .clk(clk), .pxl_cen(i_ce), .pxl2_cen(rd_ce), .active(on_q),
        .hsize(hsize_s), .hoffset(hpos_s), .voffset(vshift_s),
        .r_in(i_rgb[23:16]), .g_in(i_rgb[15:8]), .b_in(i_rgb[7:0]),
        .hs_in(i_hs), .vs_in(i_vs), .hb_in(i_hblank | i_vblank), .vb_in(i_vblank),
        .r_out(str_r), .g_out(str_g), .b_out(str_b),
        .hs_out(str_hs), .vs_out(str_vs), .hb_out(str_hb), .vb_out(str_vb),
        .hs_ref_out(hs_ref)
    );

    // ---- the OSD window: its rising edge is the start of the picture that comes in, its falling edge the end of the adjusted picture
    logic hs_q, vblank_1l, native_active_d, str_active_d, de_osd;
    wire  line_tick      = i_ce && i_hs && !hs_q;
    wire  native_active  = !(i_hblank || vblank_1l);
    wire  native_rise    = native_active && !native_active_d;
    wire  str_active     = !str_hb;
    wire  str_fall       = str_active_d && !str_active;
    always_ff @(posedge clk) begin
        if (i_ce) begin
            hs_q            <= i_hs;
            native_active_d <= native_active;
        end
        if (line_tick) vblank_1l <= i_vblank;
        if (rd_ce) str_active_d <= str_active;
        if      (native_rise) de_osd <= 1'b1;
        else if (str_fall)    de_osd <= 1'b0;
    end

    // ---- the outputs
    assign o_ce     = on_q ? rd_ce  : i_ce;
    assign o_rgb    = on_q ? {str_r, str_g, str_b} : i_rgb;
    assign o_hs     = on_q ? str_hs : i_hs;
    assign o_vs     = on_q ? str_vs : i_vs;
    assign o_hblank = on_q ? str_hb : i_hblank;
    assign o_vblank = on_q ? str_vb : i_vblank;
    assign o_de_osd = on_q ? de_osd : !(i_hblank || i_vblank);

    initial begin
        on_q = 0; hsize_s = 0; hpos_s = 0; vshift_s = 0; hs_ref_d = 0; rd_acc = 0; hs_q = 0; vblank_1l = 0; native_active_d = 0; str_active_d = 0; de_osd = 0;
    end
endmodule
`default_nettype wire
