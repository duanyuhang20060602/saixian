`timescale 1ns/1ps
module tb_spotlight;
reg mc=0,vc=0;always #10 mc=~mc;always #7 vc=~vc;
reg rst=1,enable=0,display=0,pause=0,de=0,vs=0;
reg [23:0] rgb=24'h503820;
wire req,pop,initialized,ode,ovs;wire [20:0] offset,length;
reg ack=0,valid=0;reg [20:0] pointer,left;reg [31:0] memory[0:900000];reg [11:0] high_addresses[0:2719];
wire [31:0] data=memory[pointer];wire [3:0] error;wire [6:0] index;wire [23:0] out;
integer bad=0;integer bus_cycles=0;wire offered=valid && bus_cycles%11<8 && !(bad==6 && dut.startup_done);
integer file_words,i,j,k,saved_index,saved_step,checks=0;string package_path;
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
integer px=0,py=0,cell_n,word_n,oracle_phase=0,oracle_frame=0;reg [7:0] alpha;reg [31:0] word;
reg checking=0,previous_de=0;
always @(posedge vc)begin
 if(rst)begin px=0;py=0;previous_de=0;expected_de=0;expected_vs=0;expected[0]=0;expected[1]=0;expected[2]=0;expected[3]=0;expected[4]=0;expected[5]=0;expected[6]=0;end
 else if(checking)begin
  expected[6]=expected[5];expected[5]=expected[4];expected[4]=expected[3];expected[3]=expected[2];expected[2]=expected[1];expected[1]=expected[0];
  alpha=(spatial(oracle_frame,px,py)*(256-oracle_phase)+spatial((oracle_frame+1)%120,px,py)*oracle_phase+threshold(px,py))/256;
  if(!de || py>=548)alpha=0;
  expected[0]={lit(rgb[23:16],255,alpha),lit(rgb[15:8],235,alpha),lit(rgb[7:0],200,alpha)};
  expected_de={expected_de[5:0],de};expected_vs={expected_vs[5:0],vs};
  if(vs)py=0;else if(previous_de && !de)py=py+1;
  if(de)px=px+1;else px=0;previous_de=de;
  #1;
  if(ode!==expected_de[6] || ovs!==expected_vs[6])$fatal(1,"RGB/DE/VS alignment");
  if(ode)begin if(out!==expected[6])$fatal(1,"light pixel mismatch %h %h near input x=%d y=%d top0=%h bottom0=%h",out,expected[6],px,py,dut.top_row[0],dut.bottom_row[0]);checks=checks+1;end
 end
end
task tick;begin @(negedge vc);vs=1;repeat(3)@(negedge vc);vs=0;repeat(8000)@(negedge vc);end endtask
integer stored_checks=0;
task check_stored_bank;
 input integer bank,field;
 integer n,row,address;reg [31:0] got,expected_word;
 begin
  for(row=0;row<3;row=row+1)for(n=0;n<40;n=n+1)begin
   address=row*64+n;
   expected_word=memory[memory[memory[65]+field*4]+row*40+n];
   got=bank ? dut.row_bank1[address] : dut.row_bank0[address];
   if(got!==expected_word)$fatal(1,"rolling row storage differs bank=%d field=%d row=%d word=%d",bank,field,row,n);
   stored_checks=stored_checks+1;
  end
 end
endtask
initial begin
 if(!$value$plusargs("package=%s",package_path)||!$value$plusargs("words=%d",file_words))$fatal;
 if($value$plusargs("bad=%d",bad))begin end
 $readmemh(package_path,memory,0,file_words-1);
 $readmemh("tests/fixtures/high_addresses.hex",high_addresses);
 if(bad==1)memory[memory[memory[65]]]=memory[memory[memory[65]]]^1;
 if(bad==2)memory[memory[65]+1]=0;
 if(bad==3)memory[66]=3599;
 if(bad==4)memory[memory[memory[65]]+2720]=1;
 if(bad==5)begin
  i=0;while(high_addresses[i]!=4095)i=i+1;
  memory[memory[memory[65]]+i]=memory[memory[memory[65]]+i]|32'h80808080;
 end
 if(bad==7)memory[memory[memory[65]+119*4]+100]^=1;
 if(bad==8)memory[memory[65]+119*4]-=128;
 repeat(8)@(negedge mc);rst=0;enable=1;
 if(bad==6)begin
  wait(dut.startup_done);repeat(8)@(negedge vc);display=1;tick;
  @(negedge vc);de=1;repeat(20)@(negedge vc);de=0;
  wait(error!=0);repeat(10)@(negedge vc);
  if(error!=7 || !initialized || !dut.video_error)$fatal(1,"missing-row deadline not diagnosed");
  $display("PASS row deadline: stalled initial SDRAM fetch diagnosed as error 7; no stale light publication");$finish;
 end
 if(bad!=0)begin
  wait(error!=0);repeat(8)@(negedge vc);
  if(initialized || error!=(bad==1 || bad==7?3:bad==3?1:bad==4?5:bad==5?3:2))$fatal(1,"bad light data published or wrong error %d",error);
  $display("PASS light rejection case %d: corrupt metadata/descriptor/CRC not published",bad);$finish;
 end
 wait(dut.startup_done);repeat(8)@(negedge vc);
 display=1;tick;wait(initialized);wait(dut.next_ready);check_stored_bank(0,0);check_stored_bank(1,1);repeat(7)@(negedge vc);
 for(i=0;i<40;i=i+1)begin
  if(dut.top_row[i][31:0]!==memory[memory[memory[65]]+i])
   $fatal(1,"prefetch row0 word=%d got=%h expected=%h",i,dut.top_row[i][31:0],memory[memory[memory[65]]+i]);
 end
 checking=1;
 // Cover all packed byte lanes and every row, including protected title.
 for(j=0;j<720;j=j+1)begin
  @(negedge vc);de=1;
  for(i=0;i<1280;i=i+1)begin @(negedge vc);rgb=24'h503820;end
  de=0;repeat(370)@(negedge vc);
 end
 repeat(370)@(negedge vc);checking=0;
 if(checks<10000)$fatal(1,"insufficient pixel coverage");
 repeat(60)tick;
 for(k=1;k<=360;k=k+1)begin
  tick;
  if(index!=(k/3)%120 || dut.step!=k%3)$fatal(1,"missed light frame deadline tick=%d index=%d step=%d",k,index,dut.step);
  if(!dut.next_ready)$fatal(1,"next frame missed initial-row refill budget");
  if(k%3==0)begin
   check_stored_bank(0,index);
   check_stored_bank(1,(index+1)%120);
  end
  // The focused field contains nonzero sparse MSBs. Check its complete
  // raster independently, in addition to the fan-out field checked above.
  if(k==180)begin
   px=0;py=0;previous_de=0;expected_de=0;expected_vs=0;
   oracle_frame=60;oracle_phase=0;checking=1;
   for(j=0;j<720;j=j+1)begin
    @(negedge vc);de=1;
    for(i=0;i<1280;i=i+1)@(negedge vc);
    de=0;repeat(370)@(negedge vc);
   end
   repeat(10)@(negedge vc);checking=0;oracle_frame=0;
  end
  if(error!=0)$fatal(1,"light loop error");
 end
 pause=1;repeat(8)@(negedge vc);saved_index=index;saved_step=dut.step;repeat(20)tick;
 if(index!=saved_index || dut.step!=saved_step)$fatal(1,"light pause did not freeze");
 pause=0;repeat(8)@(negedge vc);wait(dut.next_ready);tick;
 if(index==saved_index && dut.step==saved_step)$fatal(1,"light resume failed");
 // Verify a nonzero temporal phase against an independent pixel oracle.
 if(index!=0 || dut.step!=1)$fatal(1,"unexpected resumed frame phase");
 repeat(10)@(negedge vc);px=0;py=0;previous_de=0;expected_de=0;expected_vs=0;oracle_phase=85;checking=1;
 for(j=0;j<16;j=j+1)begin
  @(negedge vc);de=1;
  for(i=0;i<1280;i=i+1)@(negedge vc);
  de=0;repeat(370)@(negedge vc);
 end
 repeat(10)@(negedge vc);checking=0;

 $display("PASS spotlight: 120 CRC-checked frames, 360 uninterrupted display ticks at 2x speed with stalled producer and rolling SDRAM rows, full loop, pause/resume, %d exact RGB pixels and %d exact full-precision rolling row words, title protection and 7-stage spatial/temporal DE/VS alignment",checks,stored_checks);$finish;
end
initial begin #200000000;$fatal(1,"spotlight timeout");end
endmodule
