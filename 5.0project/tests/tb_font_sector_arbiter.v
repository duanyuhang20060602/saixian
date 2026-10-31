`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,fr=0,bv=0,done=0,aq=0,bq=0,dq=0;
always #5 clk=~clk;
wire fv,fe;wire[7:0] fd;
photo_sd_cache #(.TYPED_TEXT(1)) dut(.clk(clk),.rst(rst),.font_read(fr),.font_sector(32'd12345),.font_valid(fv),.font_data(fd),.font_end(fe));
initial begin
 force dut.abort_op=0;force dut.initialized=1;force dut.byte_valid=bv;force dut.byte_data=8'ha5;force dut.sector_end=done;
 force dut.audio_sd_req=aq;force dut.audio_switching=0;force dut.audio_sd_addr=32'd222;
 force dut.bmp_read_req=bq;force dut.bmp_read_addr=32'd333;force dut.dlt_req=dq;force dut.dlt_sector=32'd444;
end
task finish;begin @(negedge clk);done=1;@(negedge clk);done=0;repeat(2)@(negedge clk);end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 bq=1;repeat(2)@(negedge clk);bq=0;if(dut.read_owner!=1)$fatal(1,"BMP not scheduled");
 fr=1;@(negedge clk);fr=0;aq=1;dq=1;repeat(4)@(negedge clk);
 if(dut.read_owner!=1 || !dut.font_wait)$fatal(1,"font pulse lost or interrupted BMP");
 finish;if(dut.read_owner!=2 || dut.read_address!=222)$fatal(1,"audio must win at sector boundary");
 aq=0;finish;if(dut.read_owner!=4 || dut.read_address!=12345)$fatal(1,"queued font did not win ahead of DLT");
 bv=1;@(negedge clk);if(!fv || fd!=8'ha5)$fatal(1,"font data routing");bv=0;
 @(negedge clk);done=1;#1;if(!fe)$fatal(1,"font end routing");@(negedge clk);done=0;repeat(2)@(negedge clk);
 if(dut.read_owner!=3 || dut.read_address!=444)$fatal(1,"DLT did not resume");
 bv=1;#1;if(fv || fe)$fatal(1,"other sector leaked into font consumer");
 $display("PASS production sector arbiter: captured pulse while busy, no mid-sector preemption, audio priority, font routing and DLT resume");$finish;
end
initial begin #10000;$fatal(1,"arbiter timeout");end
endmodule
