// Exact single-board SXDLT003 plate header. Checks are registered separately
// to keep the 100 MHz media state transition shallow. All fields settle well
// before the end of the 512-byte header sector.
module photo_dlt_header(input clk,rst,valid,input [5:0] index,input [7:0] data,
 output header_ok,output [31:0] file_bytes,payload_crc);
reg [351:0] header;reg [7:0] checks;
assign file_bytes=header[191:160];assign payload_crc=header[319:288];
assign header_ok=&checks;
always @(posedge clk or posedge rst)begin
 if(rst)begin header<=0;checks<=0;end
 else begin
  if(valid && index<44)header[index*8+:8]<=data;
  checks[0]<=header[63:0]==64'h333030544c445853;
  checks[1]<=header[79:64]==3 && header[95:80]==512;
  checks[2]<=header[111:96]==1280 && header[127:112]==720;
  checks[3]<=header[159:128]==1;
  checks[4]<=header[191:160]>=2048 && header[191:160]<=4702208 && header[168:160]==0;
  checks[5]<=header[223:192]==460800;
  checks[6]<=header[255:224]==1 && header[287:256]==32;
  checks[7]<=header[351:320]==2;
 end
end
endmodule
