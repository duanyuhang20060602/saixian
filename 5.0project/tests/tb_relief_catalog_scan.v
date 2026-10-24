`timescale 1ns/1ps
// Exercise the production scanner and header parsers. Only the SD sector source
// is modeled; file headers are generated from the actual old/new DLT packages.
module tb;
parameter REVERSE=0;
reg clk=0;always #5 clk=~clk;reg rst=1,start=0;
wire ready,done,exhausted,found,dlt,req;wire[31:0] address,found_sector;
wire[15:0] width,height;wire[2:0] total;
reg[7:0] headers[0:5119];reg valid=0,block_end=0;reg[7:0] data=0;
reg[31:0] sectors[0:10];integer i,j,active=0,byte_index=0,selected=0,reads=0,photos=0,old=0,gold=0;
integer expected_type;
bmp_read dut(.clk(clk),.rst(rst),.op_abort(1'b0),.ready(ready),.scan_start(start),.scan_stop(1'b0),.scan_resume(1'b0),
 .scan_start_sector(32'd0),.scan_max_sector(sectors[10]-1),.scan_target_count(3'd6),.scan_done(done),.scan_exhausted(exhausted),
 .scan_found_valid(found),.scan_found_sector(found_sector),.scan_found_total(total),.scan_found_width(width),.scan_found_height(height),
 .scan_found_sprint(),.scan_found_dlt(dlt),.audio_found_valid(),.audio_found_index(),.audio_found_sector(),.audio_found_bytes(),
 .load_start(1'b0),.load_sector(32'd0),.sd_init_done(1'b1),.state_code(),.bmp_width(16'd1280),.bmp_height(16'd720),
 .write_req(),.write_req_ack(1'b0),.sd_sec_read(req),.sd_sec_read_addr(address),.sd_sec_read_data(data),
 .sd_sec_read_data_valid(valid),.sd_sec_read_end(block_end),.bmp_data_wr_en(),.bmp_data(),.scaler_fault_o());
// Catalog fixture lengths describe full files; the SD model serves only headers.
initial begin
 $readmemh("catalog_headers.hex",headers);
 $readmemh("catalog_sectors.hex",sectors);
 repeat(5)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
 wait(done);repeat(4)@(negedge clk);
 if(!exhausted || total!=6 || photos!=6 || old!=2 || gold!=2 || reads!=10)
  $fatal(1,"scan counts photos=%0d old=%0d relief=%0d sectors=%0d total=%0d",photos,old,gold,reads,total);
 $display("PASS production BMP/DLT scanner: six photos, two old/new award pairs, mixed headers, file-length skipping, exact source-size flags; reverse=%0d",REVERSE);$finish;
end
always @(posedge clk)if(!rst && found)begin
 if(height!=720)$fatal(1,"catalog height");
 if(photos<6)begin
  if(dlt || width!=1280 || found_sector!=sectors[photos])$fatal(1,"photo incorrectly classified");
  photos=photos+1;
 end else begin
  expected_type=REVERSE ? ((old+gold)%2==0):((old+gold)%2!=0);
  if(!dlt || width!=(expected_type ? 16'hc500:16'h8500))$fatal(1,"old/new format classification");
  if(expected_type)gold=gold+1;else old=old+1;
 end
end
always @(negedge clk)begin
 valid=0;block_end=0;
 if(rst)begin active=0;reads=0;end
 else case(active)
  0:if(req)begin
   selected=-1;
   for(j=0;j<10;j=j+1)if(address==sectors[j])selected=j;
   if(selected<0)$fatal(1,"scanner requested payload/incorrect next header sector %0d",address);
   if(selected!=reads)$fatal(1,"scanner repeated/skipped a file header");
   reads=reads+1;byte_index=0;active=1;
  end
  1:begin data=headers[selected*512+byte_index];valid=1;
   if(byte_index==511)active=2;else byte_index=byte_index+1;
  end
  2:begin block_end=1;active=3;end
  3:if(!req)active=0;
 endcase
end
initial begin #1000000;$fatal(1,"catalog scanner timeout reads=%0d addr=%0d",reads,address);end
endmodule
