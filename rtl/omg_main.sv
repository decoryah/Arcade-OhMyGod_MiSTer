// Atlus "Oh My God!" / "Naname de Magic!" board: the 68000 side.
//
// The 68000 (fx68k, 12 MHz), its memory map (MAME src/mame/atlus/ohmygod.cpp, ohmygod_state::main_map), the RAMs the video
// reads, the inputs, the OKI M6295 port, the registers and the watchdog.
//
//   000000-07FFFF  program ROM (SDRAM, through a cache)
//   300000-303FFF  RAM                      304000-307FFF  tile RAM (4096 tiles x {attr, code})
//   308000-30FFFF  RAM
//   400000 scroll x (w)   400002 scroll y (w)
//   600000-6007FF  palette RAM (xGRB555, 1024 entries)
//   700000-703FFF  sprite RAM (two banks of 1024 x 4 words)     704000-707FFF  RAM     708000-70FFFF  work RAM
//   800000 P1  800002 P2  A00000 DSW1  A00002 DSW2  (16 bit, active low)
//   900000         control (w): low byte = OKI bank (bits 7:4 Oh My God!, 3:0 Naname), high byte bits 12 / 13 coin counters
//   B00001         OKI M6295 (byte, low lane)
//   C00000         watchdog (r)
//   D00000         sprite bank (w, bit 15 of the word = bit 7 of the high byte)
//
// Every access completes with DTACK from here: block-RAM accesses after four clocks, ROM accesses when the cache has the word.
// Unmapped addresses read as 0 and swallow writes (MAME's defaults).
`default_nettype none

module omg_main (
    input  logic        clk,
    input  logic        reset,
    input  logic        hard_reset,                   // the reset without the watchdog's own
    input  logic [31:0] wdog_limit,                   // clocks without a kick before the reset: 3 s (MAME's time) = 288000000 at 96 MHz
    input  logic        cen_phi1, cen_phi2,           // 12 MHz CPU clock as alternating enables
    input  logic        cfg_game,                     // 0 Oh My God! (OKI bank in bits 7:4), 1 Naname de Magic! (bits 3:0)

    // program ROM word read (through the cache): level request until ack
    output logic        rom_req,
    output logic [18:1] rom_addr,
    input  logic        rom_ack,                      // one cycle, rom_data valid
    input  logic [15:0] rom_data,

    // inputs, active low, in the board's bit order
    input  logic [15:0] p1_in, p2_in, dsw1_in, dsw2_in,

    input  logic        vblank_irq,                   // pulse: raise the level 1 interrupt

    // video: tile RAM read port ({attr, code} of tile index)
    input  logic [11:0] vr_addr,
    output logic [31:0] vr_data,
    // video: sprite RAM read port ({bank, index}: word 3 .. word 0)
    input  logic [10:0] sr_addr,
    output logic [63:0] sr_data,
    // video: palette RAM read port
    input  logic [9:0]  pal_addr,
    output logic [15:0] pal_data,
    // video: registers (live)
    output logic [15:0] scrollx, scrolly,
    output logic        spritebank,

    // OKI M6295
    output logic        oki_wr,                       // one-cycle pulse
    output logic [7:0]  oki_din,
    input  logic [7:0]  oki_dout,
    output logic [3:0]  oki_bank,

    output logic        wdog_reset,                   // one cycle: the watchdog expired
    output logic        wdog_kick_o,                  // one cycle: the game kicked it

    // bus trace for the simulation
    output logic        trc_stb,
    output logic [23:1] trc_addr,
    output logic        trc_rw,
    output logic [15:0] trc_data,
    output logic [1:0]  trc_be,
    output logic        cpu_halted
);

    // ------------------------------------------------------------------ CPU
    logic [23:1] eab;
    logic [15:0] oEdb, iEdb;
    logic        eRWn, ASn, LDSn, UDSn, VMAn, E;
    logic        FC0, FC1, FC2, BGn, oRESETn, oHALTEDn;
    logic        DTACKn;

    wire iack = FC2 & FC1 & FC0 & ~ASn;

    // level 1 interrupt, held until acknowledged (MAME: irq1_line_hold)
    logic irq1;
    logic iack_d;
    always_ff @(posedge clk) begin
        iack_d <= iack;
        if (reset)                   irq1 <= 1'b0;
        else if (iack_d & ~iack)     irq1 <= 1'b0;
        else if (vblank_irq)         irq1 <= 1'b1;
    end

    logic pwr_d;
    always_ff @(posedge clk) pwr_d <= reset;

    fx68k u_cpu (
        .clk(clk), .HALTn(1'b1),
        .extReset(reset | pwr_d), .pwrUp(reset),
        .enPhi1(cen_phi1), .enPhi2(cen_phi2),
        .eRWn(eRWn), .ASn(ASn), .LDSn(LDSn), .UDSn(UDSn),
        .E(E), .VMAn(VMAn),
        .FC0(FC0), .FC1(FC1), .FC2(FC2),
        .BGn(BGn),
        .oRESETn(oRESETn), .oHALTEDn(oHALTEDn),
        .DTACKn(DTACKn), .VPAn(~iack),
        .BERRn(1'b1),
        .BRn(1'b1), .BGACKn(1'b1),
        .IPL0n(~irq1), .IPL1n(1'b1), .IPL2n(1'b1),
        .iEdb(iEdb), .oEdb(oEdb),
        .eab(eab)
    );
    assign cpu_halted = ~oHALTEDn;

    // ------------------------------------------------------------------ decode
    wire [23:0] ba = {eab, 1'b0};
    wire sel_rom   = ba[23:19] == 5'h00;
    wire sel_rama  = ba[23:14] == 10'h0C0;       // 300000
    wire sel_vram  = ba[23:14] == 10'h0C1;       // 304000
    wire sel_ramb  = ba[23:15] == 9'h061;        // 308000
    wire sel_pal   = ba[23:11] == 13'h0C00;      // 600000
    wire sel_spr   = ba[23:14] == 10'h1C0;       // 700000
    wire sel_ramc  = ba[23:14] == 10'h1C1;       // 704000
    wire sel_ramd  = ba[23:15] == 9'h0E1;        // 708000
    wire sel_scx   = eab == 23'h200000;          // 400000
    wire sel_scy   = eab == 23'h200001;          // 400002
    wire sel_p1    = eab == 23'h400000;          // 800000
    wire sel_p2    = eab == 23'h400001;          // 800002
    wire sel_ctrl  = eab == 23'h480000;          // 900000
    wire sel_dsw1  = eab == 23'h500000;          // A00000
    wire sel_dsw2  = eab == 23'h500001;          // A00002
    wire sel_oki   = eab == 23'h580000;          // B00000 / B00001 (the chip is on the low lane)
    wire sel_wdr   = eab == 23'h600000;          // C00000
    wire sel_sbk   = eab == 23'h680000;          // D00000

    // ------------------------------------------------------------------ RAMs
    logic        we;                             // one-cycle write strobe
    wire  [1:0]  be = {~UDSn, ~LDSn};

    logic [15:0] q_rama, q_attr, q_code, q_ramb, q_pal, q_ramc, q_ramd;
    logic [15:0] q_s0, q_s1, q_s2, q_s3;
    wire  [11:0] v_w = eab[12:1];                // word of the tile RAM: index * 2 + {0 attr, 1 code}

    omg_ram16 #(.AW(13)) u_rama (
        .clka(clk), .addra(eab[13:1]), .da(oEdb), .wea(we && sel_rama ? be : 2'b00), .qa(q_rama),
        .clkb(clk), .addrb(13'd0), .qb());
    // tile RAM: attr (even words) and code (odd words) in two RAMs so the renderer gets both in one read
    omg_ram16 #(.AW(12)) u_attr (
        .clka(clk), .addra(eab[13:2]), .da(oEdb), .wea(we && sel_vram && !eab[1] ? be : 2'b00), .qa(q_attr),
        .clkb(clk), .addrb(vr_addr), .qb(vr_data[31:16]));
    omg_ram16 #(.AW(12)) u_code (
        .clka(clk), .addra(eab[13:2]), .da(oEdb), .wea(we && sel_vram && eab[1] ? be : 2'b00), .qa(q_code),
        .clkb(clk), .addrb(vr_addr), .qb(vr_data[15:0]));
    omg_ram16 #(.AW(14)) u_ramb (
        .clka(clk), .addra(eab[14:1]), .da(oEdb), .wea(we && sel_ramb ? be : 2'b00), .qa(q_ramb),
        .clkb(clk), .addrb(14'd0), .qb());
    omg_ram16 #(.AW(10)) u_pal (
        .clka(clk), .addra(eab[10:1]), .da(oEdb), .wea(we && sel_pal ? be : 2'b00), .qa(q_pal),
        .clkb(clk), .addrb(pal_addr), .qb(pal_data));
    // sprite RAM: word field in four RAMs, {bank, index} as the address: 1024 sprites x 2 banks
    //   CPU word w = eab[13:1]: bank = w[12], index = w[11:2], field = w[1:0]
    omg_ram16 #(.AW(11)) u_s0 (
        .clka(clk), .addra(eab[13:3]), .da(oEdb), .wea(we && sel_spr && eab[2:1] == 2'd0 ? be : 2'b00), .qa(q_s0),
        .clkb(clk), .addrb(sr_addr), .qb(sr_data[15:0]));
    omg_ram16 #(.AW(11)) u_s1 (
        .clka(clk), .addra(eab[13:3]), .da(oEdb), .wea(we && sel_spr && eab[2:1] == 2'd1 ? be : 2'b00), .qa(q_s1),
        .clkb(clk), .addrb(sr_addr), .qb(sr_data[31:16]));
    omg_ram16 #(.AW(11)) u_s2 (
        .clka(clk), .addra(eab[13:3]), .da(oEdb), .wea(we && sel_spr && eab[2:1] == 2'd2 ? be : 2'b00), .qa(q_s2),
        .clkb(clk), .addrb(sr_addr), .qb(sr_data[47:32]));
    omg_ram16 #(.AW(11)) u_s3 (
        .clka(clk), .addra(eab[13:3]), .da(oEdb), .wea(we && sel_spr && eab[2:1] == 2'd3 ? be : 2'b00), .qa(q_s3),
        .clkb(clk), .addrb(sr_addr), .qb(sr_data[63:48]));
    omg_ram16 #(.AW(13)) u_ramc (
        .clka(clk), .addra(eab[13:1]), .da(oEdb), .wea(we && sel_ramc ? be : 2'b00), .qa(q_ramc),
        .clkb(clk), .addrb(13'd0), .qb());
    omg_ram16 #(.AW(14)) u_ramd (
        .clka(clk), .addra(eab[14:1]), .da(oEdb), .wea(we && sel_ramd ? be : 2'b00), .qa(q_ramd),
        .clkb(clk), .addrb(14'd0), .qb());

    // ------------------------------------------------------------------ registers
    // (the driver's COMBINE_DATA on the scroll words; the sprite bank is bit 15 of a write that reaches the high byte;
    //  the control word's low byte holds the OKI bank)
    // The scroll words and the sprite bank are plain latches: the machine's reset does not clear them (the game writes them
    // at start-up; MAME clears its copies, but its tilemap keeps the scroll it was given), which also lets the simulation hold the
    // CPU in reset with a frozen state loaded.
    logic [3:0] bank_r;
    initial begin scrollx = 16'd0; scrolly = 16'd0; spritebank = 1'b0; bank_r = 4'd0; end
    always_ff @(posedge clk) begin
        if (reset) bank_r <= 4'd0;
        else if (we) begin
            if (sel_ctrl && be[0]) bank_r <= cfg_game ? oEdb[3:0] : oEdb[7:4];
        end
        if (we) begin
            if (sel_scx) begin
                if (be[1]) scrollx[15:8] <= oEdb[15:8];
                if (be[0]) scrollx[7:0]  <= oEdb[7:0];
            end
            if (sel_scy) begin
                if (be[1]) scrolly[15:8] <= oEdb[15:8];
                if (be[0]) scrolly[7:0]  <= oEdb[7:0];
            end
            if (sel_sbk && be[1]) spritebank <= oEdb[15];
        end
    end
    assign oki_bank = bank_r;

    // ------------------------------------------------------------------ watchdog (MAME: 3 s, "a guess, and certainly wrong")
    logic [31:0] wd_cnt;
    logic        wd_kick;
    always_ff @(posedge clk) begin
        wdog_reset <= 1'b0;
        if (reset || wd_kick) wd_cnt <= 32'd0;
        else if (wd_cnt == wdog_limit) begin wd_cnt <= 32'd0; wdog_reset <= 1'b1; end
        else wd_cnt <= wd_cnt + 32'd1;
    end
    wire unused_hr = hard_reset;

    // ------------------------------------------------------------------ bus cycle
    logic        rdy;                             // DTACK
    logic [2:0]  cnt;
    logic        wr_seen;
    assign DTACKn = ~rdy;
    assign wdog_kick_o = wd_kick;

    logic [15:0] rd_mux;
    always_comb begin
        rd_mux = 16'h0000;
        if      (sel_rama)  rd_mux = q_rama;
        else if (sel_vram)  rd_mux = eab[1] ? q_code : q_attr;
        else if (sel_ramb)  rd_mux = q_ramb;
        else if (sel_pal)   rd_mux = q_pal;
        else if (sel_spr)   rd_mux = (eab[2:1] == 2'd0) ? q_s0 : (eab[2:1] == 2'd1) ? q_s1 : (eab[2:1] == 2'd2) ? q_s2 : q_s3;
        else if (sel_ramc)  rd_mux = q_ramc;
        else if (sel_ramd)  rd_mux = q_ramd;
        else if (sel_p1)    rd_mux = p1_in;
        else if (sel_p2)    rd_mux = p2_in;
        else if (sel_dsw1)  rd_mux = dsw1_in;
        else if (sel_dsw2)  rd_mux = dsw2_in;
        else if (sel_oki)   rd_mux = {8'h00, ~LDSn ? oki_dout : 8'h00};
    end

    assign rom_addr = eab[18:1];

    always_ff @(posedge clk) begin
        we         <= 1'b0;
        oki_wr     <= 1'b0;
        wd_kick    <= 1'b0;
        trc_stb    <= 1'b0;
        if (reset || ASn) begin
            rdy     <= 1'b0;
            cnt     <= 3'd0;
            wr_seen <= 1'b0;
            rom_req <= 1'b0;
        end else if (!iack && !rdy) begin
            if (!eRWn) begin
                // write: the data strobes (and the data) arrive a clock after AS
                if (!wr_seen) begin
                    if (be != 2'b00) begin
                        wr_seen <= 1'b1;
                        we      <= 1'b1;
                        if (sel_oki && be[0]) begin oki_din <= oEdb[7:0]; oki_wr <= 1'b1; end
                        trc_stb <= 1'b1; trc_addr <= eab; trc_rw <= 1'b0; trc_data <= oEdb; trc_be <= be;
                    end
                end else begin
                    rdy <= 1'b1;
                end
            end else if (sel_rom) begin
                // read from the ROM cache
                rom_req <= 1'b1;
                if (rom_ack) begin
                    iEdb    <= rom_data;
                    rom_req <= 1'b0;
                    rdy     <= 1'b1;
                    trc_stb <= 1'b1; trc_addr <= eab; trc_rw <= 1'b1; trc_data <= rom_data; trc_be <= be;
                end
            end else begin
                cnt <= cnt + 3'd1;
                if (cnt == 3'd3) begin
                    iEdb <= rd_mux;
                    rdy  <= 1'b1;
                    if (sel_wdr) wd_kick <= 1'b1;
                    trc_stb <= 1'b1; trc_addr <= eab; trc_rw <= 1'b1; trc_data <= rd_mux; trc_be <= be;
                end
            end
        end
    end
endmodule
`default_nettype wire
