`timescale 1ns/1ps
// Four snapshots cover the audio FIFO's look-ahead without displaying future
// audio. Incomplete/bad-CRC requests never become visible. Oldest eligible
// snapshots retire at vertical blanking, independent of metadata reception.
module photo_av_metadata_a #(parameter EDGE_METADATA=0)(
 input clk,rst,frame_tick,input [31:0] play_position,
 input begin_packet,word_valid,commit_packet,finish_packet,
 input [8:0] word_index,input [31:0] word_data,
 output available,input [4:0] read_band,input [7:0] read_index,
 output [6:0] height,peak,output [31:0] extrema,
 output fft_valid,wave_valid,output [7:0] edge_target
);
reg [3:0] occupied,eligible;
reg [7:0] generation,bank_generation[0:3];
reg [31:0] position[0:3];
// Eligibility has a full pixel clock. The publication selector compares only
// short generation tags, avoiding cascaded wide sample-position subtractors.
integer e;
always @(posedge clk or posedge rst)
 if(rst)eligible<=0;
 else for(e=0;e<4;e=e+1)eligible[e]<=occupied[e] && $signed(play_position-position[e])>=0;
reg [1:0] flags[0:3];
reg [1:0] display_bank,write_bank;reg display_present,receiving;
reg [1:0] packet_fields;reg [7:0] bank_edge[0:3];
assign edge_target=display_present ? bank_edge[display_bank]:8'd0;
wire header_valid=EDGE_METADATA ? word_data[31:16]==16'h4132:word_data[31:8]==24'h415631;
reg [1:0] free_bank;reg free_found;
integer i,j;
always @* begin
 free_bank=0;free_found=0;
 for(j=0;j<4;j=j+1)begin
  if(!occupied[j] && (!display_present || display_bank!=j) && (!receiving || write_bank!=j))begin free_bank=j;free_found=1;end

 end
end
// Balanced two-pair arbitration, then a publication register. The four
// result banks are ordered by short generation tags, including wraparound.
wire [3:0] ready_bank=occupied & eligible;
wire select1=ready_bank[1] && (!ready_bank[0] || $signed(bank_generation[1]-bank_generation[0])>0);
wire select3=ready_bank[3] && (!ready_bank[2] || $signed(bank_generation[3]-bank_generation[2])>0);
wire [1:0] pair01=select1 ? 2'd1:2'd0,pair23=select3 ? 2'd3:2'd2;
wire choose23=(|ready_bank[3:2]) && (!(|ready_bank[1:0]) || $signed(bank_generation[pair23]-bank_generation[pair01])>0);
reg [1:0] selected_bank;reg selected_valid;
always @(posedge clk or posedge rst)
 if(rst)begin selected_bank<=0;selected_valid<=0;end
 else begin selected_bank<=choose23 ? pair23:pair01;selected_valid<=|ready_bank;end
assign available=free_found && !receiving;
wire [31:0] wave_q;wire [15:0] band_q;
wire wave_write=receiving && word_valid && word_index>=34 && word_index<290;
wire band_write=receiving && word_valid && word_index>=2 && word_index<34;
wire [8:0] packet_wave_index=word_index-9'd34;
wire [4:0] packet_band_index=word_index[4:0]-5'd2;
// Native RAM9K mappings; no analysis arrays remain on A.
EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.ADDR_WIDTH_A(10),.DATA_DEPTH_A(1024),
 .DATA_WIDTH_B(32),.ADDR_WIDTH_B(10),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),
 .MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) wave_cache(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(wave_write),.ocea(1'b0),.bea(1'b0),
 .addra({write_bank,packet_wave_index[7:0]}),.dia(word_data),.doa(),
 .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b0),.beb(1'b0),
 .addrb({display_bank,read_index}),.dib(32'd0),.dob(wave_q));
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(7),.DATA_DEPTH_A(128),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(7),.DATA_DEPTH_B(128),.BYTE_ENABLE(0),
 .MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) band_cache(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(band_write),.ocea(1'b0),.bea(1'b0),
 .addra({write_bank,packet_band_index}),.dia(word_data[15:0]),.doa(),
 .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b0),.beb(1'b0),
 .addrb({display_bank,read_band}),.dib(16'd0),.dob(band_q));
assign height=fft_valid ? band_q[6:0]:7'd0;
assign peak=fft_valid ? band_q[13:7]:7'd0;
assign extrema=wave_valid ? wave_q:32'd0;
assign fft_valid=display_present && flags[display_bank][0];
assign wave_valid=display_present && flags[display_bank][1];
always @(posedge clk or posedge rst)begin
 if(rst)begin
  occupied<=0;generation<=0;display_bank<=0;write_bank<=0;display_present<=0;receiving<=0;packet_fields<=0;
  for(i=0;i<4;i=i+1)begin position[i]<=0;flags[i]<=0;bank_generation[i]<=0;bank_edge[i]<=0;end
 end else begin
  if(frame_tick && selected_valid)begin
   display_bank<=selected_bank;display_present<=1;
   for(i=0;i<4;i=i+1)
    if(occupied[i] && $signed(bank_generation[selected_bank]-bank_generation[i])>=0)occupied[i]<=0;
  end
  if(begin_packet && available)begin write_bank<=free_bank;receiving<=1;packet_fields<=0;end
  if(word_valid && receiving)begin
   if(word_index==0)begin
    flags[write_bank]<=header_valid ? word_data[1:0]:2'd0;
    bank_edge[write_bank]<=EDGE_METADATA && header_valid ? word_data[15:8]:8'd0;
    packet_fields[0]<=1;
   end
   if(word_index==1)begin position[write_bank]<=word_data;packet_fields[1]<=1;end
  end
  if(finish_packet)begin
   receiving<=0;
   // The unpublished bank already holds the complete metadata. Only this
   // validity bit crosses the CRC commit boundary; no duplicate staging bank.
   if(commit_packet && receiving && &packet_fields)begin occupied[write_bank]<=1;bank_generation[write_bank]<=generation;generation<=generation+1'b1;end
  end
 end
end
endmodule
