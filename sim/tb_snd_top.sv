// OKI bench: omg_sound behind omg_mem and the SDRAM model, driven by the C++ side with recorded write events.
`default_nettype none
module tb_snd_top (
    input  logic        clk,
    input  logic        init,
    input  logic        rst,
    input  logic        wr,
    input  logic [7:0]  din,
    input  logic [3:0]  bank,
    output logic [7:0]  dout,
    output logic        mem_ready,
    output logic signed [13:0] snd
);
    wire  [15:0] dram_dq;
    wire  [12:0] dram_a;
    wire  [1:0]  dram_ba;
    wire         dram_dqml, dram_dqmh, dram_ncs, dram_nras, dram_ncas, dram_nwe, dram_cke, dram_clk;
    logic        pcm_req, pcm_ack;
    logic [20:0] pcm_addr;
    logic [7:0]  pcm_q;
    logic        cen_phi1, cen_phi2, cen_oki;

    omg_cen u_cen (.clk(clk), .cen_phi1(cen_phi1), .cen_phi2(cen_phi2), .cen_oki(cen_oki));

    omg_mem u_mem (
        .clk(clk), .clk_sdram(clk), .init(init), .rd_late(1'b0), .ready(mem_ready),
        .dl_we(1'b0), .dl_addr(25'd0), .dl_data(8'd0), .dl_wait(), .dl_busy(), .cfg_game(),
        .p_req(1'b0), .p_addr(15'd0), .p_wr(), .p_idx(), .p_data(), .p_done(),
        .t_req(1'b0), .t_addr(24'd0), .t_wr(), .t_idx(), .t_data(), .t_done(),
        .s_req(1'b0), .s_addr(24'd0), .s_wr(), .s_idx(), .s_data(), .s_done(),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
        .SDRAM_DQ(dram_dq), .SDRAM_A(dram_a), .SDRAM_DQML(dram_dqml), .SDRAM_DQMH(dram_dqmh), .SDRAM_BA(dram_ba),
        .SDRAM_nCS(dram_ncs), .SDRAM_nWE(dram_nwe), .SDRAM_nRAS(dram_nras), .SDRAM_nCAS(dram_ncas),
        .SDRAM_CKE(dram_cke), .SDRAM_CLK(dram_clk)
    );
    sdram_model #(.PHASE_LAG(0), .AW(23)) chip (
        .clk(clk), .dq(dram_dq), .a(dram_a), .ba(dram_ba), .dqml(dram_dqml), .dqmh(dram_dqmh),
        .cs_n(dram_ncs), .ras_n(dram_nras), .cas_n(dram_ncas), .we_n(dram_nwe), .cke(dram_cke)
    );
    omg_sound u_snd (
        .clk(clk), .rst(rst), .cen_oki(cen_oki), .wr(wr), .din(din), .dout(dout), .bank(bank),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q), .snd(snd)
    );
    export "DPI-C" function tb_sdram_write;
    function void tb_sdram_write(input int idx, input int w);
        chip.mem[idx[22:0]] = w[15:0];
    endfunction
endmodule
