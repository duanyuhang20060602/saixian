// Exact single-board SXDLT003 plate header. Checks are registered separately
// to keep the 100 MHz media state transition shallow. All fields settle well
// before the end of the 512-byte header sector.
module photo_dlt_header(input clk,rst,valid,input [5:0] index,input [7:0] data,
 output header_ok,output [31:0] file_bytes,payload_crc,output is_relief);
// Most fields are compared only with fixed constants. Retain one equality
// bit per constant byte instead of eight data bits. Independent byte enables
// preserve partial/out-of-order writes and the original registered checks.
reg[43:0] constant_match;reg[31:0] bytes_q,crc_q;reg [7:0] checks;
reg relief_digit,relief_version;
assign is_relief=relief_digit;
assign file_bytes=bytes_q;assign payload_crc=crc_q;
assign header_ok=&checks;
function[7:0] expected_byte;input[5:0] n;begin
 case(n)
 0:expected_byte=8'h53;1:expected_byte=8'h58;2:expected_byte=8'h44;3:expected_byte=8'h4c;
 4:expected_byte=8'h54;5:expected_byte=8'h30;6:expected_byte=8'h30;7:expected_byte=8'h35;
 8:expected_byte=5;11:expected_byte=2;13:expected_byte=5;14:expected_byte=8'hd0;
 15:expected_byte=2;16:expected_byte=1;25:expected_byte=8'h08;26:expected_byte=8'h07;
 28:expected_byte=1;32:expected_byte=32;40:expected_byte=2;
 default:expected_byte=0;
 endcase
end endfunction
integer byte_index;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  bytes_q<=0;crc_q<=0;checks<=0;relief_digit<=0;relief_version<=0;
  for(byte_index=0;byte_index<44;byte_index=byte_index+1)
   constant_match[byte_index]<=expected_byte(byte_index)==0;
 end
 else begin
  if(valid && index<44)begin
   if(index==7)begin constant_match[index]<=data==8'h35 || data==8'h36;relief_digit<=data==8'h36;end
   else if(index==8)begin constant_match[index]<=data==5 || data==6;relief_version<=data==6;end
   else constant_match[index]<=data==expected_byte(index);
  end
  if(valid && index>=20 && index<24)bytes_q[index[1:0]*8+:8]<=data;
  if(valid && index>=36 && index<40)crc_q[index[1:0]*8+:8]<=data;
  checks[0]<=&constant_match[7:0];
  checks[1]<=(&constant_match[11:8]) && relief_digit==relief_version;
  checks[2]<=&constant_match[15:12];
  checks[3]<=&constant_match[19:16];
  checks[4]<=bytes_q>=2048 && bytes_q<=4702208 && bytes_q[8:0]==0;
  checks[5]<=&constant_match[27:24];
  checks[6]<=&constant_match[35:28];
  checks[7]<=&constant_match[43:40];
 end
end
endmodule
