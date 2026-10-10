// Memory of the OhMyGod core on MiSTer: the SDRAM (through sdram_ctrl), the ROM loader and the arbiter of the clients of its
// burst port.  (From mcatadv_mem.sv.)
//
// The MRA's image (tools/make_mra.py) arrives a byte at a time; a pair is one 16-bit word of the SDRAM (first byte in the low
// half).  The image is stored as it comes: image byte offset / 2 = SDRAM word address:
//
//   000000-07FFFF  68000 program          SDRAM word 000000   (the program cache, 8-word line fills)
//   080000-0FFFFF  character ROM          SDRAM word 040000   (tile rows: 2 words)
//   100000-17FFFF  sprite ROM             SDRAM word 080000   (sprite rows: 4 words)
//   180000-37FFFF  OKI M6295 samples      SDRAM word 0C0000   (the sound chip's byte reads)
//   380000         configuration byte: game (0 Oh My God!, 1 Naname de Magic!)
`default_nettype none
module omg_mem (
    input  logic        clk,
    input  logic        clk_sdram,
    input  logic        init,             // reset / (re)initialise the chip
    input  logic        rd_late,
    output logic        ready,

    // loader
    input  logic        dl_we,
    input  logic [24:0] dl_addr,
    input  logic [7:0]  dl_data,
    output logic        dl_wait,
    output logic        dl_busy,          // words still being written
    output logic        cfg_game,

    // burst clients: level request, a word per _wr with its index, a pulse at the end
    input  logic        p_req,            // 68000 program cache line fill (8 words)
    input  logic [18:4] p_addr,
    output logic        p_wr, output logic [2:0] p_idx, output logic [15:0] p_data, output logic p_done,

    input  logic        t_req,            // tile rows (2 words)
    input  logic [24:1] t_addr,
    output logic        t_wr, output logic [1:0] t_idx, output logic [15:0] t_data, output logic t_done,

    input  logic        s_req,            // sprite rows (4 words)
    input  logic [24:1] s_addr,
    output logic        s_wr, output logic [1:0] s_idx, output logic [15:0] s_data, output logic s_done,

    // OKI sample byte read: level request, one-cycle ack with the byte
    input  logic        pcm_req,
    input  logic [20:0] pcm_addr,
    output logic        pcm_ack,
    output logic [7:0]  pcm_q,

    // chip
    inout  wire  [15:0] SDRAM_DQ,
    output logic [12:0] SDRAM_A,
    output logic        SDRAM_DQML, SDRAM_DQMH,
    output logic  [1:0] SDRAM_BA,
    output logic        SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS,
    output logic        SDRAM_CKE, SDRAM_CLK
);
    localparam [24:1] SD_PROG = 24'h000000, SD_PCM = 24'h0C0000;
    localparam [24:1] IMG_END = 24'h1C0000;            // image word of the configuration bytes: not stored

    // ------------------------------------------------------------ the loader
    // bytes -> words (the image is sequential)
    logic        lo_v;
    logic [7:0]  lo_d;
    logic        wf_push;
    logic [39:0] wf_in;                           // {word address (24), data (16)}
    always_comb begin
        wf_push = 1'b0; wf_in = '0;
        if (dl_we && dl_addr[0] && lo_v) begin
            wf_push = 1'b1; wf_in = {dl_addr[24:1], dl_data, lo_d};
        end
    end
    always_ff @(posedge clk) begin
        if (dl_we) begin
            if (!dl_addr[0]) begin lo_v <= 1'b1; lo_d <= dl_data; end
            else lo_v <= 1'b0;
            if (dl_addr == 25'h380000) cfg_game <= dl_data[0];       // the configuration byte
        end
    end

    (* ramstyle = "no_rw_check" *) logic [39:0] wfifo [64];
    logic  [6:0] wf_wp, wf_rp;
    wire         wf_empty = (wf_wp == wf_rp);
    assign dl_wait = ((wf_wp - wf_rp) >= 7'd32);
    assign dl_busy = !wf_empty;

    logic [39:0] hd;
    wire  [24:1] wa = hd[39:16];
    wire  [15:0] wd = hd[15:0];

    typedef enum logic [1:0] { W_IDLE, W_DEC, W_SDRAM } wst_t;
    wst_t wst;
    logic        sd_wr_req;
    logic [24:1] sd_wr_addr;

    always_ff @(posedge clk) begin
        if (init) begin
            wf_wp <= '0; wf_rp <= '0; wst <= W_IDLE; sd_wr_req <= 1'b0;
        end else begin
            if (wf_push) begin wfifo[wf_wp[5:0]] <= wf_in; wf_wp <= wf_wp + 7'd1; end
            case (wst)
                W_IDLE: if (!wf_empty) begin hd <= wfifo[wf_rp[5:0]]; wst <= W_DEC; end
                W_DEC: begin
                    if (wa >= IMG_END) begin wf_rp <= wf_rp + 7'd1; wst <= W_IDLE; end                       // past the image
                    else begin sd_wr_addr <= wa; sd_wr_req <= 1'b1; wst <= W_SDRAM; end
                end
                W_SDRAM: if (sd_wr_ack) begin sd_wr_req <= 1'b0; wf_rp <= wf_rp + 7'd1; wst <= W_IDLE; end
                default: wst <= W_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------ SDRAM controller
    logic [24:1] c_addr  [2];
    logic        c_req   [2];
    logic        c_we    [2];
    logic [15:0] c_wdata [2];
    logic  [1:0] c_be    [2];
    logic        c_ack   [2];
    logic [15:0] sd_rdata;
    logic [24:1] b_addr;
    logic  [9:0] b_len, b_idx;
    logic        b_req, b_done, b_wr;
    logic [15:0] b_data;
    logic  [9:0] b_widx;
    logic        sd_ready;
    wire         sd_wr_ack = c_ack[1];

    // client 1: the loader
    assign c_addr[1] = sd_wr_addr;
    assign c_req[1]  = sd_wr_req;
    assign c_we[1]   = 1'b1;
    assign c_wdata[1] = wd;
    assign c_be[1]   = 2'b11;

    // client 0: sample byte reads, behind a registered stage
    typedef enum logic [1:0] { Q_IDLE, Q_BUSY, Q_ACK } qst_t;
    qst_t        qst;
    logic [20:0] pcm_a_l;
    logic [15:0] pcm_word;
    always_ff @(posedge clk) begin
        pcm_ack <= 1'b0;
        if (init) begin qst <= Q_IDLE; c_req[0] <= 1'b0; end
        else case (qst)
            Q_IDLE: if (pcm_req && !pcm_ack) begin
                pcm_a_l <= pcm_addr; c_addr[0] <= SD_PCM + {4'b0, pcm_addr[20:1]}; c_req[0] <= 1'b1; qst <= Q_BUSY;
            end
            Q_BUSY: if (c_ack[0]) begin pcm_word <= sd_rdata; c_req[0] <= 1'b0; qst <= Q_ACK; end
            Q_ACK: begin
                if (pcm_req && pcm_addr == pcm_a_l) pcm_ack <= 1'b1;
                qst <= Q_IDLE;
            end
            default: qst <= Q_IDLE;
        endcase
    end
    assign c_we[0]    = 1'b0;
    assign c_wdata[0] = '0;
    assign c_be[0]    = 2'b11;
    assign pcm_q      = pcm_a_l[0] ? pcm_word[15:8] : pcm_word[7:0];

    // ------------------------------------------------------------ burst arbiter
    typedef enum logic [1:0] { B_IDLE, B_RUN, B_ACK } bst_t;
    bst_t        bst;
    logic [1:0]  bsel;                            // 0 program, 1 tiles, 2 sprites
    always_ff @(posedge clk) begin
        if (init) begin bst <= B_IDLE; b_req <= 1'b0; end
        else case (bst)
            B_IDLE: begin
                if (p_req)      begin bsel <= 2'd0; b_addr <= SD_PROG + {6'd0, p_addr, 3'b000}; b_len <= 10'd8; b_req <= 1'b1; bst <= B_RUN; end
                else if (t_req) begin bsel <= 2'd1; b_addr <= t_addr; b_len <= 10'd2; b_req <= 1'b1; bst <= B_RUN; end
                else if (s_req) begin bsel <= 2'd2; b_addr <= s_addr; b_len <= 10'd4; b_req <= 1'b1; bst <= B_RUN; end
            end
            B_RUN: if (b_done) begin b_req <= 1'b0; bst <= B_ACK; end
            B_ACK: bst <= B_IDLE;                 // the client sees its done pulse and drops its request
            default: bst <= B_IDLE;
        endcase
    end
    wire run = (bst == B_RUN) && b_wr;
    assign p_wr = run && bsel == 2'd0;  assign p_idx = b_idx[2:0]; assign p_data = b_data;
    assign t_wr = run && bsel == 2'd1;  assign t_idx = b_idx[1:0]; assign t_data = b_data;
    assign s_wr = run && bsel == 2'd2;  assign s_idx = b_idx[1:0]; assign s_data = b_data;
    assign p_done = (bst == B_ACK) && bsel == 2'd0;
    assign t_done = (bst == B_ACK) && bsel == 2'd1;
    assign s_done = (bst == B_ACK) && bsel == 2'd2;

    sdram_ctrl #(.NCLI(2)) u_sdram (
        .clk(clk), .clk_pin(clk_sdram), .init(init), .rd_late(rd_late), .burst_slow(1'b0), .ready(sd_ready),
        .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH), .SDRAM_BA(SDRAM_BA),
        .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
        .SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK),
        .c_addr(c_addr), .c_req(c_req), .c_we(c_we), .c_wdata(c_wdata), .c_be(c_be), .c_ack(c_ack), .rdata(sd_rdata),
        .b_addr(b_addr), .b_len(b_len), .b_req(b_req), .b_abort(1'b0), .b_wr(b_wr), .b_idx(b_idx), .b_data(b_data), .b_done(b_done),
        .b_we(1'b0), .b_wdata(16'd0), .b_be(2'b00), .b_widx(b_widx)
    );
    assign ready = sd_ready;

    wire unused = ^{b_widx, b_idx[9:3]};
endmodule
`default_nettype wire
