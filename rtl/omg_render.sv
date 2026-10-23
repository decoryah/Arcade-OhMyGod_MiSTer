// Line renderer: MAME's ohmygod_state::screen_update for one line (the one after the line being shown).
//
//   1. the tile layer: 64 x 64 tiles of 8 x 8, 4bpp, opaque; 41 tiles cover the line.  Per tile: the {attr, code} pair from the
//      tile RAM, the row's 4 bytes (two words) from the character ROM in SDRAM, 8 pen writes.
//   2. the sprites: 1024 entries of four words (the active bank of the sprite RAM), drawn in entry order, the last one on top:
//      word 0 x (- 29), word 1 y (signed), word 2 colour (bits 3:0), word 3 flip x (bit 15) and code (bits 11:0).  16 x 16, 4bpp,
//      pen 0 transparent.  The scan runs one entry a clock and stops at a hit for the row's 8 bytes (four words) and 16 writes.
//
// Line buffer entries are palette indexes: tiles {0, colour[3:0], pen[3:0]} (0..255), sprites 512 + colour * 16 + pen.
// The picture's window is x 96..415 of MAME's 512-dot bitmap; tile scroll: source x = x + 96 + (scrollx - 0x81ec), y + (scrolly - 0x81ef).
`default_nettype none
module omg_render #(
    parameter [24:1] CHR_BASE = 24'h040000,       // SDRAM word address of the character ROM
    parameter [24:1] SPR_BASE = 24'h080000        // ... and of the sprite ROM
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,                    // draw `line` into half `bank` of the line buffer
    input  logic [7:0]  line,
    input  logic        bank,
    output logic        busy,
    output logic        overrun,                  // pulse: a line started while the last one was still being drawn

    input  logic [15:0] scrollx, scrolly,
    input  logic        spritebank,
    input  logic        flip,                     // the screen flip: the picture drawn here is the one the game would show unflipped (omg_video turns it)

    // tile RAM: {attr, code} of the tile index, one clock after the address
    output logic [11:0] vr_addr,
    input  logic [31:0] vr_data,
    // sprite RAM: {w3, w2, w1, w0} of {bank, index}, one clock after the address
    output logic [10:0] sr_addr,
    input  logic [63:0] sr_data,

    // SDRAM burst clients (level request, a word per wr with its index, a pulse at the end)
    output logic        t_req,
    output logic [24:1] t_addr,                   // 2 words
    input  logic        t_wr,
    input  logic [1:0]  t_idx,
    input  logic [15:0] t_data,
    input  logic        t_done,
    output logic        s_req,
    output logic [24:1] s_addr,                   // 4 words
    input  logic        s_wr,
    input  logic [1:0]  s_idx,
    input  logic [15:0] s_data,
    input  logic        s_done,

    // line buffer write port
    output logic        lb_we,
    output logic [9:0]  lb_addr,
    output logic [9:0]  lb_data
);
    typedef enum logic [3:0] {
        S_IDLE, T_ADDR, T_WAIT, T_CAP, T_FETCH, T_PIX,
        S_SCAN, S_FETCH, S_DRAW, S_END
    } st_t;
    st_t st = S_IDLE;

    // latched at the start of the line
    logic [7:0]  y;
    logic        bk;
    logic [8:0]  off_x;                           // (96 + scroll x) & 511
    logic [8:0]  my;                              // tile row source line: y + scroll y
    logic        sbk;

    // tile pass
    logic [5:0]  ti;                              // tile 0..40
    logic [3:0]  attr_c;
    logic [15:0] tw [2];
    logic [2:0]  pp;                              // pixel 0..7
    wire  [5:0]  tcol = off_x[8:3] + ti;
    wire  [9:0]  tile_x = {ti, 3'b000} - {7'd0, off_x[2:0]};           // screen x of the tile's first pixel (signed 10 bit)

    // sprite pass
    logic [9:0]  ia;                              // next entry to ask for
    logic        scan_run;                        // entries are being asked for
    logic [9:0]  i_sa;                            // entry on sr_addr
    logic        v_sa, v_sd;                      // sr_addr / sr_data hold a requested entry
    logic [9:0]  i_sd;                            // entry on sr_data
    logic [9:0]  resume;
    logic        last_hit;                        // the hit was entry 1023: the scan ends after the draw
    logic [11:0] sp_code;
    logic [3:0]  sp_color;
    logic        sp_flip;
    logic [9:0]  sp_x;                            // screen x of the sprite's first pixel (signed 10 bit)
    logic [3:0]  sp_row;
    logic [15:0] sw [4];
    logic [3:0]  sp;                              // pixel 0..15

    wire [15:0] w0 = sr_data[15:0], w1 = sr_data[31:16], w2 = sr_data[47:32], w3 = sr_data[63:48];
    // y test: row = y - sy, sy signed 16 bit
    // Flipped, the game's sprite words are the unflipped ones moved by (-57, +17): put them back (docs/hardware.md, tools/lua/probe_inputs.lua)
    wire signed [17:0] row_s  = $signed({10'd0, y}) - $signed({{2{w1[15]}}, w1}) + (flip ? 18'sd17 : 18'sd0);
    wire               hit_y  = (row_s >= 18'sd0) && (row_s < 18'sd16);
    // x test: x = w0 - 29 - 96 = w0 - 125, visible when -16 < x < 320
    wire signed [17:0] x_s    = $signed({2'b00, w0}) - 18'sd125 + (flip ? 18'sd57 : 18'sd0);
    wire               hit_x  = (x_s > -18'sd16) && (x_s < 18'sd320);
    wire               hit    = v_sd && hit_y && hit_x;

    // pixel pick from the fetched row words
    function automatic [3:0] nib(input [15:0] a, input [15:0] b, input [15:0] c, input [15:0] d, input [3:0] col);
        logic [15:0] wd;
        logic [7:0]  by;
        begin
            wd = (col[3:2] == 2'd0) ? a : (col[3:2] == 2'd1) ? b : (col[3:2] == 2'd2) ? c : d;
            by = col[1] ? wd[15:8] : wd[7:0];
            nib = col[0] ? by[3:0] : by[7:4];
        end
    endfunction
    wire [3:0]  sp_col = sp_flip ? ~sp : sp;
    wire [3:0]  sp_pen = nib(sw[0], sw[1], sw[2], sw[3], sp_col);
    wire signed [10:0] sp_xx = $signed({sp_x[9], sp_x}) + $signed({7'd0, sp});
    wire signed [10:0] tl_xx = $signed({tile_x[9], tile_x}) + $signed({8'd0, pp});
    // tile pixel: byte pp>>1 of the row, high nibble first
    wire [7:0]  tl_byte = (pp[2:1] == 2'd0) ? tw[0][7:0] : (pp[2:1] == 2'd1) ? tw[0][15:8] : (pp[2:1] == 2'd2) ? tw[1][7:0] : tw[1][15:8];
    wire [3:0]  tl_pen  = pp[0] ? tl_byte[3:0] : tl_byte[7:4];

    assign busy = (st != S_IDLE);

    always_ff @(posedge clk) begin
        lb_we   <= 1'b0;
        overrun <= 1'b0;
        if (t_wr) tw[t_idx[0]] <= t_data;
        if (s_wr) sw[s_idx]    <= s_data;

        if (rst) begin
            st <= S_IDLE; t_req <= 1'b0; s_req <= 1'b0; scan_run <= 1'b0;
        end else begin
            if (start && st != S_IDLE) overrun <= 1'b1;
            case (st)
                S_IDLE: if (start) begin
                    y     <= line;
                    bk    <= bank;
                    // flipped, the game's scroll words are the unflipped ones plus (39, 273): take them out (-273 = +239 mod 512)
                    off_x <= scrollx[8:0] + (flip ? 9'd77 : 9'd116);               // 96 + (scrollx - 0x81ec) mod 512 (116 - 39 = 77)
                    my    <= {1'b0, line} + scrolly[8:0] + (flip ? 9'd256 : 9'd17); // y + (scrolly - 0x81ef) mod 512 (17 + 239 = 256)
                    sbk   <= spritebank;
                    ti    <= 6'd0;
                    st    <= T_ADDR;
                end

                // ---------------------------------------------------- tiles
                T_ADDR: begin
                    vr_addr <= {my[8:3], tcol};
                    st      <= T_WAIT;
                end
                T_WAIT: st <= T_CAP;
                T_CAP: begin
`ifdef VERILATOR
                    if ($test$plusargs("RDBG") && y == 8'd0 && ti < 6'd4)
                        $display("RDBG line %0d ti %0d off_x %0d my %0d vr_addr %0d vr_data %08x", y, ti, off_x, my, vr_addr, vr_data);
`endif
                    attr_c <= vr_data[27:24];                       // attr bits 11:8: the palette group
                    t_addr <= CHR_BASE + {vr_data[13:0], my[2:0], 1'b0};   // the character ROM holds 16384 tiles: the code's low 14 bits
                    t_req  <= 1'b1;
                    st     <= T_FETCH;
                end
                T_FETCH: if (t_done) begin
                    t_req <= 1'b0;
                    pp    <= 3'd0;
                    st    <= T_PIX;
                end
                T_PIX: begin
                    if (tl_xx >= 11'sd0 && tl_xx < 11'sd320) begin
                        lb_we   <= 1'b1;
                        lb_addr <= {bk, tl_xx[8:0]};
                        lb_data <= {2'b00, attr_c, tl_pen};
                    end
                    pp <= pp + 3'd1;
                    if (pp == 3'd7) begin
                        if (ti == 6'd40) begin
                            ia <= 10'd0; scan_run <= 1'b1; v_sa <= 1'b0; v_sd <= 1'b0;
                            st <= S_SCAN;
                        end else begin
                            ti <= ti + 6'd1;
                            st <= T_ADDR;
                        end
                    end
                end

                // ---------------------------------------------------- sprites
                S_SCAN: begin
                    // pipeline: ia -> sr_addr -> (RAM) -> sr_data, evaluated on arrival
                    sr_addr <= {sbk, ia};
                    i_sa    <= ia;
                    v_sa    <= scan_run;
                    i_sd    <= i_sa;
                    v_sd    <= v_sa;
                    if (scan_run) begin
                        ia <= ia + 10'd1;
                        if (ia == 10'd1023) scan_run <= 1'b0;
                    end
                    if (hit) begin
                        sp_code  <= w3[11:0];
                        sp_color <= w2[3:0];
                        sp_flip  <= w3[15];
                        sp_x     <= x_s[9:0];
                        sp_row   <= row_s[3:0];
                        resume   <= i_sd + 10'd1;
                        last_hit <= (i_sd == 10'd1023);
                        s_addr   <= SPR_BASE + {w3[11:0], row_s[3:0], 2'b00};
                        s_req    <= 1'b1;
                        scan_run <= 1'b0;
                        v_sa     <= 1'b0;
                        v_sd     <= 1'b0;
                        st       <= S_FETCH;
                    end else if (!scan_run && !v_sa && !v_sd) begin
                        st <= S_IDLE;                                // all entries seen
                    end
                end
                S_FETCH: if (s_done) begin
                    s_req <= 1'b0;
                    sp    <= 4'd0;
                    st    <= S_DRAW;
                end
                S_DRAW: begin
                    if (sp_pen != 4'd0 && sp_xx >= 11'sd0 && sp_xx < 11'sd320) begin
                        lb_we   <= 1'b1;
                        lb_addr <= {bk, sp_xx[8:0]};
                        lb_data <= {2'b10, sp_color, sp_pen};
                    end
                    sp <= sp + 4'd1;
                    if (sp == 4'd15) begin
                        if (last_hit) st <= S_IDLE;
                        else begin
                            ia <= resume; scan_run <= 1'b1; v_sa <= 1'b0; v_sd <= 1'b0;
                            st <= S_SCAN;
                        end
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end

    wire unused = ^{hit_y};
endmodule
`default_nettype wire
