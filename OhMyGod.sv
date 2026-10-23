//============================================================================
//
//  Atlus "Oh My God!" (1993) and "Naname de Magic!" (1994) -- MAME's atlus/ohmygod.cpp -- for MiSTer.
//
//  Written for MiSTer from MAME 0.289's driver (src/mame/atlus/ohmygod.cpp).  The 68000 is fx68k (Jorge Cwik), the OKI M6295
//  is jt6295 (Jose Tejada); the platform layer (SDRAM controller, loader, CRT adjust) follows the owner's other cores
//  (mcatadv-mister, metro-mister).
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S   = 1;       // signed samples
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

//////////////////////////////////////////////////////////////////

wire [127:0] status;
wire   [1:0] buttons;
wire         forced_scandoubler;
wire         direct_video;
wire  [21:0] gamma_bus;

// Aspect ratio and Scale. The framework's video_freak (after arcade_video, below) turns the two into VIDEO_ARX/ARY: with
// Scale Normal they pass through as they are; the integer modes replace them with the exact size in pixels (bit 12 set)
// that the HDMI scaler should give the picture. The menu's order is the user's; video_freak's SCALE input counts
// 0 Normal, 1 V-Integer, 2 Narrower HV-Integer, 3 HV-Integer+ (wider), 4 HV-Integer
wire  [1:0] ar = status[122:121];
reg   [2:0] scale_sel;
always @* case (status[34:32])
	3'd1:    scale_sel = 3'd1;   // V-Integer
	3'd2:    scale_sel = 3'd4;   // HV-Integer
	3'd3:    scale_sel = 3'd2;   // Narrower HV-Integer
	3'd4:    scale_sel = 3'd3;   // HV-Integer+
	default: scale_sel = 3'd0;   // Normal
endcase
// Full Screen is ARX = ARY = 0 ("fill"), which has no proportions for the integer rule to size the width from: it sizes the
// height from the width instead and asks for more rows than the screen has. With an integer Scale the screen's own
// proportions stand in for it, so the picture is a whole-number size in the screen's aspect
wire        fs_int = (ar == 2'd1) && (scale_sel != 3'd0) && (HDMI_WIDTH != 12'd0) && (HDMI_HEIGHT != 12'd0);

`include "build_id.v"
localparam CONF_STR = {
	"A.OHMYGOD;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[34:32],Scale,Normal,V-Integer,HV-Integer,Narrower HV-Integer,HV-Integer+;",
	"O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"P1,CRT Adjust;",
	"P1O[101],CRT Adjust,Off,On;",
	"H3P1O[100:96],H-Size,0,+1,+2,+3,+4,+5,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H3P1O[85:79],H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H3P1O[78:74],V-Shift,0,+1,+2,+3,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	"DIP;",
	"-;",
	"O[9:8],Volume,Normal,-6 dB,-12 dB,-18 dB;",
	"O[10],Sprite bank flip,Live,At vblank;",
	"O[20],SDRAM read capture,Normal,Late;",
	"-;",
	"R0,Reset;",
	"J1,Button,Start,Coin;",
	"jn,A,Start,Select,R;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;           // 96 MHz: the machine (68000 /8 = 12 MHz, OKI /48 = 2 MHz, dots /16 = 6 MHz)
wire clk_sdram;         // 96 MHz, shifted: the SDRAM chip's clock pin
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_sdram),
	.outclk_2(),
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire         ioctl_download;
wire         ioctl_wr;
wire  [15:0] ioctl_index;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire         ioctl_wait;

wire  [31:0] joystick_0, joystick_1;
wire  [10:0] ps2_key;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),

	.buttons(buttons),
	.status(status),
	.status_menumask({12'd0, ~status[101], 1'b0, 1'b0, direct_video}),
	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),
	.gamma_bus(gamma_bus),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);

///////////////////////   DIP SWITCHES (from the MRA)   ///////////////////////

// ioctl index 254: byte 0 = the high byte of MAME's DSW1 port, byte 1 = the high byte of DSW2; a 1 is MAME's default.
// The low bytes of both ports are unused inputs (active low: read 1).
reg [7:0] sw[2];
initial begin sw[0] = 8'hFF; sw[1] = 8'hFF; end
always @(posedge clk_sys) begin
	if (ioctl_wr && (ioctl_index[7:0] == 8'd254) && !ioctl_addr[26:1]) sw[ioctl_addr[0]] <= ioctl_dout;
end

///////////////////////   CONTROLS   ///////////////////////

// keyboard: 1/2 start, 5/6 coin, 9 service credit, F2 test switch (MAME's defaults)
reg key_start1, key_start2, key_coin1, key_coin2, key_service, key_test;
always @(posedge clk_sys) begin
	reg old_stb;
	old_stb <= ps2_key[10];
	if (old_stb != ps2_key[10]) begin
		case (ps2_key[8:0])
			9'h016: key_start1  <= ps2_key[9];
			9'h01E: key_start2  <= ps2_key[9];
			9'h02E: key_coin1   <= ps2_key[9];
			9'h036: key_coin2   <= ps2_key[9];
			9'h046: key_service <= ps2_key[9];
			9'h006: key_test    <= ps2_key[9];      // F2
			default: ;
		endcase
	end
end

// joystick bits: 0 right, 1 left, 2 down, 3 up, 4 button, 5 start, 6 coin (the MRA's <buttons> list names them)
wire j1_r = joystick_0[0], j1_l = joystick_0[1], j1_d = joystick_0[2], j1_u = joystick_0[3], j1_b = joystick_0[4];
wire j2_r = joystick_1[0], j2_l = joystick_1[1], j2_d = joystick_1[2], j2_u = joystick_1[3], j2_b = joystick_1[4];
wire start1 = joystick_0[5] | key_start1, coin1 = joystick_0[6] | key_coin1;
wire start2 = joystick_1[5] | key_start2, coin2 = joystick_1[6] | key_coin2;
// the two service inputs are different switches (MAME: P2 "Service 1", key 9; P1 "Service Mode", key F2) and the program treats
// them differently: P2 bit 9 is a service credit, P1 bit 9 makes the vertical-blank interrupt enter the test menu.  They are keys only:
// the controller's button mapping has no entry for them
wire service = key_service;
wire test_sw = key_test;

// the board's inputs, active low (MAME's INPUT_PORTS ohmygod, naname):
//   P1: bit 0 up, 1 down, 2 left, 3 right, 4 button 1, 7 start 1, 8 coin 1, 9 service mode (the test switch, no toggle)
//   P2: the same, bit 7 start 2, 8 coin 2, 9 service 1 (a credit)
wire [15:0] p1_in = ~{6'd0, test_sw, coin1, start1, 2'b00, j1_b, j1_r, j1_l, j1_d, j1_u};
wire [15:0] p2_in = ~{6'd0, service, coin2, start2, 2'b00, j2_b, j2_r, j2_l, j2_d, j2_u};
wire [15:0] dsw1_in = {sw[0], 8'hFF};
wire [15:0] dsw2_in = {sw[1], 8'hFF};

///////////////////////   MEMORY   ///////////////////////

// the ROM image: MRA index 0
wire        rom_dl = ioctl_download && (ioctl_index[7:0] == 8'd0);

// Fast load: with address= on the MRA's index-0 <rom>, Main_MiSTer copies the whole assembled image into the DDR3 (byte 0x32000000)
// in one go and then ends a download that has no data bytes, only a start address: the image's length (ioctl_addr, which is 0 at
// the start of an ordinary download). The machine stays in reset from that start until rtl/omg_fastload.sv has read the image back
// and played it into the loader as the HPS port would have streamed it. An older Main_MiSTer ignores the attribute and streams the
// bytes as before; nothing here touches that path.
reg         rom_dl_d;
always @(posedge clk_sys) rom_dl_d <= rom_dl;
wire        dl_start = rom_dl && !rom_dl_d;
wire        dl_done  = !rom_dl && rom_dl_d;
reg         fast_dl = 1'b0;
reg  [26:0] fast_len;
wire        fl_go    = fast_dl && dl_done;
wire        fl_done;
always @(posedge clk_sys) begin
	if (dl_start) begin fast_dl <= (ioctl_addr != 27'd0); fast_len <= ioctl_addr; end
	else if (fl_done || !pll_locked) fast_dl <= 1'b0;
end
wire        fl_wr;
wire [25:0] fl_addr;
wire  [7:0] fl_data;
wire        fl_ddr_rd, fl_busy_unused;
wire [24:0] fl_ddr_addr;
wire  [7:0] fl_ddr_burst;

// the loader's byte stream: the HPS port's, or the fast load's replay
wire        dl_we   = fl_wr || (rom_dl && ioctl_wr);
wire [24:0] dl_addr = fl_wr ? fl_addr[24:0] : ioctl_addr[24:0];
wire  [7:0] dl_data = fl_wr ? fl_data : ioctl_dout;

wire        mem_init = ~pll_locked | RESET;
wire        mem_ready;
wire        dl_busy;

wire        p_req, t_req, s_req, pcm_req;
wire [18:4] p_addr;
wire [24:1] t_addr, s_addr;
wire [20:0] pcm_addr;
wire        p_wr, t_wr, s_wr, p_done, t_done, s_done, pcm_ack;
wire  [2:0] p_idx;
wire  [1:0] t_idx, s_idx;
wire [15:0] p_data, t_data, s_data;
wire  [7:0] pcm_q;
wire        cfg_game;

omg_mem u_mem
(
	.clk(clk_sys), .clk_sdram(clk_sdram), .init(mem_init), .rd_late(status[20]), .ready(mem_ready),
	.dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data), .dl_wait(ioctl_wait), .dl_busy(dl_busy), .cfg_game(cfg_game),
	.p_req(p_req), .p_addr(p_addr), .p_wr(p_wr), .p_idx(p_idx), .p_data(p_data), .p_done(p_done),
	.t_req(t_req), .t_addr(t_addr), .t_wr(t_wr), .t_idx(t_idx), .t_data(t_data), .t_done(t_done),
	.s_req(s_req), .s_addr(s_addr), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
	.pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH), .SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK)
);

// the fast load's reads of the image from the DDR3: the framework's port, byte 0x30000000 + the client's window; this core has no other
// user of the DDR3 and never writes it
omg_fastload u_fastload
(
	.clk(clk_sys), .rst(~pll_locked), .go(fl_go), .len(fast_len), .busy(fl_busy_unused), .done(fl_done),
	.ddr_rd(fl_ddr_rd), .ddr_addr(fl_ddr_addr), .ddr_burst(fl_ddr_burst), .ddr_busy(DDRAM_BUSY), .ddr_dout(DDRAM_DOUT), .ddr_dready(DDRAM_DOUT_READY),
	.o_wr(fl_wr), .o_addr(fl_addr), .o_data(fl_data), .hold(ioctl_wait)
);
assign DDRAM_CLK      = clk_sys;
assign DDRAM_BURSTCNT = fl_ddr_burst;
assign DDRAM_ADDR     = {4'd3, fl_ddr_addr};
assign DDRAM_RD       = fl_ddr_rd;
assign DDRAM_DIN      = 64'd0;
assign DDRAM_BE       = 8'hFF;
assign DDRAM_WE       = 1'b0;

///////////////////////   THE MACHINE   ///////////////////////

wire        reset_sw = RESET | status[0] | buttons[1];
// the machine is held while a ROM loads (streamed or replayed from the DDR3) and until the memory is up; registered, it fans out
// to the whole core
reg         mc_rst = 1'b1;
always @(posedge clk_sys) mc_rst <= reset_sw | rom_dl | fast_dl | dl_busy | ~mem_ready | ~pll_locked;

wire        ce_pix, hblank, vblank, hsync, vsync;
wire [23:0] rgb;
wire signed [13:0] snd;
wire        dbg_ovr, dbg_irq, dbg_halted, dbg_wdog, dbg_render_busy;

omg_core u_core
(
	.clk(clk_sys), .rst(mc_rst), .cpu_hold(1'b0), .wdog_limit(32'd288_000_000),
	.cache_inval(rom_dl | fast_dl | mem_init), .cfg_game(cfg_game), .sb_latch(status[10]),
	.p_req(p_req), .p_addr(p_addr), .p_wr(p_wr), .p_idx(p_idx), .p_data(p_data), .p_done(p_done),
	.t_req(t_req), .t_addr(t_addr), .t_wr(t_wr), .t_idx(t_idx), .t_data(t_data), .t_done(t_done),
	.s_req(s_req), .s_addr(s_addr), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
	.pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
	.p1_in(p1_in), .p2_in(p2_in), .dsw1_in(dsw1_in), .dsw2_in(dsw2_in),
	.ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .rgb(rgb),
	.snd(snd),
	.dbg_ovr(dbg_ovr), .dbg_irq(dbg_irq), .dbg_halted(dbg_halted), .dbg_wdog(dbg_wdog), .dbg_render_busy(dbg_render_busy),
	.dbg_addr(), .trc_stb(), .trc_rw(), .trc_data(), .trc_be()
);

///////////////////////   AUDIO   ///////////////////////

// MAME's output is exactly 16 times jt6295's 14-bit sum of the OKI's voices (measured on MAME's own recording of the same OKI
// writes: envelope correlation 1.000 at lag 0, a constant -24.0 dB), clipped to 16 bits as MAME does: "Normal" is that level,
// the others 6 / 12 / 18 dB lower.
reg signed [15:0] aud;
wire signed [18:0] aud_x16 = {{1{snd[13]}}, snd, 4'b0000};            // x16: 19 bits
wire signed [18:0] aud_sh  = aud_x16 >>> {1'b0, status[9:8]} ;         // x16, x8, x4, x2
always @(posedge clk_sys) begin
	if (aud_sh > 19'sd32767)       aud <= 16'sd32767;
	else if (aud_sh < -19'sd32768) aud <= -16'sd32768;
	else                           aud <= aud_sh[15:0];
end
assign AUDIO_L = aud;
assign AUDIO_R = aud;

///////////////////////   VIDEO   ///////////////////////

// CRT Adjust (OSD page of the same name): H-Size, H-Position and V-Shift of the picture, through rmonic79's line buffer
// (rtl/omg_crtadj.sv). It is for the 15 kHz output and does nothing while the scandoubler is in use (Scandoubler Fx or the
// framework's forced_scandoubler): the module's blank includes the vertical one, and the scandoubler needs the horizontal blank
// alone, on every line (without it the picture freezes and there is no vertical sync)
wire        ca_on = status[101] & ~((|status[5:3]) | forced_scandoubler);
wire        ca_ce, ca_hblank, ca_vblank, ca_hs, ca_vs;
wire [23:0] vid_rgb;
wire [23:0] rgb_in = mc_rst ? 24'd0 : rgb;
omg_crtadj u_crtadj
(
	.clk(clk_sys), .i_on(ca_on), .i_hsize_f(status[100:96]), .i_hpos_f(status[85:79]), .i_vshift_f(status[78:74]), .i_pdot(5'd16),
	.i_ce(ce_pix), .i_hblank(hblank), .i_vblank(vblank), .i_hs(hsync), .i_vs(vsync), .i_rgb(rgb_in),
	.o_ce(ca_ce), .o_hblank(ca_hblank), .o_vblank(ca_vblank), .o_hs(ca_hs), .o_vs(ca_vs), .o_rgb(vid_rgb)
);
wire        vga_de_mix;

arcade_video #(.WIDTH(320), .DW(24)) arcade_video
(
	.*,
	.clk_video(clk_sys),
	.ce_pix(ca_ce),
	.RGB_in(vid_rgb),
	.HBlank(ca_hblank),
	.VBlank(ca_vblank),
	.HSync(ca_hs),
	.VSync(ca_vs),
	.fx(status[5:3]),
	.VGA_DE(vga_de_mix)
);

video_freak video_freak
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_VS(VGA_VS),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),
	.VGA_DE_IN(vga_de_mix),
	.ARX(fs_int ? HDMI_WIDTH  : (ar == 2'd0) ? 12'd4 : {10'd0, ar - 2'd1}),
	.ARY(fs_int ? HDMI_HEIGHT : (ar == 2'd0) ? 12'd3 : 12'd0),
	.CROP_SIZE(12'd0),
	.CROP_OFF(5'd0),
	.SCALE(scale_sel)
);

///////////////////////   LEDs   ///////////////////////

// user LED: on while the machine is held (a ROM loading), blinks once per frame while it runs, blinks fast once a line has not
// been finished in time (since the reset)
reg        led_vbl_toggle, led_ovr;
reg [23:0] led_cnt;
always @(posedge clk_sys) begin
	led_cnt <= led_cnt + 24'd1;
	if (dbg_irq) led_vbl_toggle <= ~led_vbl_toggle;
	if (mc_rst) led_ovr <= 1'b0;
	else if (dbg_ovr) led_ovr <= 1'b1;
end
assign LED_USER = mc_rst ? 1'b1 : led_ovr ? led_cnt[22] : led_vbl_toggle;

endmodule
