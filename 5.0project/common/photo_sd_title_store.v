// Two self-contained, sector-aligned records. Sniff the existing media scan;
// no second SD controller, sector buffer, filename parser or extra reads.
module photo_sd_title_store #(parameter INDEPENDENT_TEXT=0)(input clk,rst,valid,input [7:0] data,input sector_end,
 output ready,output [4:0] length,input [6+INDEPENDENT_TEXT:0] address,output [31:0] word);
reg [8:0] position;
reg magic_ok,header_ok;reg [INDEPENDENT_TEXT:0] part;
reg [7:0] record_length;
reg [31:0] record_id,record_crc,crc,identity;
reg [4:0] saved_length,saved_ticker_length;
reg [(INDEPENDENT_TEXT ? 4:2)-1:0] accepted;
reg [7:0] packed_byte;reg ready_q;wire complete=&accepted;
wire payload=position>=20 && position<276;
wire [8:0] offset=position-9'd20;
wire write_word=valid && header_ok && payload && offset[0] && !complete;
wire [7+INDEPENDENT_TEXT:0] write_address={part,offset[7:1]};
wire [7+INDEPENDENT_TEXT:0] first_address=complete ? {address,1'b0}:write_address;
wire [15:0] first_word,second_word;
assign word={first_word,second_word};
function [31:0] crc_byte;input [31:0] c;input [7:0] b;reg [31:0] t;integer i;begin
 t=c^{24'd0,b};for(i=0;i<8;i=i+1)t=(t>>1)^(t[0] ? 32'hedb88320:0);crc_byte=t;
end endfunction
function [7:0] magic_byte;input [2:0] i;begin
 case(i)0:magic_byte="S";1:magic_byte="X";2:magic_byte="T";3:magic_byte="T";
 4:magic_byte="L";5:magic_byte="0";6:magic_byte="0";default:magic_byte=INDEPENDENT_TEXT ? "2":"1";endcase
end endfunction
assign ready=ready_q;
always @(posedge clk or posedge rst)if(rst)ready_q<=0;else ready_q<=complete;assign length=ready ? ((INDEPENDENT_TEXT && address[6+INDEPENDENT_TEXT]) ? saved_ticker_length:saved_length):5'd0;
always @(posedge clk or posedge rst)begin
 if(rst)begin position<=0;magic_ok<=0;header_ok<=0;part<=0;record_length<=0;
  record_id<=0;record_crc<=0;crc<=32'hffffffff;identity<=0;saved_length<=0;saved_ticker_length<=0;accepted<=0;packed_byte<=0;end
 else if(!complete)begin
  if(sector_end)begin
   if(position==0 && header_ok && ~crc==record_crc)accepted[part]<=1;
   position<=0;magic_ok<=0;header_ok<=0;crc<=32'hffffffff;
  end else if(valid)begin
   position<=position+1'b1;
   if(position==0)begin magic_ok<=data=="S";header_ok<=0;crc<=32'hffffffff;end
   else if(position<8)magic_ok<=magic_ok && data==magic_byte(position[2:0]);
   if(position==8)begin record_length<=data;header_ok<=magic_ok && data!=0 && data<=16;end
   if(position==9)begin part<=data[INDEPENDENT_TEXT:0];header_ok<=header_ok && data<(INDEPENDENT_TEXT ? 4:2);end
   if(position==10)header_ok<=header_ok && data==(INDEPENDENT_TEXT ? 2:1);
   if(position==11)header_ok<=header_ok && data==0;
   if(position>=12 && position<16)record_id<={record_id[23:0],data};
   if(position>=16 && position<20)record_crc<={record_crc[23:0],data};
   if(position==19 && header_ok)begin
    if(identity!=record_id)accepted<=0;
    else if(((INDEPENDENT_TEXT && part[INDEPENDENT_TEXT]) ? saved_ticker_length:saved_length)!=record_length[4:0])begin
     if(INDEPENDENT_TEXT && part[INDEPENDENT_TEXT])accepted<=accepted & 4'b0011;else accepted[1:0]<=0;
    end
    else accepted[part]<=0;
    identity<=record_id;
    if(INDEPENDENT_TEXT && part[INDEPENDENT_TEXT])saved_ticker_length<=record_length[4:0];
    else saved_length<=record_length[4:0];
   end
   if((position>=8 && position<16) || payload)crc<=crc_byte(crc,data);
   if(payload)packed_byte<=data;
  end
 end
end
`ifdef TITLE_SIM
reg [15:0] memory[0:(INDEPENDENT_TEXT ? 512:256)-1];reg [15:0] first_q,second_q;
always @(posedge clk)begin
 if(write_word)memory[write_address]<={packed_byte,data};
 first_q<=memory[first_address];second_q<=memory[{address,1'b1}];
end
assign first_word=first_q;assign second_word=second_q;
`else
// One 16-bit true dual-port RAM serves both halves of the UART word.
// During loading port A writes; after completion it reads the even row.
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(8+INDEPENDENT_TEXT),.DATA_DEPTH_A(INDEPENDENT_TEXT ? 512:256),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(8+INDEPENDENT_TEXT),.DATA_DEPTH_B(INDEPENDENT_TEXT ? 512:256),.BYTE_ENABLE(0),
 .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) memory(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(write_word),.ocea(1'b0),.bea(1'b0),
 .addra(first_address),.dia({packed_byte,data}),.doa(first_word),
 .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b0),.beb(1'b0),
 .addrb({address,1'b1}),.dib(16'd0),.dob(second_word));
`endif
endmodule
