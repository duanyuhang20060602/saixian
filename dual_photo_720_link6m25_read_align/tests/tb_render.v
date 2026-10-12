`timescale 1ns/1ps
module tb_render;
reg clk=0;always #6.666667 clk=~clk;
tri1 sda;wire [7:0] seg;
top_photo_a dut(.clk(clk),.hdmi_hpd(1'b1),.link_clk(clk),.link_data(16'd0),.link_valid(1'b0),.link_sof(1'b0),.link_eof(1'b0),
 .key(4'b1111),.control_rx(1'b1),.hmi_uart_rx(1'b1),.control_tx(),.hmi_uart_tx(),.link_ready(),.image_ack(),
 .seg_sel(),.seg_data(seg),.HDMI_CLK_P(),.HDMI_D2_P(),.HDMI_D1_P(),.HDMI_D0_P(),.HDMI_DDC_SCL(),.HDMI_DDC_SDA(sda));
function [15:0] pixel;
 input integer index;begin pixel=((index*13)^16'h345a);end
endfunction
function [23:0] golden;
 input integer index;reg [15:0] p;integer r,g,b;
 begin p=pixel(index);r={p[15:11],p[15:13]};g={p[10:5],p[10:9]};b={p[4:0],p[4:2]};
 golden={8'(16+((r*219+128)>>8)),8'(16+((g*219+128)>>8)),8'(16+((b*219+128)>>8))};end
endfunction
reg [20:0] delayed_de=0;reg [23:0] expected[0:20];integer j,n=0;
always @(posedge dut.pixel_clk)begin
 if(dut.rst_pixel)delayed_de=0;
 else begin
  for(j=20;j>0;j=j-1)expected[j]=expected[j-1];
  expected[0]=golden(dut.y*1280+dut.x);delayed_de={delayed_de[19:0],dut.de};
  #1;
  if(dut.ef!=0 || dut.shf!=0 || dut.sharpness!=0 || dut.enhancement!=0)$fatal(1,"processing enable override failed");
  if(delayed_de[20])begin
   if(dut.final_rgb!==expected[20])$fatal(1,"real A pipeline alignment pixel=%d got=%h expected=%h",n,dut.final_rgb,expected[20]);
   if(dut.u_tx.send_mode!=1)$fatal(1,"HDMI active control shifted relative to RGB");
   n=n+1;
   if(n==3840)begin $display("PASS real A top: 21-cycle RGB/HDMI control alignment, RGB565 ordering, three 1280-pixel rows");$finish;end
  end
 end
end
initial begin
 force dut.display_valid=1;force dut.settings.sharpness_setting=3;force dut.settings.enhancement_setting=2;force dut.bf=4;force dut.cf=4;force dut.sf=4;force dut.invf=0;force dut.vinf=0;force dut.darkness=0;
end
initial begin #2000000;$fatal(1,"render timeout n=%d",n);end
endmodule
module sys_pll(input refclk,reset,output clk0_out,clk1_out,clk2_out,output reg locked=0);
assign clk0_out=refclk;assign clk1_out=refclk;assign clk2_out=~refclk;initial #100 locked=1;
endmodule
module video_pll(input refclk,reset,output clk0_out,clk1_out,output reg locked=0);
assign clk0_out=refclk;assign clk1_out=refclk;initial #100 locked=1;
endmodule
module hdmi_phy_wrapper #(parameter DEVICE="EG")(
 input I_pixel_clk,I_serial_clk,I_rst,input [9:0] I_tmds_channel_0,I_tmds_channel_1,I_tmds_channel_2,I_tmds_channel_clk,
 output O_tmds_ch0_p,O_tmds_ch1_p,O_tmds_ch2_p,O_tmds_clk_p);
assign O_tmds_ch0_p=0;assign O_tmds_ch1_p=0;assign O_tmds_ch2_p=0;assign O_tmds_clk_p=0;
endmodule
module frame_store #(parameter FLIP=0)(
 input [1:0] write_slot,read_slot,new_slot,input slide_active,slide_right,input [10:0] slide_offset,input [2:0] transition_mode,
 input mem_clk,mem_clk_sft,rst,write_clk,write_req,write_en,input [31:0] write_data,output write_ack,write_finish,write_full,
 input read_clk,read_req,read_en,output read_ack,read_finish,read_empty,output reg [31:0] read_data=0,output init_done);
reg [2:0] ack_pipe=0;integer word_index=0;
function [15:0] pixel;
 input integer index;begin pixel=((index*13)^16'h345a);end
endfunction
assign write_ack=0;assign write_finish=0;assign write_full=0;assign read_finish=0;assign read_empty=0;assign init_done=1;assign read_ack=ack_pipe[2];
always @(posedge read_clk)begin
 ack_pipe<={ack_pipe[1:0],read_req};
 if(rst || read_req)word_index<=0;
 else if(read_en)begin read_data<={pixel(word_index*2),pixel(word_index*2+1)};word_index<=word_index+1;end
end
endmodule
module status_segments(input [3:0] digit,output [7:0] segments);assign segments=0;endmodule
