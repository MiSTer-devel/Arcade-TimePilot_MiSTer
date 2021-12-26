//============================================================================
// 
//  Time Pilot main PCB model
//  Copyright (C) 2021 Ace, Artemio Urbina & RTLEngineering
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the 
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

//Module declaration, I/O ports
module TimePilot_CPU
(
	input         reset,
	input         clk_49m,          //Actual frequency: 49.152MHz
	output  [4:0] red, green, blue, //15-bit RGB, 5 bits per color
	output        video_hsync, video_vsync, video_csync, //CSync not needed for MISTer
	output        video_hblank, video_vblank,
	output        ce_pix,
	
	input   [7:0] controls_dip,
	output  [7:0] cpubrd_Dout,
	output        cpubrd_A5, cpubrd_A6,
	output        cs_sounddata, irq_trigger,
	output        cs_dip2, cs_controls_dip1,
	
	//Screen centering (alters HSync, VSync and VBlank timing in the Konami 082 to reposition the video output)
	input   [3:0] h_center, v_center,
	
	input         ep1_cs_i,
	input         ep2_cs_i,
	input         ep3_cs_i,
	input         ep4_cs_i,
	input         ep5_cs_i,
	input         ep6_cs_i,
	input         cp1_cs_i,
	input         cp2_cs_i,
	input         tl_cs_i,
	input         sl_cs_i,
	input  [24:0] ioctl_addr,
	input   [7:0] ioctl_data,
	input         ioctl_wr,
	
	input         pause,

	input  [15:0] hs_address,
	input   [7:0] hs_data_in,
	output  [7:0] hs_data_out,
	input         hs_write
);

//------------------------------------------------------- Signal outputs -------------------------------------------------------//

//Assign active high HBlank and VBlank outputs
assign video_hblank = hblk;
assign video_vblank = vblk;

//Output pixel clock enable
assign ce_pix = cen_6m;

//Output select lines for player inputs and DIP switches to sound board
assign cs_controls_dip1 = (~n_cs_k501 & z80_A[14]) & (z80_A[13:12] == 2'b00) & (z80_A[9:8] == 2'b11) & n_ram_write;
assign cs_dip2 = (~n_cs_k501 & z80_A[14]) & (z80_A[13:12] == 2'b00) & (z80_A[9:8] == 2'b10) & n_ram_write;

//Output primary MC6809E address lines A5 and A6 to sound board
assign cpubrd_A5 = z80_A[5];
assign cpubrd_A6 = z80_A[6];

//Assign CPU board data output to sound board
assign cpubrd_Dout = z80_Dout;

//Generate and output chip select for latching sound data to sound CPU
assign cs_sounddata = (~n_cs_k501 & z80_A[14]) & (z80_A[13:12] == 2'b00) & (z80_A[9:8] == 2'b00) & ~n_ram_write;

//Generate sound IRQ trigger
reg sound_irq = 1;
always_ff @(posedge clk_49m) begin
	if(cen_3m) begin
		if(cs_soundirq)
			sound_irq <= 1;
		else
			sound_irq <= 0;
	end
end
assign irq_trigger = sound_irq;

//------------------------------------------------------- Clock division -------------------------------------------------------//

//Generate 12.288MHz, 6.144MHz and 3.072MHz clock enables
reg [3:0] div = 4'd0;
always_ff @(posedge clk_49m) begin
	div <= div + 4'd1;
end
wire cen_12m = !div[1:0];
wire cen_6m = !div[2:0];
wire cen_3m = !div;

//------------------------------------------------------------ CPUs ------------------------------------------------------------//

//Primary CPU - Zilog Z80 (uses T80s version of the T80 soft core)
wire [15:0] z80_A;
wire [7:0] z80_Dout;
wire n_mreq, n_rd, n_rfsh;
T80s E3
(
	.RESET_n(reset),
	.CLK(clk_49m),
	.CEN(cen_3m & ~pause),
	.NMI_n(n_nmi),
	.WAIT_n(n_wait),
	.MREQ_n(n_mreq),
	.RD_n(n_rd),
	.RFSH_n(n_rfsh),
	.A(z80_A),
	.DI(z80_Din),
	.DO(z80_Dout)
);
//Address decoding for Z80
//Most of the decoding is handled by the Konami 526 (82S153 PLA) - instantiate an instance of this IC here
wire n_cs_rom1, n_cs_rom2, n_cs_rom3, n_cs_k501, n_cs_vram_wram, n_cs_spriteram0, n_cs_spriteram1;
k526 E1
(
	.MREQ(n_mreq),
	.RFSH(n_rfsh),
	.A15(z80_A[15]),
	.A14(z80_A[14]),
	.A13(z80_A[13]),
	.A12(z80_A[12]),
	.A10(z80_A[10]),
	.ENABLE(n_k501_enable),
	.SPRAM0(n_cs_spriteram0),
	.SPRAM1(n_cs_spriteram1),
	.WRAM(n_cs_vram_wram),
	.K501(n_cs_k501),
	.ROM({1'bZ, n_cs_rom3, n_cs_rom2, n_cs_rom1})
);
//The rest of the decoding is handled by the Konami 501 custom chip - instantiate an instance of this IC here
wire n_wait, n_ram_write, n_k501_enable;
wire [7:0] k501_D, k501_Dout;
k501 C3
(
	.CLK(clk_49m),
	.CEN(cen_12m),
	.H1(h_cnt[0]),
	.H2(h_cnt[1]),
	.RAM(n_cs_k501),
	.RD(n_rd),
	.WAIT(n_wait),
	.WRITE(n_ram_write),
	.ENABLE(n_k501_enable),
	.Di(z80_Dout),
	.XDi(k501_Din),
	.Do(k501_Dout),
	.XDo(k501_D)
);
wire cs_beam = (~n_cs_k501 & z80_A[14]) & (z80_A[13:12] == 2'b00) & (z80_A[9:8] == 2'b00) & n_ram_write;
wire cs_mainlatch = (~n_cs_k501 & z80_A[14]) & (z80_A[13:12] == 2'b00) & (z80_A[9:8] == 2'b11) & ~n_ram_write;
//Multiplex data inputs to Z80
wire [7:0] z80_Din = ~n_cs_rom1 ? eprom1_D:
                     ~n_cs_rom2 ? eprom2_D:
                     ~n_cs_rom3 ? eprom3_D:
                     ~n_cs_k501 ? k501_Dout:
                     8'hFF;

//Game ROMs
//ROM 1/3
wire [7:0] eprom1_D;
eprom_1 H2
(
	.ADDR(z80_A[12:0]),
	.CLK(clk_49m),
	.DATA(eprom1_D),
	.ADDR_DL(ioctl_addr),
	.CLK_DL(clk_49m),
	.DATA_IN(ioctl_data),
	.CS_DL(ep1_cs_i),
	.WR(ioctl_wr)
);
//ROM 2/3
wire [7:0] eprom2_D;
eprom_2 H3
(
	.ADDR(z80_A[12:0]),
	.CLK(clk_49m),
	.DATA(eprom2_D),
	.ADDR_DL(ioctl_addr),
	.CLK_DL(clk_49m),
	.DATA_IN(ioctl_data),
	.CS_DL(ep2_cs_i),
	.WR(ioctl_wr)
);
//ROM 3/3
wire [7:0] eprom3_D;
eprom_3 H4
(
	.ADDR(z80_A[12:0]),
	.CLK(clk_49m),
	.DATA(eprom3_D),
	.ADDR_DL(ioctl_addr),
	.CLK_DL(clk_49m),
	.DATA_IN(ioctl_data),
	.CS_DL(ep3_cs_i),
	.WR(ioctl_wr)
);

//Multiplex data input to Konami 501 data bus passthrough
wire [7:0] k501_Din = (~n_cs_vram_wram & ~vram_wram_sel & n_vram_wram_wr) ? vram_D:
                      (~n_cs_vram_wram & vram_wram_sel & n_vram_wram_wr)  ? wram_D:
                      (~n_cs_spriteram0 & n_spriteram0_wr)                ? spriteram_D[7:0]:
                      (~n_cs_spriteram1 & n_spriteram1_wr)                ? spriteram_D[15:8]:
                      cs_beam                                             ? v_cnt:
                      (cs_controls_dip1 | cs_dip2)                        ? controls_dip:
                      8'hFF;

//Z80 work RAM
wire [7:0] wram_D;
dpram_dc #(.widthad_a(11)) F9
(
	.clock_a(clk_49m),
	.wren_a(~n_cs_vram_wram & vram_wram_sel & ~n_vram_wram_wr),
	.address_a(vram_wram_A),
	.data_a(k501_D),
	.q_a(wram_D),
	
	.clock_b(clk_49m),
	.wren_b(hs_write),
	.address_b(hs_address),
	.data_b(hs_data_in),
	.q_b(hs_data_out)
);
//VRAM
wire [7:0] vram_D;
spram #(8, 11) F10
(
	.clk(clk_49m),
	.we(~n_cs_vram_wram & ~vram_wram_sel & ~n_vram_wram_wr),
	.addr(vram_wram_A),
	.data(k501_D),
	.q(vram_D)
);
//Generate select line and write enable for work RAM/VRAM
wire vram_wram_sel = z80_A[11] & ~h_cnt[1];
wire n_vram_wram_wr = n_cs_vram_wram | n_ram_write;

//Main latch
reg nmi_mask = 0;
reg flip = 0;
reg cs_soundirq = 0;
reg pixel_en = 0;
always_ff @(posedge clk_49m) begin
	if(!reset) begin
		nmi_mask <= 0;
		flip <= 0;
		cs_soundirq <= 0;
	end
	else if(cen_3m) begin
		if(cs_mainlatch)
			case(z80_A[3:1])
				3'b000: nmi_mask <= k501_D[0];
				3'b001: flip <= k501_D[0];
				3'b010: cs_soundirq <= k501_D[0];
				3'b100: pixel_en <= k501_D[0];
				default:;
		endcase
	end
end

//Generate VBlank NMI for Z80
reg n_nmi = 1;
always_ff @(posedge clk_49m) begin
	if(cen_6m) begin
		if(!nmi_mask)
			n_nmi <= 1;
		else if(vblank_irq_en)
			n_nmi <= 0;
	end
end

//-------------------------------------------------------- Video timing --------------------------------------------------------//

//Konami 082 custom chip - responsible for all video timings
wire vblk, vblank_irq_en, h256;
wire [8:0] h_cnt;
wire [7:0] v_cnt;
k082 F5
(
	.reset(1),
	.clk(clk_49m),
	.cen(cen_6m),
	.h_center(h_center),
	.v_center(v_center),
	.n_vsync(video_vsync),
	.sync(video_csync),
	.n_hsync(video_hsync),
	.vblk(vblk),
	.vblk_irq_en(vblank_irq_en),
	.h1(h_cnt[0]),
	.h2(h_cnt[1]),
	.h4(h_cnt[2]),
	.h8(h_cnt[3]),
	.h16(h_cnt[4]),
	.h32(h_cnt[5]),
	.h64(h_cnt[6]),
	.h128(h_cnt[7]),
	.n_h256(h_cnt[8]),
	.h256(h256),
	.v1(v_cnt[0]),
	.v2(v_cnt[1]),
	.v4(v_cnt[2]),
	.v8(v_cnt[3]),
	.v16(v_cnt[4]),
	.v32(v_cnt[5]),
	.v64(v_cnt[6]),
	.v128(v_cnt[7])
);

//Time Pilot has an additional 82S153 PLA labelled K528 that controls the vertical counter latch and is used to control the state of
//the Konami 082's vertical counter (active or high impedance as the vertical counter is directly connected to the Z80's data bus on
//the PCB) - instantiate an instance of this IC here
wire vcntlatch, vcntlatch_clr;
k528 E10
(
	.HCNT(h_cnt[6:0]),
	.H256(h256),
	.RESET0(reset),
	.RESET1(reset),
	.NVEN(~cs_beam),
	.PEN(pixel_en),
	.CLR(vcntlatch_clr),
	.CLKO(vcntlatch)
);

//Latch vertical counter bits from 082 custom chip
reg [7:0] vcnt_lat = 8'd0;
reg old_vcntlatch;
always_ff @(posedge clk_49m) begin
	old_vcntlatch <= vcntlatch;
	if(!vcntlatch_clr)
		vcnt_lat <= 8'd0;
	else if(!old_vcntlatch && vcntlatch)
		vcnt_lat <= v_cnt;
end

//XOR horizontal counter bits [7:2] with the inverse of the flip flag
wire [7:2] hcnt_x = h_cnt[7:2] ^ {6{~flip}};

//XOR latched vertical counter bits with the inverse of the flip flag
wire [7:0] vcnt_x = vcnt_lat ^ {8{~flip}};

//--------------------------------------------------------- Tile layer ---------------------------------------------------------//

//Generate addresses for VRAM
wire [10:0] vram_wram_A = h_cnt[1] ? {h_cnt[2], vcnt_x[7:3], hcnt_x[7:3]} : z80_A[10:0];

//LDO, labelled D1 in the Time Pilot schematics, signals to the tilemap logic when to latch tilemap codes from VRAM.  It pulses
//low when the lower 3 bits of the horizontal counter are all 1, then on the rising edge, tilemap codes are latched.
//Set LDO as a register and latch a 0 when the 3 least significant bits of the horizontal counter are set to 1, otherwise latch
//a 1
reg ldo = 1;
always_ff @(posedge clk_49m) begin
	if(h_cnt[2:0] == 3'b111)
		ldo <= 0;
	else
		ldo <= 1;
end

//Latch tilemap code from VRAM at every rising edge of LDO
reg [7:0] tile_code = 8'd0;
always_ff @(posedge clk_49m) begin
	if(!ldo && h_cnt[2:0] == 3'b000)
		tile_code <= vram_D;
end

//Latch tilemap attributes from VRAM at the rising edge of bit 2 of the horizontal counter when H256 is low
reg tile_attrib_latch = 1;
always_ff @(posedge clk_49m) begin
	if(h_cnt[2:0] == 3'b011)
		tile_attrib_latch <= 0;
	else
		tile_attrib_latch <= 1;
end
reg [7:0] tile_attrib = 8'd0;
always_ff @(posedge clk_49m) begin
	if(!h256 && !tile_attrib_latch && h_cnt[2:0] == 3'b100)
		tile_attrib <= vram_D;
end

//Latch tile color information, tilemap enable and flip signal for tilemap 083 custom chip every 8 pixels
wire tile_flip = tile_hflip ^ flip;
reg tile_083_flip = 0;
reg tilemap_en = 0;
reg [3:0] tile_color = 4'd0;
always_ff @(posedge clk_49m) begin
	if(cen_6m) begin
		if(h_cnt[2:0] == 3'b011) begin
			tile_083_flip <= tile_flip;
			tile_color <= tile_attrib[3:0];
			tilemap_en <= tile_attrib[4];
		end
		else begin
			tile_083_flip <= tile_083_flip;
			tile_color <= tile_color;
			tilemap_en <= tilemap_en;
		end
	end
end

//Generate address lines A1 - A3 of tilemap ROMs, CRA and tile flip attributes on the falling edge of horizontal
//counter bit 2
reg v1l, v2l, v4l, cra, tile_hflip, tile_vflip;
reg old_h4;
always_ff @(posedge clk_49m) begin
	old_h4 <= h_cnt[2];
	if(old_h4 && !h_cnt[2]) begin
		v1l <= vcnt_x[0];
		v2l <= vcnt_x[1];
		v4l <= vcnt_x[2];
		tile_hflip <= tile_attrib[6];
		tile_vflip <= tile_attrib[7];
		cra <= tile_attrib[5];
	end
end

//Address tilemap ROM
assign tilerom_A[12] = cra;
assign tilerom_A[11:4] = tile_code[7:0];
assign tilerom_A[3:0] = {hcnt_x[2] ^ tile_hflip, v4l ^ tile_vflip, v2l ^ tile_vflip, v1l ^ tile_vflip};

//Tilemap ROM
wire [12:0] tilerom_A;
wire [7:0] eprom4_D;
eprom_4 F11
(
	.ADDR(tilerom_A),
	.CLK(clk_49m),
	.DATA(eprom4_D),
	.ADDR_DL(ioctl_addr),
	.CLK_DL(clk_49m),
	.DATA_IN(ioctl_data),
	.CS_DL(ep4_cs_i),
	.WR(ioctl_wr)
);

//Konami 083 custom chip 1/2 - this one shifts the pixel data from tilemap ROMs
k083 F12
(
	.CK(clk_49m),
	.CEN(cen_6m),
	.LOAD(h_cnt[1:0] == 2'b11),
	.FLIP(tile_083_flip),
	.DB0i(eprom4_D),
	.DSH0(tile_lut_A[1:0])
);

//Tilemap lookup PROM
wire [7:0] tile_lut_A;
assign tile_lut_A[7] = 0;
assign tile_lut_A[6] = tilemap_en;
assign tile_lut_A[5:2] = tile_color;
wire [3:0] tile_D;
tile_lut_prom E12
(
	.ADDR(tile_lut_A),
	.CLK(clk_49m),
	.DATA(tile_D),
	.ADDR_DL(ioctl_addr),
	.CLK_DL(clk_49m),
	.DATA_IN(ioctl_data),
	.CS_DL(tl_cs_i),
	.WR(ioctl_wr)
);

//-------------------------------------------------------- Sprite layer --------------------------------------------------------//

//Generate write enables for sprite RAM (active low)
wire n_spriteram0_wr = n_cs_spriteram0 | n_ram_write;
wire n_spriteram1_wr = n_cs_spriteram1 | n_ram_write;

//Sprite RAM
wire [15:0] spriteram_D;
wire [7:0] spriteram_A = h_cnt[1] ? {2'b00, h_cnt[7], (h_cnt[8] ^ h_cnt[7]), h_cnt[6:4], h_cnt[2]} : z80_A[7:0];
//Bank 0 (lower 4 bits)
spram #(4, 8) D7
(
	.clk(clk_49m),
	.we(~n_cs_spriteram0 & ~n_spriteram0_wr),
	.addr(spriteram_A),
	.data(k501_D[3:0]),
	.q(spriteram_D[3:0])
);
//Bank 0 (upper 4 bits)
spram #(4, 8) D6
(
	.clk(clk_49m),
	.we(~n_cs_spriteram0 & ~n_spriteram0_wr),
	.addr(spriteram_A),
	.data(k501_D[7:4]),
	.q(spriteram_D[7:4])
);
//Bank 1 (lower 4 bits)
spram #(4, 8) D9
(
	.clk(clk_49m),
	.we(~n_cs_spriteram1 & ~n_spriteram1_wr),
	.addr(spriteram_A),
	.data(k501_D[3:0]),
	.q(spriteram_D[11:8])
);
//Bank 1 (upper 4 bits)
spram #(4, 8) D8
(
	.clk(clk_49m),
	.we(~n_cs_spriteram1 & ~n_spriteram1_wr),
	.addr(spriteram_A),
	.data(k501_D[7:4]),
	.q(spriteram_D[15:12])
);

//Konami 503 custom chip - generates sprite addresses for lower half of sprite ROMs, sprite line buffer control, enable for
//sprite write and sprite flip for 083 custom chip.
wire cs_linebuffer, sprite_flip;
k503 F8
(
	.CLK(clk_49m),
	.OB(spriteram_D[7:0]),
	.VCNT(vcnt_lat),
	.H4(h_cnt[2]),
	.H8(h_cnt[3]),
	.LD(h_cnt[1:0] != 2'b11),
	.OCS(cs_linebuffer),
	.OFLP(sprite_flip),
	.R(spriterom_A[5:0])
);

//Latch sprite code from sprite RAM bank 1 every 16 pixels
reg [7:0] sprite_code = 8'd0;
always_ff @(posedge clk_49m) begin
	if(cen_6m) begin
		if(h_cnt[3:0] == 4'b0111)
			sprite_code <= spriteram_D[15:8];
		else
			sprite_code <= sprite_code;
	end
end

//Assign sprite code to address the upper 7 bits of the sprite ROMs
assign spriterom_A[12:6] = sprite_code[6:0];

//Sprite ROMs
wire [12:0] spriterom_A;
//ROM 1/2
wire [7:0] eprom5_D;
eprom_5 C10
(
	.ADDR(spriterom_A),
	.CLK(clk_49m),
	.DATA(eprom5_D),
	.ADDR_DL(ioctl_addr),
	.CLK_DL(clk_49m),
	.DATA_IN(ioctl_data),
	.CS_DL(ep5_cs_i),
	.WR(ioctl_wr)
);
//ROM 2/2
wire [7:0] eprom6_D;
eprom_6 C11
(
	.ADDR(spriterom_A),
	.CLK(clk_49m),
	.DATA(eprom6_D),
	.ADDR_DL(ioctl_addr),
	.CLK_DL(clk_49m),
	.DATA_IN(ioctl_data),
	.CS_DL(ep6_cs_i),
	.WR(ioctl_wr)
);

//Multiplex sprite ROM data outputs based on the state of the most significant bit of the sprite code
wire spriterom_sel = sprite_code[7];
wire [7:0] spriterom_D = spriterom_sel ? eprom6_D : eprom5_D;

//Konami 083 custom chip 2/2 - shifts the pixel data from sprite ROMs
k083 C12
(
	.CK(clk_49m),
	.CEN(cen_6m),
	.LOAD(h_cnt[1:0] == 2'b11),
	.FLIP(sprite_k083_flip),
	.DB0i(spriterom_D),
	.DSH0(sprite_lut_A[1:0])
);

//Latch sprite color information, enable for sprite line buffer, sprite 083 flip at every 12 pixels
reg [5:0] sprite_color = 6'd0;
reg sprite_lbuff_en, sprite_k083_flip;
always_ff @(posedge clk_49m) begin
	if(cen_6m) begin
		if(h_cnt[3:0] == 4'b1011) begin
			sprite_color <= spriteram_D[5:0];
			sprite_lbuff_en <= cs_linebuffer;
			sprite_k083_flip <= sprite_flip;
		end
	end
end

//Assign sprite color information to bits [7:2] of the sprite lookup PROM
assign sprite_lut_A[7:2] = sprite_color;

//Sprite lookup PROM
wire [7:0] sprite_lut_A;
wire [3:0] sprite_lut_D;
sprite_lut_prom E9
(
	.ADDR(sprite_lut_A),
	.CLK(clk_49m),
	.DATA(sprite_lut_D),
	.ADDR_DL(ioctl_addr),
	.CLK_DL(clk_49m),
	.DATA_IN(ioctl_data),
	.CS_DL(sl_cs_i),
	.WR(ioctl_wr)
);

//Konami 502 custom chip, responsible for generating sprites (sits between sprite ROMs and the sprite line buffer)
wire [7:0] sprite_lbuff_Do;
wire [4:0] sprite_D;
wire sprite_lbuff_sel, sprite_lbuff_dec0, sprite_lbuff_dec1;
k502 C8
(
	.RESET(1),
	.CK1(clk_49m),
	.CK2(clk_49m),
	.CEN(cen_6m),
	.LDO(h_cnt[2:0] != 3'b111),
	.H2(h_cnt[1]),
	.H256(h_cnt[8]),
	.SPAL(sprite_lut_D),
	.SPLBi({sprite_lbuff1_D, sprite_lbuff0_D}),
	.SPLBo(sprite_lbuff_Do),
	.OSEL(sprite_lbuff_sel),
	.OLD(sprite_lbuff_dec1),
	.OCLR(sprite_lbuff_dec0),
	.COL(sprite_D)
);

//----------------------------------------------------- Sprite line buffer -----------------------------------------------------//

//Generate load and clear signals for counters generating addresses to sprite line buffer
reg sprite_lbuff0_ld, sprite_lbuff1_ld, sprite_lbuff0_clr, sprite_lbuff1_clr;
always_ff @(posedge clk_49m) begin
	if(h_cnt[1:0] == 2'b11) begin
		if(sprite_lbuff_dec0 && !sprite_lbuff_dec1) begin
			sprite_lbuff0_clr <= 0;
			sprite_lbuff1_clr <= 1;
		end
		else if(!sprite_lbuff_dec0 && sprite_lbuff_dec1) begin
			sprite_lbuff0_clr <= 1;
			sprite_lbuff1_clr <= 0;
		end
		else begin
			sprite_lbuff0_clr <= 0;
			sprite_lbuff1_clr <= 0;
		end
	end
	else begin
		sprite_lbuff0_clr <= 0;
		sprite_lbuff1_clr <= 0;
	end
	if(h_cnt[3:0] == 4'b1011) begin
		if(!sprite_lbuff_dec1) begin
			sprite_lbuff0_ld <= 1;
			sprite_lbuff1_ld <= 0;
		end
		else begin
			sprite_lbuff0_ld <= 0;
			sprite_lbuff1_ld <= 1;
		end
	end
	else begin
		sprite_lbuff0_ld <= 0;
		sprite_lbuff1_ld <= 0;
	end
end

//Generate addresses for sprite line buffer
//Bank 0, lower 4 bits
reg [3:0] linebuffer0_l = 4'd0;
always_ff @(posedge clk_49m) begin
	if(cen_6m) begin
		if(sprite_lbuff0_clr)
			linebuffer0_l <= 4'd0;
		else
			if(sprite_lbuff0_ld)
				linebuffer0_l <= spriteram_D[11:8];
			else
				linebuffer0_l <= linebuffer0_l + 4'd1;
	end
end
//Bank 0, upper 4 bits
reg [3:0] linebuffer0_h = 4'd0;
always_ff @(posedge clk_49m) begin
	if(cen_6m) begin
		if(sprite_lbuff0_clr)
			linebuffer0_h <= 4'd0;
		else
			if(sprite_lbuff0_ld)
				linebuffer0_h <= spriteram_D[15:12];
			else if(linebuffer0_l == 4'hF)
				linebuffer0_h <= linebuffer0_h + 4'd1;
	end
end
wire [7:0] sprite_lbuff0_A = {linebuffer0_h, linebuffer0_l};
//Bank 1, lower 4 bits
reg [3:0] linebuffer1_l = 4'd0;
always_ff @(posedge clk_49m) begin
	if(cen_6m) begin
		if(sprite_lbuff1_clr)
			linebuffer1_l <= 4'd0;
		else
			if(sprite_lbuff1_ld)
				linebuffer1_l <= spriteram_D[11:8];
			else
				linebuffer1_l <= linebuffer1_l + 4'd1;
	end
end
//Bank 1, upper 4 bits
reg [3:0] linebuffer1_h = 4'd0;
always_ff @(posedge clk_49m) begin
	if(cen_6m) begin
		if(sprite_lbuff1_clr)
			linebuffer1_h <= 4'd0;
		else
			if(sprite_lbuff1_ld)
				linebuffer1_h <= spriteram_D[15:12];
			else if(linebuffer1_l == 4'hF)
				linebuffer1_h <= linebuffer1_h + 4'd1;
	end
end
wire [7:0] sprite_lbuff1_A = {linebuffer1_h, linebuffer1_l};

//Generate chip select signals for sprite line buffer
wire cs_sprite_lbuff0 = ~(sprite_lbuff_en & sprite_lbuff_sel);
wire cs_sprite_lbuff1 = ~(sprite_lbuff_en & ~sprite_lbuff_sel);

//Sprite line buffer bank 0
wire [3:0] sprite_lbuff0_D;
spram #(4, 8) B7
(
	.clk(clk_49m),
	.we(cen_6m & cs_sprite_lbuff0),
	.addr(sprite_lbuff0_A),
	.data({sprite_lbuff_Do[0], sprite_lbuff_Do[1], sprite_lbuff_Do[2], sprite_lbuff_Do[3]}),
	.q({sprite_lbuff0_D[0], sprite_lbuff0_D[1], sprite_lbuff0_D[2], sprite_lbuff0_D[3]})
);

//Sprite line buffer bank 1
wire [3:0] sprite_lbuff1_D;
spram #(4, 8) C7
(
	.clk(clk_49m),
	.we(cen_6m & cs_sprite_lbuff1),
	.addr(sprite_lbuff1_A),
	.data({sprite_lbuff_Do[4], sprite_lbuff_Do[5], sprite_lbuff_Do[6], sprite_lbuff_Do[7]}),
	.q({sprite_lbuff1_D[0], sprite_lbuff1_D[1], sprite_lbuff1_D[2], sprite_lbuff1_D[3]})
);

//----------------------------------------------------- Final video output -----------------------------------------------------//

//Generate HBlank (active high) while the horizontal counter is between 141 and 268
wire hblk = (h_cnt > 140 && h_cnt < 269);

//Multiplex tile and sprite data
wire tile_sprite_sel = (tilemap_en | sprite_D[4]);
wire [3:0] tile_sprite_D = tile_sprite_sel ? tile_D[3:0] : sprite_D[3:0];

//Latch pixel data for color PROMs
reg [3:0] pixel_D;
always_ff @(posedge clk_49m) begin
	if(cen_6m)
		pixel_D <= tile_sprite_D;
end

//Color PROMs
wire [4:0] color_A = {tile_sprite_sel, pixel_D};
//Red & green (bits 1 and 0)
wire [4:0] prom_red, prom_green;
color_prom_1 B5
(
	.ADDR(color_A),
	.CLK(clk_49m),
	.DATA({prom_green[1:0], prom_red, 1'bZ}),
	.ADDR_DL(ioctl_addr),
	.CLK_DL(clk_49m),
	.DATA_IN(ioctl_data),
	.CS_DL(cp1_cs_i),
	.WR(ioctl_wr)
);
//Blue & green (bits 2 - 4)
wire [4:0] prom_blue;
color_prom_2 B4
(
	.ADDR(color_A),
	.CLK(clk_49m),
	.DATA({prom_blue, prom_green[4:2]}),
	.ADDR_DL(ioctl_addr),
	.CLK_DL(clk_49m),
	.DATA_IN(ioctl_data),
	.CS_DL(cp2_cs_i),
	.WR(ioctl_wr)
);

//Output video signal from color PROMs, otherwise output black if in HBlank or VBlank
assign red = (hblk | vblk) ? 5'h0 : prom_red;
assign green = (hblk | vblk) ? 5'h0 : prom_green;
assign blue = (hblk | vblk) ? 5'h0 : prom_blue;

endmodule
