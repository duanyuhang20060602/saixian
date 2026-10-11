`timescale 1ns/1ps
module tb_volume_boost;
reg [3:0] volume;
reg [23:0] li,ri;
reg [7:0] meter;
reg clk=0,rst=1;
always #5 clk=~clk;
wire [23:0] lo,ro;
wire [7:0] mo;
wire [23:0] plo,pro;
wire [7:0] pmo;
integer gains[0:8],i,j,value,want,left_expected,right_expected;
saixian_audio_volume dut(volume,li,ri,meter,lo,ro,mo,clk,rst);
saixian_audio_volume #(.PIPELINE(1)) pipeline(volume,li,ri,meter,plo,pro,pmo,clk,rst);
function integer clamp;
input integer n;
begin clamp=n>8388607 ? 8388607 : n< -8388608 ? -8388608 : n;end
endfunction
initial begin
repeat(3)@(negedge clk);rst=0;
gains[0]=0;gains[1]=2;gains[2]=4;gains[3]=5;gains[4]=6;
gains[5]=7;gains[6]=8;gains[7]=9;gains[8]=10;
for(i=0;i<9;i=i+1)begin
 volume=i;
 for(j=0;j<1000;j=j+1)begin
  @(negedge clk);
  value=j<2 ? (j==0 ? 8388607 : -8388608) : ($random%8388608);
  li=value;ri=-value;meter=j%256;
  left_expected=clamp((value*gains[i])>>>3);
  right_expected=clamp((-value*gains[i])>>>3);
  // -(-8388608) is outside input range: use same negative full-scale both sides.
  if(value== -8388608)begin ri=value;right_expected=left_expected;end
  #1;
  if($signed(lo)!==left_expected || $signed(ro)!==right_expected)
   $fatal(1,"volume %d sample %d got %d/%d expected %d/%d",i,value,$signed(lo),$signed(ro),left_expected,right_expected);
  if(i==0 && mo!==0)$fatal(1,"mute meter");
  if(i==8 && meter==255 && mo!==255)$fatal(1,"meter wrapped");
  @(posedge clk);#1;
  if(plo!==lo || pro!==ro || pmo!==mo)$fatal(1,"volume pipeline changed sample/meter");
 end
end
$display("PASS boosted volume: all 9 gains, stereo signs, zero mute, full-scale saturation, meter saturation (9000 samples)");$finish;
end
endmodule
