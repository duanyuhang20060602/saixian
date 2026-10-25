// Ported from water-single a15d24f6bbae56187508928f800aea7c5df8e7af; embedded edge weights.
// Music features are measured from final played PCM. The edge envelope is

// smoothed at frame boundaries and never drives the water-wave scheduler.

module water_edge_before #(parameter EXTERNAL_ENVELOPE=0)(input clk,rst,frame_tick,music_drive,pcm_valid,

 input signed[15:0] pcm_left,pcm_right,input[10:0] x,input[9:0] y,

 input de,sof,eol,input[23:0] rgb,input[5:0] darkness,input[7:0] external_target,

 output reg de_out,sof_out,eol_out,output reg[23:0] rgb_out,output reg[7:0] level);

reg[18:0] envelope;wire signed[16:0] sum=$signed({pcm_left[15],pcm_left})+$signed({pcm_right[15],pcm_right});

wire signed[16:0] mono=sum>>>1;wire[16:0] magnitude=mono<0 ? -mono:mono;

reg[15:0] breathe;

wire[7:0] target=EXTERNAL_ENVELOPE ? external_target:(envelope>8191 ? 8'd255:envelope[12:5]);

always @(posedge clk)begin

 if(rst)begin envelope<=0;breathe<=0;level<=0;end

 else begin

  if(!EXTERNAL_ENVELOPE && pcm_valid)begin

   if(magnitude>envelope)envelope<=envelope+((magnitude-envelope)>>6);

   else envelope<=envelope-((envelope-magnitude)>>10);

  end

  if(frame_tick)begin

   if({target,8'd0}>breathe)breathe<=breathe+(({target,8'd0}-breathe)>>3);

   else breathe<=breathe-((breathe-{target,8'd0})>>4);

   level<=music_drive ? breathe[15:8]:8'd0;

  end

 end

end

wire[10:0] right_dist=x<1280 ? 11'd1279-x:11'd0;

wire[9:0] bottom_dist=y<720 ? 10'd719-y:10'd0;

wire[10:0] xd=x<right_dist ? x:right_dist;

wire[10:0] yd={1'b0,y}<bottom_dist ? {1'b0,y}:{1'b0,bottom_dist};

wire[10:0] distance=xd<yd ? xd:yd;

// The weight is zero away from the 76-pixel border. Clip each axis before
// taking the minimum: only seven bits are relevant to the ROM, avoiding the
// wide subtract/compare chain on the synchronous RAM address setup path.
// Screen-outside coordinates retain the original zero-distance behavior.
wire[6:0] border_x=x<76 ? x[6:0]:x>=1280 ? 7'd0:x>=1204 ? 7'd127-x[6:0]:7'd127;
wire[6:0] border_y=y<76 ? y[6:0]:y>=720 ? 7'd0:y>=644 ? 7'd79-y[6:0]:7'd127;
wire[6:0] border_address=border_x<border_y ? border_x:border_y;

// Use the original synchronous LUT model for legacy simulator-only builds.
// Production uses a native eRAM read in the same single-clock stage.
`ifdef WATER_SIM
reg[7:0] edge_rom[0:127];initial begin
 edge_rom[0]=8'h60;
 edge_rom[1]=8'h5d;
 edge_rom[2]=8'h5b;
 edge_rom[3]=8'h58;
 edge_rom[4]=8'h55;
 edge_rom[5]=8'h53;
 edge_rom[6]=8'h50;
 edge_rom[7]=8'h4e;
 edge_rom[8]=8'h4b;
 edge_rom[9]=8'h49;
 edge_rom[10]=8'h46;
 edge_rom[11]=8'h44;
 edge_rom[12]=8'h42;
 edge_rom[13]=8'h40;
 edge_rom[14]=8'h3d;
 edge_rom[15]=8'h3b;
 edge_rom[16]=8'h39;
 edge_rom[17]=8'h37;
 edge_rom[18]=8'h35;
 edge_rom[19]=8'h33;
 edge_rom[20]=8'h31;
 edge_rom[21]=8'h2f;
 edge_rom[22]=8'h2d;
 edge_rom[23]=8'h2b;
 edge_rom[24]=8'h2a;
 edge_rom[25]=8'h28;
 edge_rom[26]=8'h26;
 edge_rom[27]=8'h25;
 edge_rom[28]=8'h23;
 edge_rom[29]=8'h21;
 edge_rom[30]=8'h20;
 edge_rom[31]=8'h1e;
 edge_rom[32]=8'h1d;
 edge_rom[33]=8'h1b;
 edge_rom[34]=8'h1a;
 edge_rom[35]=8'h19;
 edge_rom[36]=8'h17;
 edge_rom[37]=8'h16;
 edge_rom[38]=8'h15;
 edge_rom[39]=8'h14;
 edge_rom[40]=8'h13;
 edge_rom[41]=8'h11;
 edge_rom[42]=8'h10;
 edge_rom[43]=8'h0f;
 edge_rom[44]=8'h0e;
 edge_rom[45]=8'h0d;
 edge_rom[46]=8'h0c;
 edge_rom[47]=8'h0c;
 edge_rom[48]=8'h0b;
 edge_rom[49]=8'h0a;
 edge_rom[50]=8'h09;
 edge_rom[51]=8'h08;
 edge_rom[52]=8'h08;
 edge_rom[53]=8'h07;
 edge_rom[54]=8'h06;
 edge_rom[55]=8'h06;
 edge_rom[56]=8'h05;
 edge_rom[57]=8'h05;
 edge_rom[58]=8'h04;
 edge_rom[59]=8'h04;
 edge_rom[60]=8'h03;
 edge_rom[61]=8'h03;
 edge_rom[62]=8'h02;
 edge_rom[63]=8'h02;
 edge_rom[64]=8'h02;
 edge_rom[65]=8'h01;
 edge_rom[66]=8'h01;
 edge_rom[67]=8'h01;
 edge_rom[68]=8'h01;
 edge_rom[69]=8'h01;
 edge_rom[70]=8'h00;
 edge_rom[71]=8'h00;
 edge_rom[72]=8'h00;
 edge_rom[73]=8'h00;
 edge_rom[74]=8'h00;
 edge_rom[75]=8'h00;
 edge_rom[76]=8'h00;
 edge_rom[77]=8'h00;
 edge_rom[78]=8'h00;
 edge_rom[79]=8'h00;
 edge_rom[80]=8'h00;
 edge_rom[81]=8'h00;
 edge_rom[82]=8'h00;
 edge_rom[83]=8'h00;
 edge_rom[84]=8'h00;
 edge_rom[85]=8'h00;
 edge_rom[86]=8'h00;
 edge_rom[87]=8'h00;
 edge_rom[88]=8'h00;
 edge_rom[89]=8'h00;
 edge_rom[90]=8'h00;
 edge_rom[91]=8'h00;
 edge_rom[92]=8'h00;
 edge_rom[93]=8'h00;
 edge_rom[94]=8'h00;
 edge_rom[95]=8'h00;
 edge_rom[96]=8'h00;
 edge_rom[97]=8'h00;
 edge_rom[98]=8'h00;
 edge_rom[99]=8'h00;
 edge_rom[100]=8'h00;
 edge_rom[101]=8'h00;
 edge_rom[102]=8'h00;
 edge_rom[103]=8'h00;
 edge_rom[104]=8'h00;
 edge_rom[105]=8'h00;
 edge_rom[106]=8'h00;
 edge_rom[107]=8'h00;
 edge_rom[108]=8'h00;
 edge_rom[109]=8'h00;
 edge_rom[110]=8'h00;
 edge_rom[111]=8'h00;
 edge_rom[112]=8'h00;
 edge_rom[113]=8'h00;
 edge_rom[114]=8'h00;
 edge_rom[115]=8'h00;
 edge_rom[116]=8'h00;
 edge_rom[117]=8'h00;
 edge_rom[118]=8'h00;
 edge_rom[119]=8'h00;
 edge_rom[120]=8'h00;
 edge_rom[121]=8'h00;
 edge_rom[122]=8'h00;
 edge_rom[123]=8'h00;
 edge_rom[124]=8'h00;
 edge_rom[125]=8'h00;
 edge_rom[126]=8'h00;
 edge_rom[127]=8'h00;
end
reg [7:0] weight;
always @(posedge clk)weight<=distance<76 ? edge_rom[distance[6:0]]:8'd0;
`else
wire [7:0] rom_weight;
reg inside_edge;
wire [7:0] weight=inside_edge ? rom_weight:8'd0;
EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.ADDR_WIDTH_A(7),.DATA_DEPTH_A(128),
 .DATA_WIDTH_B(8),.ADDR_WIDTH_B(7),.DATA_DEPTH_B(128),.BYTE_ENABLE(0),
 .MODE("SP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.INIT_FILE("../../src/board_a/user_source/hdl_source/IP/water_edge_weights.mif"),.IMPLEMENT("9K")) weights(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(1'b0),.ocea(1'b1),.bea(1'b0),.addra(border_address),.dia(8'd0),.doa(rom_weight),
 .clkb(1'b0),.rstb(1'b0),.ceb(1'b0),.web(1'b0),.oceb(1'b0),.beb(1'b0),.addrb(7'd0),.dib(8'd0),.dob());
`endif

reg[23:0] rgb0,rgb1,rgb2;reg[5:0] dark0,dark1,dark2;

reg[15:0] energy;reg[3:0] dq,sq,lq;reg[8:0] red,green,blue;

// Suppress the overlay immediately on scene entry, including the first
// award/result frame; the held envelope still updates only in blanking.
wire[7:0] amount=music_drive ? energy[15:8]:8'd0;

// Bounded 0..48-level blue/cyan edge light, added after source sampling.

wire[8:0] add_r={1'b0,rgb1[23:16]}+({1'b0,amount}>>3);

wire[8:0] add_g={1'b0,rgb1[15:8]}+({1'b0,amount}>>2);

wire[8:0] add_b={1'b0,rgb1[7:0]}+({1'b0,amount}>>1);

reg[15:0] pr,pg,pb;

function[15:0] dark_channel;input[7:0] c;input[5:0] d;reg[15:0] loss;

 begin

 loss=c*d;

 dark_channel={3'd0,c,5'd0}-loss;

 end

endfunction

function signed[15:0] edge_product;input signed[8:0] aa;input[7:0] b;
 begin edge_product=aa*$signed({1'b0,b});end
endfunction

always @(posedge clk)begin

 // Exact distance<76 predicate for every 11-bit x / 10-bit y,
 // including the original zero-distance clamp outside 1280x720.
 inside_edge<=(x<11'd76 || x>=11'd1204 || y<10'd76 || y>=10'd644);rgb0<=rgb;dark0<=darkness;

 energy<=edge_product($signed({1'b0,weight}),level);rgb1<=rgb0;dark1<=dark0;

 rgb2<={add_r[8]?8'hff:add_r[7:0],add_g[8]?8'hff:add_g[7:0],add_b[8]?8'hff:add_b[7:0]};dark2<=dark1;

 // Fade-to-black applies to the whole composited picture, including edge light.

 pr<=dark_channel(rgb2[23:16],dark2);pg<=dark_channel(rgb2[15:8],dark2);pb<=dark_channel(rgb2[7:0],dark2);

 rgb_out<={pr[12:5],pg[12:5],pb[12:5]};

 dq<={dq[2:0],de};sq<={sq[2:0],sof};lq<={lq[2:0],eol};

 de_out<=dq[3];sof_out<=sq[3];eol_out<=lq[3];

 if(rst)begin dq<=0;sq<=0;lq<=0;de_out<=0;sof_out<=0;eol_out<=0;rgb_out<=0;end

end

endmodule

