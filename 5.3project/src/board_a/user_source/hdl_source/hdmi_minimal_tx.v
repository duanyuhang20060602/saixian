`timescale 1ns/1ps
// Minimal RGB HDMI source. Format/ecc tables cross-checked against
// hdl-util/hdmi (Sameer Puri), packet_assembler and tmds_channel.
// See README for references. No audio, pixel repetition or deep colour.
module hdmi_minimal_tx #(
 parameter integer H_ACTIVE=1280,H_FRONT=110,H_SYNC=40,H_BACK=220,
 parameter integer V_ACTIVE=720,V_FRONT=5,V_SYNC=5,V_BACK=20,
 parameter integer VIC=4, EXTERNAL_VIDEO=0, VIDEO_DELAY=2
)(input wire clk,input wire rst,input wire [23:0] rgb_in,
 output wire [9:0] blue,green,red,
 output wire hs,vs,de,frame_start,
 output wire [11:0] x,output wire [10:0] y);
 localparam integer HT=H_ACTIVE+H_FRONT+H_SYNC+H_BACK;
 localparam integer VT=V_ACTIVE+V_FRONT+V_SYNC+V_BACK;
 reg [11:0] h;
 reg [10:0] v;
 always @(posedge clk or posedge rst) begin
  // Start in vertical blanking: send AVI and guards before first active line.
  if(rst) begin h<=0;v<=V_ACTIVE;end
  else if(h==HT-1) begin h<=0;if(v==VT-1) v<=0;else v<=v+1'b1;end
  else h<=h+1'b1;
 end
 assign x=h;assign y=v;
 assign hs=(h>=H_ACTIVE+H_FRONT && h<H_ACTIVE+H_FRONT+H_SYNC);
 assign vs=(v>=V_ACTIVE+V_FRONT && v<V_ACTIVE+V_FRONT+V_SYNC);
 assign de=(h<H_ACTIVE && v<V_ACTIVE) && !rst;
 assign frame_start=(h==0 && v==0) && !rst;
 // AVI PB1 RGB + active-format present, PB2 16:9/same active aspect,
 // PB3 explicitly limited RGB, PB4 VIC, PB5 zero pixel repetition.
 localparam [23:0] HEADER=24'h0d0282;
 localparam [7:0] CHECKSUM=-(8'h82+8'h02+8'h0d+8'h10+8'h28+8'h04+VIC);
 localparam [7:0] VIC_BYTE=VIC;
 // Seven payload bytes, PB0 through PB6. All later payload bytes are zero.
 localparam [55:0] PAYLOAD0={8'h00,8'h00,VIC_BYTE,8'h04,8'h28,8'h10,CHECKSUM};
 function [7:0] ecc56;
  input [55:0] bits;
  reg [7:0] parity;
  integer k;
  begin parity=0;for(k=0;k<56;k=k+1)
   parity=(parity>>1)^((parity[0]^bits[k]) ? 8'h83 : 8'h00);
   ecc56=parity;
  end
 endfunction
 function [7:0] ecc24;
  input [23:0] bits;
  reg [7:0] parity;
  integer k;
  begin parity=0;for(k=0;k<24;k=k+1)
   parity=(parity>>1)^((parity[0]^bits[k]) ? 8'h83 : 8'h00);
   ecc24=parity;
  end
 endfunction
 localparam [63:0] BLOCK0={ecc56(PAYLOAD0),PAYLOAD0};
 localparam [63:0] BLOCK1=64'd0,BLOCK2=64'd0,BLOCK3=64'd0;
 localparam [31:0] HEADER_BLOCK={ecc24(HEADER),HEADER};
 wire packet_line=(v==V_ACTIVE);
 wire island_pre=packet_line && h>=H_ACTIVE+4 && h<H_ACTIVE+12;
 wire island_guard=packet_line && ((h>=H_ACTIVE+12 && h<H_ACTIVE+14) ||
                                  (h>=H_ACTIVE+46 && h<H_ACTIVE+48));
 wire island=packet_line && h>=H_ACTIVE+14 && h<H_ACTIVE+46;
 wire next_line_active=(v<V_ACTIVE-1 || v==VT-1);
 wire video_pre=next_line_active && h>=HT-10 && h<HT-2;
 wire video_guard=next_line_active && h>=HT-2;
 wire [4:0] packet_index=h-(H_ACTIVE+14);
 wire [5:0] even_index={packet_index,1'b0};
 wire [5:0] odd_index={packet_index,1'b1};
 // Channel 0 bit 3 marks the first pixel of a LINE, not a packet.
 // This island is entirely at nonzero h, so bit 3 stays 1 for all 32 words.
 wire [3:0] nibble0={(h!=0),HEADER_BLOCK[packet_index],vs,hs};
 wire [3:0] nibble1={BLOCK3[even_index],BLOCK2[even_index],BLOCK1[even_index],BLOCK0[even_index]};
 wire [3:0] nibble2={BLOCK3[odd_index],BLOCK2[odd_index],BLOCK1[odd_index],BLOCK0[odd_index]};
 wire [2:0] mode=de ? 3'd1 : video_guard ? 3'd2 : island ? 3'd3 : island_guard ? 3'd4 : 3'd0;
 wire [1:0] ctl1={1'b0,(video_pre || island_pre)};
 wire [1:0] ctl2={1'b0,island_pre};
 reg [23:0] rgb;
 always @* begin
  if(h<H_ACTIVE/8) rgb=24'hebebeb;
  else if(h<H_ACTIVE*2/8) rgb=24'hebeb10;
  else if(h<H_ACTIVE*3/8) rgb=24'h10ebeb;
  else if(h<H_ACTIVE*4/8) rgb=24'h10eb10;
  else if(h<H_ACTIVE*5/8) rgb=24'heb10eb;
  else if(h<H_ACTIVE*6/8) rgb=24'heb1010;
  else if(h<H_ACTIVE*7/8) rgb=24'h1010eb;
  else rgb=24'h101010;
  if(h<8 || h>=H_ACTIVE-8 || v<8 || v>=V_ACTIVE-8) rgb=24'h202020;
 end
reg [2:0] mode_pipe [0:VIDEO_DELAY-1];
 reg [1:0] c0_pipe[0:VIDEO_DELAY-1],c1_pipe[0:VIDEO_DELAY-1],c2_pipe[0:VIDEO_DELAY-1];
 reg [3:0] n0_pipe[0:VIDEO_DELAY-1],n1_pipe[0:VIDEO_DELAY-1],n2_pipe[0:VIDEO_DELAY-1];
 integer di;
 always @(posedge clk or posedge rst)begin
  if(rst)begin for(di=0;di<VIDEO_DELAY;di=di+1)begin mode_pipe[di]<=0;c0_pipe[di]<=0;c1_pipe[di]<=0;c2_pipe[di]<=0;n0_pipe[di]<=0;n1_pipe[di]<=0;n2_pipe[di]<=0;end end
  else begin
   mode_pipe[0]<=mode;c0_pipe[0]<={vs,hs};c1_pipe[0]<=ctl1;c2_pipe[0]<=ctl2;
   n0_pipe[0]<=nibble0;n1_pipe[0]<=nibble1;n2_pipe[0]<=nibble2;
   for(di=1;di<VIDEO_DELAY;di=di+1)begin
    mode_pipe[di]<=mode_pipe[di-1];c0_pipe[di]<=c0_pipe[di-1];c1_pipe[di]<=c1_pipe[di-1];c2_pipe[di]<=c2_pipe[di-1];
    n0_pipe[di]<=n0_pipe[di-1];n1_pipe[di]<=n1_pipe[di-1];n2_pipe[di]<=n2_pipe[di-1];
   end
  end
 end
 wire [2:0] mode2=mode_pipe[VIDEO_DELAY-1];
 wire [1:0] ctl02=c0_pipe[VIDEO_DELAY-1],ctl12=c1_pipe[VIDEO_DELAY-1],ctl22=c2_pipe[VIDEO_DELAY-1];
 wire [3:0] ni02=n0_pipe[VIDEO_DELAY-1],ni12=n1_pipe[VIDEO_DELAY-1],ni22=n2_pipe[VIDEO_DELAY-1];
 wire [2:0] send_mode=EXTERNAL_VIDEO ? mode2 : mode;
 wire [23:0] send_rgb=EXTERNAL_VIDEO ? rgb_in : rgb;
 hdmi_minimal_channel #(.CHANNEL(0)) ch0(.clk(clk),.rst(rst),.mode(send_mode),.rgb(send_rgb[7:0]),.control(EXTERNAL_VIDEO ? ctl02 : {vs,hs}),.island_data(EXTERNAL_VIDEO ? ni02 : nibble0),.symbol(blue));
 hdmi_minimal_channel #(.CHANNEL(1)) ch1(.clk(clk),.rst(rst),.mode(send_mode),.rgb(send_rgb[15:8]),.control(EXTERNAL_VIDEO ? ctl12 : ctl1),.island_data(EXTERNAL_VIDEO ? ni12 : nibble1),.symbol(green));
 hdmi_minimal_channel #(.CHANNEL(2)) ch2(.clk(clk),.rst(rst),.mode(send_mode),.rgb(send_rgb[23:16]),.control(EXTERNAL_VIDEO ? ctl22 : ctl2),.island_data(EXTERNAL_VIDEO ? ni22 : nibble2),.symbol(red));
endmodule

module hdmi_minimal_channel #(parameter integer CHANNEL=0)(
 input wire clk,input wire rst,input wire [2:0] mode,
 input wire [7:0] rgb,input wire [1:0] control,input wire [3:0] island_data,
 output reg [9:0] symbol);
 reg [8:0] qm_comb,qm;
 reg [2:0] mode_d;
 reg [1:0] ctl_d;
 reg [3:0] island_d;
 integer i,j,ones_data,ones_qm;
 reg use_xnor;
 reg signed [5:0] disparity,balance;
 function [9:0] ctrl;
  input [1:0] bits;
  begin case(bits)
   0:ctrl=10'b1101010100;1:ctrl=10'b0010101011;
   2:ctrl=10'b0101010100;3:ctrl=10'b1010101011;
  endcase end
 endfunction
 function [9:0] terc;
  input [3:0] bits;
  begin case(bits)
   0:terc=10'b1010011100;1:terc=10'b1001100011;
   2:terc=10'b1011100100;3:terc=10'b1011100010;
   4:terc=10'b0101110001;5:terc=10'b0100011110;
   6:terc=10'b0110001110;7:terc=10'b0100111100;
   8:terc=10'b1011001100;9:terc=10'b0100111001;
   10:terc=10'b0110011100;11:terc=10'b1011000110;
   12:terc=10'b1010001110;13:terc=10'b1001110001;
   14:terc=10'b0101100011;15:terc=10'b1011000011;
  endcase end
 endfunction
 always @* begin
  ones_data=0;for(i=0;i<8;i=i+1) ones_data=ones_data+rgb[i];
  use_xnor=(ones_data>4 || (ones_data==4 && rgb[0]==0));
  qm_comb[0]=rgb[0];
  for(i=1;i<8;i=i+1) qm_comb[i]=use_xnor ? ~(qm_comb[i-1]^rgb[i]) : (qm_comb[i-1]^rgb[i]);
  qm_comb[8]=!use_xnor;
  ones_qm=0;for(j=0;j<8;j=j+1) ones_qm=ones_qm+qm[j];
  balance=2*ones_qm-8;
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin qm<=0;mode_d<=0;ctl_d<=0;island_d<=0;end
  else begin qm<=qm_comb;mode_d<=mode;ctl_d<=control;island_d<=island_data;end
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin symbol<=10'b1101010100;disparity<=0;end
  else if(mode_d!=1) begin
   disparity<=0;
   case(mode_d)
    0:symbol<=ctrl(ctl_d);
    2:symbol<=(CHANNEL==1) ? 10'b0100110011 : 10'b1011001100;
    3:symbol<=terc(island_d);
    4:symbol<=(CHANNEL==0) ? terc({2'b11,ctl_d}) : 10'b0100110011;
    default:symbol<=ctrl(ctl_d);
   endcase
  end else if(disparity==0 || balance==0) begin
   symbol<={~qm[8],qm[8],(qm[8] ? qm[7:0] : ~qm[7:0])};
   disparity<=disparity+(qm[8] ? balance : -balance);
  end else if((disparity>0 && balance>0) || (disparity<0 && balance<0)) begin
   symbol<={1'b1,qm[8],~qm[7:0]};
   disparity<=disparity+(qm[8] ? 6'sd2 : 6'sd0)-balance;
  end else begin
   symbol<={1'b0,qm[8],qm[7:0]};
   disparity<=disparity+balance-(qm[8] ? 6'sd0 : 6'sd2);
  end
 end
endmodule
