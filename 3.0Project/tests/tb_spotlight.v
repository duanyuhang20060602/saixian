`timescale 1ns/1ps
module tb_spotlight;
reg mc=0,vc=0;always #10 mc=~mc;always #7 vc=~vc;
reg rst=1,enable=0,display=0,pause=0,de=0,vs=0;
reg [23:0] rgb=24'h503820;
wire req,pop,initialized,ode,ovs;wire [20:0] offset,length;
reg ack=0,valid=0;reg [20:0] pointer,left;reg [31:0] memory[0:900000];
wire [31:0] data=memory[pointer];wire [3:0] error;wire [6:0] index;wire [23:0] out;
integer bus_cycles=0;wire offered=valid && bus_cycles%11<8;
integer file_words,bad=0,i,j,k,saved_index,saved_step,checks=0;string package_path;
spotlight_player dut(mc,rst,enable,file_words[20:0],req,offset,length,ack,data,offered,pop,error,
 vc,rst,display,pause,rgb,de,vs,out,ode,ovs,index,initialized);
always @(posedge mc)begin
 bus_cycles<=bus_cycles+1;
 if(rst)begin ack<=0;valid<=0;pointer<=0;left<=0;end
 else begin
  if(req && !ack && !valid)begin ack<=1;pointer<=offset;left<=length;end
  if(ack && !req)begin ack<=0;valid<=1;end
  if(valid && pop)begin pointer<=pointer+1;left<=left-1;if(left==1)valid<=0;end
 end
end
function [7:0] lit;
 input [7:0] c,t,a;integer product;
 begin product=(t>c ? t-c : 0)*a;lit=c+(product/256);end
endfunction
function [7:0] map_byte;
 input integer frame_id,x,y;reg [31:0] w;integer n;
 begin n=y*160+x;w=memory[memory[memory[65]+frame_id*4]+n/4];map_byte=w>>((n%4)*8);end
endfunction
function integer threshold;
 input integer x,y;
 begin threshold=((x%2)^(y%2))*128+(y%2)*64+(((x/2)%2)^((y/2)%2))*32+((y/2)%2)*16+8;end
endfunction
function [7:0] spatial;
 input integer frame_id,x,y;integer lx,rx,uy,ly,fx,fy,top,bottom;
 begin
  lx=x<4?0:(x-4)/8;uy=y<4?0:(y-4)/8;
  if(lx>159)lx=159;if(uy>89)uy=89;rx=lx<159?lx+1:lx;ly=uy<89?uy+1:uy;
  fx=x<4?0:(x-4)%8;fy=y<4?0:(y-4)%8;
  top=map_byte(frame_id,lx,uy)*(8-fx)+map_byte(frame_id,rx,uy)*fx;
  bottom=map_byte(frame_id,lx,ly)*(8-fx)+map_byte(frame_id,rx,ly)*fx;
  spatial=(top*(8-fy)+bottom*fy+threshold(x,y)/4)/64;
 end
endfunction
reg [23:0] expected[0:6];reg [6:0] expected_de=0,expected_vs=0;
integer px=0,py=0,cell_n,word_n,oracle_phase=0;reg [7:0] alpha;reg [31:0] word;
reg checking=0,previous_de=0;
always @(posedge vc)begin
 if(rst)begin px=0;py=0;previous_de=0;expected_de=0;expected_vs=0;expected[0]=0;expected[1]=0;expected[2]=0;expected[3]=0;expected[4]=0;expected[5]=0;expected[6]=0;end
 else if(checking)begin
  expected[6]=expected[5];expected[5]=expected[4];expected[4]=expected[3];expected[3]=expected[2];expected[2]=expected[1];expected[1]=expected[0];
  alpha=(spatial(0,px,py)*(256-oracle_phase)+spatial(1,px,py)*oracle_phase+threshold(px,py))/256;
  if(!de || py>=548)alpha=0;
  expected[0]={lit(rgb[23:16],255,alpha),lit(rgb[15:8],235,alpha),lit(rgb[7:0],200,alpha)};
  expected_de={expected_de[5:0],de};expected_vs={expected_vs[5:0],vs};
  if(vs)py=0;else if(previous_de && !de)py=py+1;
  if(de)px=px+1;else px=0;previous_de=de;
  #1;
  if(ode!==expected_de[6] || ovs!==expected_vs[6])$fatal(1,"RGB/DE/VS alignment");
  if(ode)begin if(out!==expected[6])$fatal(1,"light pixel mismatch %h %h",out,expected[6]);checks=checks+1;end
 end
end
task tick;begin @(negedge vc);vs=1;repeat(3)@(negedge vc);vs=0;repeat(8000)@(negedge vc);end endtask
initial begin
 if(!$value$plusargs("package=%s",package_path)||!$value$plusargs("words=%d",file_words))$fatal;
 if($value$plusargs("bad=%d",bad))begin end
 $readmemh(package_path,memory,0,file_words-1);
 if(bad==1)memory[memory[memory[65]]]=memory[memory[memory[65]]]^1;
 if(bad==2)memory[memory[65]+1]=0;
 if(bad==3)memory[66]=3599;
 repeat(8)@(negedge mc);rst=0;enable=1;
 if(bad!=0)begin
  wait(error!=0);repeat(8)@(negedge vc);
  if(initialized || error!=(bad==1?3:bad==3?1:2))$fatal(1,"bad light data published or wrong error %d",error);
  $display("PASS light rejection case %d: corrupt metadata/descriptor/CRC not published",bad);$finish;
 end
 wait(initialized);display=1;tick;repeat(7)@(negedge vc);checking=1;
 // Cover all packed byte lanes and every row, including protected title.
 for(j=0;j<720;j=j+1)begin
  @(negedge vc);de=1;
  for(i=0;i<1280;i=i+1)begin @(negedge vc);rgb=24'h503820;end
  de=0;repeat(370)@(negedge vc);
 end
 repeat(370)@(negedge vc);checking=0;
 if(checks<10000)$fatal(1,"insufficient pixel coverage");
 repeat(60)tick;
 for(k=1;k<=720;k=k+1)begin
  tick;
  if(index!=(k/6)%120 || dut.step!=k%6)$fatal(1,"missed light frame deadline tick=%d index=%d step=%d",k,index,dut.step);
  if(!dut.next_ready)$fatal(1,"next frame missed 112us refill budget");
  if(error!=0)$fatal(1,"light loop error");
 end
 pause=1;repeat(8)@(negedge vc);saved_index=index;saved_step=dut.step;repeat(20)tick;
 if(index!=saved_index || dut.step!=saved_step)$fatal(1,"light pause did not freeze");
 pause=0;repeat(8)@(negedge vc);wait(dut.next_ready);tick;
 if(index==saved_index && dut.step==saved_step)$fatal(1,"light resume failed");
 // Verify a nonzero temporal phase against an independent pixel oracle.
 if(index!=0 || dut.step!=1)$fatal(1,"unexpected resumed frame phase");
 repeat(10)@(negedge vc);px=0;py=0;previous_de=0;expected_de=0;expected_vs=0;oracle_phase=43;checking=1;
 for(j=0;j<16;j=j+1)begin
  @(negedge vc);de=1;
  for(i=0;i<1280;i=i+1)@(negedge vc);
  de=0;repeat(370)@(negedge vc);
 end
 repeat(10)@(negedge vc);checking=0;

 $display("PASS spotlight: 120 CRC-checked frames, 720 uninterrupted display ticks with stalled producer, full loop, pause/resume, %d exact RGB pixels, title protection and 7-stage spatial/temporal DE/VS alignment",checks);$finish;
end
initial begin #200000000;$fatal(1,"spotlight timeout");end
endmodule
