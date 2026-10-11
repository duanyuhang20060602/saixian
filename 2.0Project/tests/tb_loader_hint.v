`timescale 1ns/1ps
module tb_loader_hint;
reg clk=0,rst=1,valid=0,ending=0,hint=1;
reg [7:0] data=0;reg [351:0] header=0;
wire req,ready,we;wire [31:0] sector;wire [20:0] words;wire [5:0] frames;wire [2:0] error;
always #5 clk=~clk;
delta_loader #(.MAX_FILE_BYTES(1937408),.USE_START_HINT(1),.SKIP_KNOWN_MEDIA(1)) dut(
 .clk(clk),.rst(rst),.sd_init(1'b1),.req(req),.sector(sector),.valid(valid),.data(data),.block_end(ending),.fifo_full(1'b0),
 .upload_we(we),.ready(ready),.file_words(words),.frame_count(frames),.error(error),.start_hint_valid(hint),.start_hint(32'd12345));
integer i;
task reset;begin rst=1;valid=0;ending=0;repeat(3)@(negedge clk);rst=0;wait(req);@(negedge clk);end endtask
task sector_bytes;begin
 for(i=0;i<512;i=i+1)begin data=i<44 ? header[i*8+:8] : 0;valid=1;@(negedge clk);end
 valid=0;ending=1;@(negedge clk);ending=0;repeat(4)@(negedge clk);
end endtask
initial begin
 header[63:0]=64'h313030544c445853;header[79:64]=1;header[95:80]=512;
 header[111:96]=480;header[127:112]=480;header[159:128]=27;header[191:160]=1890304;
 header[223:192]=115200;header[255:224]=1;header[287:256]=32;header[351:320]=28;
 reset;if(sector!=12345)$fatal(1,"hint not used");sector_bytes;
 if(!dut.loading || error || words!=472576 || frames!=27 || sector!=12345)$fatal(1,"real DLT hint rejected");
 header[191:160]=1937920;reset;sector_bytes;
 if(error!=7 || ready || we || req)$fatal(1,"oversized file escaped reserved TF memory");
 header=0;reset;sector_bytes;
 if(sector!=0 || error || !req)$fatal(1,"invalid hint did not fall back to scan");
 hint=0;reset;if(sector!=0)$fatal(1,"unhinted scan did not start at zero");
 header=0;header[15:0]=16'h4d42;header[47:16]=921654;header[143:112]=40;
 header[223:208]=1;header[239:224]=24;sector_bytes;
 if(sector!=1801 || error)$fatal(1,"BMP payload not skipped exactly");
 header=0;header[63:0]=64'h3130304455415853;header[95:64]=62914560;
 header[127:96]=48000;header[143:128]=16;header[159:144]=2;
 reset;sector_bytes;if(sector!=122881 || error)$fatal(1,"60 MiB AUD payload not skipped exactly");
 $display("PASS loader hint: real 27-frame header, direct sector lookup, invalid-hint fallback, oversized DLT rejection, exact BMP/60 MiB AUD payload skipping");$finish;
end
endmodule
