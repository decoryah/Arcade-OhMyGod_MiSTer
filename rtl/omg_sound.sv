// The board's sound: one OKI M6295 (jt6295, Jose Tejada), clocked at 2 MHz (12 MHz / 6), pin 7 high (sample rate clock / 132 =
// 15.15 kHz), mono.  Its sample ROM is the 2 MB in SDRAM: the chip's 18-bit address space is a fixed 128 KB (0..1FFFF) and a
// window (20000..3FFFF) onto one of 16 banks of 128 KB, chosen by the control register (MAME: oki_map / m_okibank).
//
// The chip asks for a byte at its address and wants `rom_ok` while the byte is valid; the byte is read from the SDRAM whenever
// the address changes and held in a register.  The output is MAME's level (OKIM6295 route 1.0: the sum of up to four 12-bit
// voices, here already scaled the same by jt6295: 14 bit).
`default_nettype none
module omg_sound (
    input  logic        clk,
    input  logic        rst,
    input  logic        cen_oki,            // 2 MHz

    input  logic        wr,                 // one-cycle pulse
    input  logic [7:0]  din,
    output logic [7:0]  dout,
    input  logic [3:0]  bank,

    // sample byte read: level request until ack (target/omg_mem.sv)
    output logic        pcm_req,
    output logic [20:0] pcm_addr,
    input  logic        pcm_ack,
    input  logic [7:0]  pcm_q,

    output logic signed [13:0] snd
);
    logic       wrn;
    logic [7:0] din_r;
    always_ff @(posedge clk) begin
        wrn <= 1'b1;
        if (wr) begin din_r <= din; wrn <= 1'b0; end
    end

    logic [17:0] rom_addr;
    logic [7:0]  rom_data;
    logic        rom_ok;
    jt6295 #(.INTERPOL(0)) u_oki (
        .rst(rst), .clk(clk), .cen(cen_oki), .ss(1'b1),
        .wrn(wrn), .din(din_r), .dout(dout),
        .rom_addr(rom_addr), .rom_data(rom_data), .rom_ok(rom_ok),
        .sound(snd), .sample()
    );

    // byte address in the 2 MB: the banked window selects one of 16 128 KB banks
    wire [20:0] want = {rom_addr[17] ? bank : 4'd0, rom_addr[16:0]};

    logic [20:0] srv_a;
    logic        have;
    always_ff @(posedge clk) begin
        if (rst) begin
            have <= 1'b0; pcm_req <= 1'b0; rom_data <= 8'h00; srv_a <= 21'd0;
        end else begin
            if (pcm_ack) begin
                rom_data <= pcm_q; srv_a <= pcm_addr; have <= 1'b1; pcm_req <= 1'b0;
            end else if (!pcm_req && !(have && srv_a == want)) begin
                pcm_addr <= want; pcm_req <= 1'b1;
            end
        end
    end
    assign rom_ok = have && (srv_a == want);
endmodule
`default_nettype wire
