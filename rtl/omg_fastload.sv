// Fast load: the MRA's address= attribute makes Main_MiSTer copy the whole assembled image into the DDR3 (byte 0x32000000) in one go and then end a download that has no
// data bytes, only a start address = the image's length (OhMyGod.sv: fast_dl / fl_go / fast_len).  This module reads the image back from the DDR3 in 256-byte bursts and plays
// it into the loader's byte stream (the same strobe / address / byte as the HPS port's ioctl_wr / ioctl_addr / ioctl_dout), as long as the loader has room (`hold` =
// omg_mem's dl_wait).  The loader, the SDRAM write path and everything behind them are those of a streamed load.  The SDRAM write path takes about a word in ten clocks, so
// the 3.6 MB image loads in about 0.2 s (a streamed one takes several seconds).
// (From the owner's Metro core, rtl/metro_fastload.sv, with the DDR3 port wired straight to the framework: this core has no other DDR3 user.)
`default_nettype none
module omg_fastload #(
    parameter [24:0] FL_BASE = 25'h0400000      // the image's first 64-bit beat in the client's window (byte 0x30000000 + 0x2000000)
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        go,                     // one clock: the download that carried the length has ended
    input  logic [26:0] len,                    // the image's length in bytes
    output logic        busy,                   // from `go` until the last byte is out
    output logic        done,                   // one clock: the last byte has been played

    // the DDR3 client port (window byte 0x30000000)
    output logic        ddr_rd,
    output logic [24:0] ddr_addr,
    output logic  [7:0] ddr_burst,
    input  logic        ddr_busy,
    input  logic [63:0] ddr_dout,
    input  logic        ddr_dready,

    // the byte stream
    output logic        o_wr,
    output logic [25:0] o_addr,
    output logic  [7:0] o_data,
    input  logic        hold
);
    typedef enum logic [2:0] { F_IDLE, F_REQ, F_BEATS, F_PUSH, F_FIN } fst_t;
    fst_t        fst;
    // the block buffer: a plain MLAB (a write port without reset, a registered read); written inside the state machine's reset branch it became 2,048 flip-flops
    (* ramstyle = "MLAB, no_rw_check" *) logic [63:0] fbuf [0:31];
    logic [63:0] fb_q;
    logic [26:0] off;                           // the block's first byte
    logic [26:0] end_b;
    logic  [5:0] fbn;                           // beats of the block stored
    logic  [7:0] fi;                            // byte in the block
    logic  [8:0] fowed;                         // read beats still to come
    logic        pend;
    logic [63:0] cur;                           // the beat the byte comes from
    logic        cur_v;                         // `cur` holds beat fi[7:3]
    logic        rdy;                           // the buffer's registered read of beat fi[7:3] is there (one clock after the address)
    // the HPS port's read data and valid are registered once here before they reach the block buffer's write port: straight from the framework's
    // f2sdram flip-flops into the MLAB the path missed its hold time by 0.05 ns in two of the four fitter seeds tried (20261022)
    logic [63:0] dq_d;
    logic        dq_v;
    always_ff @(posedge clk) begin dq_d <= ddr_dout; dq_v <= ddr_dready; end
    wire         fb_we = (fst == F_BEATS) && dq_v;
    always_ff @(posedge clk) begin
        if (fb_we) fbuf[fbn[4:0]] <= dq_d;
        fb_q <= fbuf[fi[7:3]];
    end

    wire [26:0] byte_a = off + {19'd0, fi};

    always_ff @(posedge clk) begin
        o_wr <= 1'b0; done <= 1'b0;
        if (rst) fowed <= '0;
        else fowed <= fowed + ((ddr_rd && !ddr_busy) ? 9'(ddr_burst) : 9'd0) - (ddr_dready ? 9'd1 : 9'd0);
        if (ddr_rd && !ddr_busy) ddr_rd <= 1'b0;                // taken
        if (go) pend <= 1'b1;
        if (rst) begin
            fst <= F_IDLE; ddr_rd <= 1'b0; pend <= 1'b0; busy <= 1'b0; cur_v <= 1'b0; rdy <= 1'b0;
        end else case (fst)
            F_IDLE: if (pend && fowed == 9'd0) begin            // after any burst of an aborted load has come back
                pend <= 1'b0; busy <= 1'b1;
                off <= '0; end_b <= len;
                fst <= F_REQ;
            end
            F_REQ: begin
                if (off >= end_b) fst <= F_FIN;
                else if (!ddr_rd) begin
                    ddr_rd <= 1'b1; ddr_addr <= FL_BASE + 25'(off[26:3]); ddr_burst <= 8'd32;
                    fbn <= '0; fst <= F_BEATS;
                end
            end
            F_BEATS: if (dq_v) begin
                fbn <= fbn + 6'd1;
                if (fbn == 6'd31) begin fi <= '0; cur_v <= 1'b0; rdy <= 1'b0; fst <= F_PUSH; end
            end
            F_PUSH: begin
                // the beat is read from the buffer two clocks before its bytes go out (address, registered read)
                if (!cur_v) begin
                    if (!rdy) rdy <= 1'b1;
                    else begin cur <= fb_q; cur_v <= 1'b1; rdy <= 1'b0; end
                end else if (!hold) begin
                    if (byte_a < end_b) begin
                        o_wr <= 1'b1; o_addr <= byte_a[25:0]; o_data <= cur[8 * fi[2:0] +: 8];
                    end
                    if (fi == 8'd255) begin off <= off + 27'd256; fst <= F_REQ; cur_v <= 1'b0; end
                    else begin
                        fi <= fi + 8'd1;
                        if (fi[2:0] == 3'd7) cur_v <= 1'b0;
                    end
                end
            end
            F_FIN: begin done <= 1'b1; busy <= 1'b0; fst <= F_IDLE; end
            default: fst <= F_IDLE;
        endcase
    end
endmodule
`default_nettype wire
