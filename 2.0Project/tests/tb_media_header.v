`timescale 1ns/1ps
// Reference reconstructs full little-endian fields; it does not use the
// DUT's accumulated predicates or compressed diagnostic representations.
module tb_media_header;
reg clk=0;always #5 clk=~clk;
reg rst=1,valid=0,scan_audio=1;
reg [5:0] index=0;reg [7:0] data=0;
wire b,m,dib,planes,bits24,uncompressed,sx,sy,magic,rate,bits16,stereo;
wire [31:0] fl,offset,width,height,audio_len;
saixian_media_header dut(clk,rst,valid,scan_audio,index,data,
    b,m,dib,planes,bits24,uncompressed,sx,sy,magic,rate,bits16,stereo,
    fl,offset,audio_len,width,height);
reg [7:0] bytes[0:63];
reg [31:0] random_state=32'h49f713ac;
reg [63:0] reference_magic;
reg [35:0] held_audio;
integer i,j,k,kind,cases=0;
function [31:0] word32;
 input integer pos;
 begin word32={bytes[pos+3],bytes[pos+2],bytes[pos+1],bytes[pos]};end
endfunction
function [15:0] word16;
 input integer pos;
 begin word16={bytes[pos+1],bytes[pos]};end
endfunction
task put32;
 input integer pos;input [31:0] value;
 begin bytes[pos]=value;bytes[pos+1]=value>>8;bytes[pos+2]=value>>16;bytes[pos+3]=value>>24;end
endtask
task baseline;
 input integer audio;
 begin
  for(i=0;i<64;i=i+1)bytes[i]=0;
  if(audio)begin
   bytes[0]="S";bytes[1]="X";bytes[2]="A";bytes[3]="U";
   bytes[4]="D";bytes[5]="0";bytes[6]="0";bytes[7]="1";
   put32(8,32'd384004);put32(12,32'd48000);bytes[16]=16;bytes[18]=2;
  end else begin
   bytes[0]="B";bytes[1]="M";put32(2,32'd2764854);put32(10,54);
   put32(14,40);put32(18,1280);put32(22,720);bytes[26]=1;bytes[28]=24;
   put32(38,12345);put32(42,54321);
  end
 end
endtask
task run_case;
 begin
  for(k=0;k<64;k=k+1)begin
   @(negedge clk);index=k;data=bytes[k];valid=1;
   if(k%7==6)begin @(negedge clk);valid=0;end
  end
  @(negedge clk);valid=0;#1;
  reference_magic={bytes[7],bytes[6],bytes[5],bytes[4],bytes[3],bytes[2],bytes[1],bytes[0]};
  if({b,m,dib,planes,bits24,uncompressed,sx,sy} !==
     {bytes[0]==8'h42,bytes[1]==8'h4d,word32(14)>=32'd40,
      word16(26)==16'd1,word16(28)==16'd24,word32(30)==32'd0,
      word32(38)==32'd12345,word32(42)==32'd54321})
   $fatal(1,"BMP predicates mismatch case %0d",cases);
  if(fl!==word32(2) || offset!==word32(10) ||
     width[15:0]!==word16(18) || height[15:0]!==word16(22) ||
     ((width[31:16]==0)!==(word32(18)<65536)) ||
     ((height[31:16]==0)!==(word32(22)<65536)))
   $fatal(1,"Full-width file/offset/geometry mismatch case %0d",cases);
  if(scan_audio)begin
   if({magic,rate,bits16,stereo} !==
      {reference_magic==64'h3130304455415853,word32(12)==32'd48000,
       word16(16)==16'd16,word16(18)==16'd2} || audio_len!==word32(8))
    $fatal(1,"Audio predicates mismatch case %0d",cases);
  end else if({magic,rate,bits16,stereo,audio_len}!==held_audio)
   $fatal(1,"BMP load changed audio metadata");
  cases=cases+1;
 end
endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 for(kind=0;kind<2;kind=kind+1)
  for(j=0;j<46;j=j+1)for(i=0;i<256;i=i+1)begin: mutations
   integer value;value=i;
   // baseline uses i internally; preserve the outer mutation loop variable.
   baseline(kind);i=value;bytes[j]=value;run_case;
  end
 for(j=0;j<2000;j=j+1)begin
  for(i=0;i<64;i=i+1)begin
   random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
   bytes[i]=random_state[7:0];
  end
  run_case;
 end
 baseline(1);run_case;held_audio={magic,rate,bits16,stereo,audio_len};
 scan_audio=0;baseline(0);run_case;
 @(negedge clk);rst=1;@(negedge clk);#1;
 if({b,m,dib,planes,bits24,sx,sy,magic,rate,bits16,stereo,fl,audio_len,width,height}!==0 ||
    offset!==54 || !uncompressed)$fatal(1,"Reset defaults changed");
 $display("PASS %0d independent full-width header references: exhaustive byte mutations, random fields, valid gaps, mode hold, reset",cases);
 $finish;
end
endmodule
