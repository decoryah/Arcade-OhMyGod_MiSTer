// Raster, line buffer and palette lookup (the display side), all on the machine clock.
//
// The dot clock is 96 MHz / 16 = 6 MHz; the line is 384 dots (15.625 kHz) and the frame 260 lines (60.096 Hz), 320 x 240 of it
// visible.  MAME gives the board's picture as 320 x 240 at 60 Hz (a 512 x 256 total); the totals here are the usual 15 kHz arcade
// ones.  A line is drawn (omg_render) while the one before it is shown, into the other half of the line buffer; the display reads
// the buffer, then the palette RAM (a 10-bit pen: 0..255 tiles, 512..767 sprites), and registers the colour at the dot.
`default_nettype none
module omg_video (
    input  logic        clk,
    input  logic        flip,             // the screen is turned 180 degrees: the lines are drawn from the bottom up and read out backwards (held for a whole frame)

    // raster out
    output logic        ce_pix,
    output logic        hblank, vblank, hsync, vsync,
    output logic [23:0] rgb,

    // raster events (one-cycle pulses)
    output logic        line_start,       // a line is to be drawn: line_no into half line_bank
    output logic  [7:0] line_no,
    output logic        line_bank,
    output logic        vbl_pulse,        // vertical blanking starts (line 240)

    // renderer write port
    input  logic        lb_we,
    input  logic [9:0]  lb_addr,          // {bank, x[8:0]}
    input  logic [9:0]  lb_data,

    // palette RAM read port (registered)
    output logic [9:0]  pal_addr,
    input  logic [15:0] pal_data
);
    localparam H_ACT = 320, H_TOT = 384, V_ACT = 240, V_TOT = 260;
    localparam H_SYNC0 = 336, H_SYNC1 = 368;           // 32 dots, 16 after the picture, 16 before the next
    localparam V_SYNC0 = 244, V_SYNC1 = 247;           // 3 lines, 4 after the picture, 13 before the next

    // ------------------------------------------------------------ raster
    logic [3:0] ph = 4'd0;
    logic [8:0] hc = 9'd0, vc = 9'd0;                  // the dot / line being output
    always_ff @(posedge clk) begin
        ph <= ph + 4'd1;
        ce_pix <= (ph == 4'd15);
    end

    // the counters at the next dot
    wire        wrap = (hc == H_TOT - 1);
    wire [8:0]  hn = wrap ? 9'd0 : hc + 9'd1;
    wire [8:0]  vn = wrap ? ((vc == V_TOT - 1) ? 9'd0 : vc + 9'd1) : vc;
    wire  [7:0] next_d = (vn == 9'(V_TOT - 1)) ? 8'd0 : vn[7:0] + 8'd1;            // the line after the one that starts now: the one drawn meanwhile (valid when `wrap`)

    always_ff @(posedge clk) begin
        line_start <= 1'b0;
        vbl_pulse  <= 1'b0;
        if (ph == 4'd15) begin
            hc <= hn;
            vc <= vn;
            hblank <= (hn >= H_ACT);
            vblank <= (vn >= V_ACT);
            hsync  <= (hn >= H_SYNC0) && (hn < H_SYNC1);
            vsync  <= (vn >= V_SYNC0) && (vn < V_SYNC1);
            if (wrap) begin
                // line vn starts: draw the one after it (the last blank line draws line 0 of the next frame)
                line_bank  <= ~vn[0];
                line_start <= (vn == V_TOT - 1) || (vn + 9'd1 < V_ACT);
                line_no    <= flip ? (8'(V_ACT - 1) - next_d) : next_d;       // the picture line to draw: the next one shown, from the other end when flipped
                vbl_pulse  <= (vn == V_ACT);
            end
        end
    end

    // ------------------------------------------------------------ line buffer and palette
    // the dot after the next one is read two clocks ahead of the register: the line buffer's output is registered, so is
    // the palette RAM's (omg_main's port B), and the dot's colour is registered at the dot edge.
    wire        rd_bank = wrap ? ~vc[0] : vc[0];
    wire  [8:0] rd_x    = (flip && hn < H_ACT) ? 9'(H_ACT - 1) - hn : hn;      // flipped, the picture is read from its right end
    wire [9:0]  rd_addr = {rd_bank, rd_x};
    logic [9:0] lb_q;
    omg_sdp #(.AW(10), .DW(10)) u_lb (.clk(clk), .we(lb_we), .waddr(lb_addr), .wdata(lb_data), .raddr(rd_addr), .rdata(lb_q));
    assign pal_addr = lb_q;

    // palette entry: xGRB555
    wire [4:0] cr = pal_data[9:5], cg = pal_data[14:10], cb = pal_data[4:0];
    always_ff @(posedge clk) if (ph == 4'd15) begin
        rgb <= {cr, cr[4:2], cg, cg[4:2], cb, cb[4:2]};
    end
endmodule
`default_nettype wire
