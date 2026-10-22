`timescale 1ns/1ps
module tb_dlt_faults;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,valid=0,last=0;reg [7:0] data=0;reg [1:0] ack=0;
wire ready,done,wr,pv,req;wire [3:0] error;wire [31:0] sector;wire [23:0] pixel;
reg [7:0] bytes[0:2047];integer mode=0,i,s,limit,count=0;reg [3:0] wanted;
photo_dlt_reader #(.PIXEL_GAP(1)) dut(clk,rst,start,32'd0,ready,done,error,wr,ack[1],1'b0,pv,pixel,req,sector,valid,data,last);
always @(posedge clk)ack<={ack[0],wr};
always @(negedge clk)begin
 if(pv)count=count+1;
 if(wr && (mode==0 || mode==2))$fatal(1,"write started before header/payload/index verification case=%0d",mode);
end
initial forever begin
 wait(req);s=sector;limit=mode==4 && s==0 ? 32:512;
 for(i=0;i<limit;i=i+1)begin @(negedge clk);valid=1;data=bytes[s*512+i];end
 @(negedge clk);valid=0;last=1;@(negedge clk);last=0;wait(!req);
end
string path;
initial begin
 for(mode=0;mode<12;mode=mode+1)begin
  $sformat(path,"tests/results/dlt_fault%0d.hex",mode);$readmemh(path,bytes);count=0;
  if(mode==0)begin repeat(4)@(negedge clk);rst=0;end
  repeat(4)@(negedge clk);start=1;@(negedge clk);start=0;
  if(mode==11 || mode==1 || mode==5 || mode==6)begin
   wait(done);if(count!=921600 || error)$fatal(1,"CRC-free decode/retry failed");
  end else begin
   case(mode)0:wanted=1;1:wanted=3;2:wanted=4;3:wanted=5;4:wanted=2;5:wanted=6;6:wanted=7;default:wanted=5;endcase
   wait(error!=0);if(error!==wanted)$fatal(1,"fault case=%0d got=%0d expected=%0d",mode,error,wanted);
   if(mode==5 || mode==6)begin if(count!=921600)$fatal(1,"late CRC test did not decode full frame");end
   $display("PASS DLT reject case=%0d code=%0d pixels=%0d",mode,error,count);$fflush();
  end
  repeat(5)@(negedge clk);
 end
 $display("PASS NOCRC: altered payload/stream/frame CRC accepted; header, descriptor, truncated sector, illegal commands and incomplete raster rejected; valid retry");$finish;
end
initial begin #200000000;$fatal(1,"DLT fault timeout case=%0d state=%0d",mode,dut.state);end
endmodule
