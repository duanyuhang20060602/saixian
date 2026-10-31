// Fetch one glyph using the sector index built by the existing media scan.
module photo_scan_glyph_b(input clk,rst,input request,input [13:0] code,input clear_line,
 input map_valid,input [31:0] map_sector,input scan_complete,
 output reg ready,output reg failed,input consume,output [31:0] word,
 output reg read_sector,output reg [31:0] sector,
 input byte_valid,input [7:0] byte_data,input sector_end);
reg [2:0] state,read_index;reg [8:0] position;reg [7:0] first_byte;reg blank;
wire [8:0] offset=position-9'd16;
wire selected=position>=16 && position<272 && offset[7:5]==code[2:0];
wire writing=state==3 && byte_valid && selected && offset[0];
wire [2:0] next_read_index=read_index+(consume ? 3'd1:3'd0);
wire [3:0] port_address=state==3 ? offset[4:1]:{next_read_index,1'b0};
wire [15:0] upper,lower;assign word=blank ? 32'd0:{upper,lower};
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(4),.DATA_DEPTH_A(16),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(4),.DATA_DEPTH_B(16),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.IMPLEMENT("9K")) cache(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(writing),.ocea(1'b0),.bea(1'b0),
 .addra(port_address),.dia({first_byte,byte_data}),.doa(upper),
 .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b0),.beb(1'b0),
 .addrb({next_read_index,1'b1}),.dib(16'd0),.dob(lower));
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=0;ready<=0;failed<=0;read_index<=0;position<=0;first_byte<=0;blank<=0;read_sector<=0;sector<=0;end
 else begin
  read_sector<=0;
  if(consume)read_index<=read_index+1'b1;
  case(state)
   0:if(request)begin ready<=0;failed<=0;read_index<=0;blank<=clear_line;state<=clear_line ? 4:1;end
   1:state<=2;
   2:if(map_valid)begin read_sector<=1;sector<=map_sector;position<=0;state<=3;end
     else if(scan_complete)begin failed<=1;state<=5;end
   3:begin
    if(byte_valid)begin first_byte<=byte_data;position<=position+1'b1;end
    if(sector_end)state<=4;
   end
   4:begin ready<=1;state<=5;end
   5:if(!request)begin ready<=0;failed<=0;state<=0;end
   default:state<=0;
  endcase
 end
end
endmodule
