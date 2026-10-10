// Clock enables from the 96 MHz machine clock: the 68000 at 12 MHz (96 / 8, as the alternating phase enables fx68k wants,
// phases four clocks apart: the same pattern as the owner's other 12 MHz boards) and the OKI M6295's master clock, 2 MHz
// (12 MHz / 6 on the board = 96 / 48).  The dot clock (6 MHz = 96 / 16) is generated in omg_video.
`default_nettype none
module omg_cen (
    input  logic clk,
    output logic cen_phi1, cen_phi2,
    output logic cen_oki
);
    logic [2:0] c8  = 3'd0;
    logic [5:0] c48 = 6'd0;
    always_ff @(posedge clk) begin
        c8  <= c8 + 3'd1;                                   // wraps at 8
        c48 <= (c48 == 6'd47) ? 6'd0 : c48 + 6'd1;
        cen_phi1 <= (c8 == 3'd7);
        cen_phi2 <= (c8 == 3'd3);
        cen_oki  <= (c48 == 6'd47);
    end
endmodule
`default_nettype wire
