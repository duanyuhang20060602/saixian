`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg[11:0] x=0;reg[10:0] y=0;reg[8:0] progress=0;reg[7:0] phase=0;
wire[23:0] actual[0:5],expected[0:5];wire[5:0] active,old_active;
genvar g;generate for(g=0;g<6;g=g+1)begin:pair
 localparam DELAY=g==0 ? 1:g==1 ? 21:g==2 ? 26:g==3 ? 2:5;
 photo_boot_screen #(.VIDEO_DELAY(DELAY),.STAGED_LOADING(g%2)) newer(
 .clk(clk),.rst(rst),.frame_tick(1'b0),.x(x),.y(y),.memory_ready(1'b1),.catalog_ready(1'b0),
 .frame_ready(1'b0),.animation_ready(1'b1),.audio_ready(1'b0),.active(active[g]),.rgb(actual[g]));
 photo_boot_screen_reference #(.VIDEO_DELAY(DELAY),.STAGED_LOADING(g%2)) older(
 .clk(clk),.rst(rst),.frame_tick(1'b0),.x(x),.y(y),.memory_ready(1'b1),.catalog_ready(1'b0),
 .frame_ready(1'b0),.animation_ready(1'b1),.audio_ready(1'b0),.active(old_active[g]),.rgb(expected[g]));
 initial begin
  force newer.progress=progress;force older.progress=progress;
  force newer.phase=phase;force older.phase=phase;
 end
end endgenerate
integer n,k,checked=0;reg[10:0] seen=0;
always @(posedge clk)begin #1;
 for(k=0;k<6;k=k+1)begin
  if(actual[k]!==expected[k]||active[k]!==old_active[k])$fatal(1,"startup palette/latency mismatch pair%0d pixel%0d,%0d got%h expected%h",k,x,y,actual[k],expected[k]);
  checked=checked+1;
  case(actual[k])
   24'h000000:seen[0]=1;24'hb8edff:seen[1]=1;24'h7cd8ff:seen[2]=1;24'h47baff:seen[3]=1;
   24'h2693d1:seen[4]=1;24'h17628b:seen[5]=1;24'h102c40:seen[6]=1;24'hd0e4ee:seen[7]=1;
   24'h163044:seen[8]=1;24'h359cd0:seen[9]=1;24'h080e14:seen[10]=1;
  endcase
 end
end
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(n=0;n<100000;n=n+1)begin
  @(negedge clk);progress=(n%61)*8;phase=n;
  if(n%5==0)begin x=(n*73)%1280;y=(n*11)%720;end
  else begin x=398+n%485;y=250+(n/485)%140;end
  rst=n%4000==3999;
 end
 rst=0;repeat(30)@(negedge clk);
 if(seen!=11'h7ff)$fatal(1,"startup palette coverage %h",seen);
 $display("PASS lossless startup palette: %0d exact RGB/control comparisons, all 11 colours, delays 1/2/5/21/26, both loading modes and reset",checked);$finish;
end
endmodule
