// Self-contained sector records: raw media scan builds an index without FAT.
module photo_scan_font_index(input clk,rst,input valid,input [7:0] data,input sector_end,
 input [31:0] sector_address,input [10:0] query,output query_valid,output [31:0] query_sector,
 output complete);
reg [8:0] position;reg magic_ok,header_ok;reg [10:0] group_id;
reg [10:0] clear_index,groups_found;reg initialized;
wire scan_select=header_ok;
wire [10:0] read_group=scan_select ? group_id:query;
reg [10:0] read_group_q;
wire [31:0] low_q,high_q;
wire [31:0] entry=read_group_q[10] ? high_q:low_q;
wire record_end=initialized && sector_end && header_ok && position==0 && group_id<=1120 && !sector_address[31];
wire writing=!initialized || record_end;
wire [10:0] write_group=initialized ? group_id:clear_index;
wire [31:0] write_data=initialized ? {1'b1,sector_address[30:0]}:32'd0;
assign query_valid=initialized && read_group_q==query && query<=1120 && entry[31];
assign query_sector={1'b0,entry[30:0]};assign complete=groups_found==1121;
function [7:0] magic;input [2:0] n;begin case(n)
 0:magic="S";1:magic="X";2:magic="G";3:magic="L";4:magic="Y";5:magic="P";6:magic="0";7:magic="1";
endcase end endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin position<=0;magic_ok<=0;header_ok<=0;group_id<=0;clear_index<=0;groups_found<=0;initialized<=0;read_group_q<=0;end
 else begin
  read_group_q<=read_group;
  if(!initialized)begin if(clear_index==1151)initialized<=1;else clear_index<=clear_index+1'b1;end
  if(sector_end)begin
   if(record_end && read_group_q==group_id && !entry[31])groups_found<=groups_found+1'b1;
   position<=0;magic_ok<=0;header_ok<=0;
  end else if(valid)begin
   position<=position+1'b1;
   if(position==0)begin magic_ok<=data=="S";header_ok<=0;end
   else if(position<8)magic_ok<=magic_ok && data==magic(position[2:0]);
   if(position==8)group_id[7:0]<=data;
   if(position==9)begin group_id[10:8]<=data[2:0];header_ok<=magic_ok && data[7:3]==0;end
   if(position==10)header_ok<=header_ok && data==1;
   if(position==11)header_ok<=header_ok && data==8;
  end
 end
end
EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.ADDR_WIDTH_A(10),.DATA_DEPTH_A(1024),
 .DATA_WIDTH_B(32),.ADDR_WIDTH_B(10),.DATA_DEPTH_B(1024),.MODE("PDPW"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.IMPLEMENT("9K")) low_index(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(writing && !write_group[10]),.ocea(1'b0),.bea(1'b0),
 .addra(write_group[9:0]),.dia(write_data),.doa(),
 .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b0),.beb(1'b0),
 .addrb(read_group[9:0]),.dib(32'd0),.dob(low_q));
EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.ADDR_WIDTH_A(7),.DATA_DEPTH_A(128),
 .DATA_WIDTH_B(32),.ADDR_WIDTH_B(7),.DATA_DEPTH_B(128),.MODE("PDPW"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.IMPLEMENT("9K")) high_index(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(writing && write_group[10]),.ocea(1'b0),.bea(1'b0),
 .addra(write_group[6:0]),.dia(write_data),.doa(),
 .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b0),.beb(1'b0),
 .addrb(read_group[6:0]),.dib(32'd0),.dob(high_q));
endmodule
