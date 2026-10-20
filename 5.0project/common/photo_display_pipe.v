// B owns image enhancement. A only preserves the established 15-clock
// neutral processing latency; no second enhancement/adjustment engine.
module photo_neutral_delay(
 input clk,rst,de,input [23:0] rgb_in,output [23:0] rgb_out
);
// Native eRAM uses one write and one synchronous read each pixel clock.
// The 14-clock storage distance plus the input edge preserves 15 stages.
reg [3:0] pointer,age;
wire [3:0] read_address=pointer+4'd2;
wire [23:0] stored;
always @(posedge clk or posedge rst)begin
 if(rst)begin pointer<=0;age<=0;end
 else begin pointer<=pointer+1'b1;if(age<15)age<=age+1'b1;end
end
photo_video_eram #(.MODE("PDPW")) pixels(.clk(clk),
 .wa(pointer),.wea(!rst),.a_in(de ? rgb_in:24'd0),.a_out(),
 .wb(read_address),.web(1'b0),.b_in(24'd0),.b_out(stored));
assign rgb_out=age==15 ? stored:24'd0;
endmodule

// Four colour clocks, matching the original style/fade/range pipeline.
// Gain is frame-stable in blanking. At the midpoint level 63 is true black.
module photo_display_fade(
 input clk,rst,input [5:0] darkness,input [23:0] rgb_in,output reg [23:0] rgb_out
);
reg [23:0] source,dimmed;reg [6:0] gain;
reg [15:0] red_range,green_range,blue_range;
function [7:0] fade;
 input [7:0] value;input [6:0] amount;reg [14:0] product;
 begin product=value*amount;fade=product[13:6];end
endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin source<=0;dimmed<=0;gain<=64;red_range<=0;green_range<=0;blue_range<=0;rgb_out<=24'h101010;end
 else begin
  source<=rgb_in;gain<=darkness==63 ? 7'd0:7'd64-{1'b0,darkness};
  dimmed<={fade(source[23:16],gain),fade(source[15:8],gain),fade(source[7:0],gain)};
  red_range<=dimmed[23:16]*8'd219+16'd128;
  green_range<=dimmed[15:8]*8'd219+16'd128;
  blue_range<=dimmed[7:0]*8'd219+16'd128;
  rgb_out<={8'd16+red_range[15:8],8'd16+green_range[15:8],8'd16+blue_range[15:8]};
 end
end
endmodule

// Two circular FIFOs share the eRAM's independent ports and disjoint rows.
// Read-before-write makes port A the seven-clock tap and port B the twelve-
// clock tap, including the clock that transfers A into B. No pixel is dropped.
module photo_award_delay(input clk,rst,input [23:0] rgb_in,
 output [23:0] rgb,menu_rgb);
reg [3:0] first,second,age;
wire [23:0] tap7,tap12;
always @(posedge clk)begin
 if(rst)begin first<=0;second<=8;age<=0;end
 else begin
  first<=first==5 ? 4'd0:first+1'b1;
  second<=second==11 ? 4'd8:second+1'b1;
  if(age<12)age<=age+1'b1;
 end
end
photo_video_eram #(.WRITE_MODE("READBEFOREWRITE")) pixels(.clk(clk),
 .wa(first),.wea(!rst),.a_in(rgb_in),.a_out(tap7),
 .wb(second),.web(!rst),.b_in(menu_rgb),.b_out(tap12));
assign menu_rgb=age>=7 ? tap7:24'd0;
assign rgb=age>=12 ? tap12:24'd0;
endmodule

// TD's eRAM IP configuration: 24-bit, 16-word, 9K implementation, no extra
// output register. The simulation branch implements that documented contract.
module photo_video_eram #(parameter MODE="DP",WRITE_MODE="NORMAL")(
 input clk,input [3:0] wa,input wea,input [23:0] a_in,output [23:0] a_out,
 input [3:0] wb,input web,input [23:0] b_in,output [23:0] b_out);
`ifdef ERAM_SIM
reg [23:0] memory[0:15];reg [23:0] qa,qb;
always @(posedge clk)begin
 if(wea)memory[wa]<=a_in;
 if(web)memory[wb]<=b_in;
 if(!wea || WRITE_MODE=="READBEFOREWRITE")qa<=memory[wa];
 if(!web || WRITE_MODE=="READBEFOREWRITE")qb<=memory[wb];
 if(wea && web && wa==wb)$fatal(1,"eRAM FIFO ports overlap");
end
assign a_out=qa;assign b_out=qb;
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(24),.ADDR_WIDTH_A(4),.DATA_DEPTH_A(16),
 .DATA_WIDTH_B(24),.ADDR_WIDTH_B(4),.DATA_DEPTH_B(16),.BYTE_ENABLE(0),
 .MODE(MODE),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A(WRITE_MODE),.WRITEMODE_B(WRITE_MODE),.RESETMODE("SYNC"),.IMPLEMENT("9K")) memory(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(wea),.ocea(1'b1),.bea(1'b0),.addra(wa),.dia(a_in),.doa(a_out),
 .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(web),.oceb(1'b1),.beb(1'b0),.addrb(wb),.dib(b_in),.dob(b_out));
`endif
endmodule
