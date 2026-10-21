`timescale 1ns/1ps
module tb_fx_dlt_bounds;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,valid=0,last=0;reg [7:0] data=0;
wire req,ready;wire [31:0] sector;wire [3:0] error;
reg [31:0] words[0:599999];reg [31:0] offset,limit;
reg [32:0] ending;reg invalid;integer i,j;
photo_dlt_reader dut(.clk(clk),.rst(rst),.start(start),.start_sector(32'd100),
 .ready(ready),.error(error),.write_ack(1'b0),.full(1'b0),.req(req),.sector(sector),
 .byte_valid(valid),.byte_data(data),.block_end(last));
initial begin
 $readmemh("tests/fx_audio_results/award_file.hex",words);
 limit=(words[5]>>2)-230400;
 for(i=0;i<40;i=i+1)begin
  case(i)
   0:offset=words[65];1:offset=limit&32'hffffff80;
   2:offset=(limit&32'hffffff80)+128;3:offset=32'hffffff80;
   4:offset=0;5:offset=words[65]+1;
   default:offset={$random}&32'hffffff80;
  endcase
  ending={1'b0,offset}+33'd230400;
  invalid=(offset[6:0]!=0 || ending>{3'd0,words[5][31:2]});
  @(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;start=1;
  @(negedge clk);start=0;wait(req);
  for(j=0;j<512;j=j+1)begin
   @(negedge clk);valid=1;
   data=j>=260 && j<264 ? offset>>((j-260)*8):words[j/4]>>((j%4)*8);
  end
  @(negedge clk);valid=0;last=1;
  @(negedge clk);last=0;repeat(8)@(negedge clk);
  if(invalid ? error!=1 : error!=0 || !req || sector!=101)
   $fatal(1,"DLT bounds mismatch offset=%h end=%h expected_invalid=%b error=%d",offset,ending,invalid,error);
 end
 $display("PASS DLT header bounds: 40 real 512-byte headers, valid edge, overrun, 33-bit overflow, alignment and reset/retry");$finish;
end
initial begin #1000000;$fatal(1,"DLT bounds timeout");end
endmodule
