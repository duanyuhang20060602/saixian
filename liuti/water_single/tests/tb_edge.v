module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,de=0,sof=0,eol=0;reg[10:0] x;reg[9:0] y;reg[23:0] rgb;reg[5:0] darkness;
wire od,os,ol;wire[23:0] out_rgb;wire[7:0] level;
water_edge d(.clk(clk),.rst(rst),.frame_tick(1'b0),.music_drive(1'b1),.pcm_valid(1'b0),.pcm_left(16'sd0),.pcm_right(16'sd0),
 .x(x),.y(y),.de(de),.sof(sof),.eol(eol),.rgb(rgb),.darkness(darkness),.de_out(od),.sof_out(os),.eol_out(ol),.rgb_out(out_rgb),.level(level));
integer f,z,i,n,head=0,tail=0;reg[23:0] expected[0:4095];reg[2:0] flags[0:4095];
integer xx,yy,rr,gg,bb,dark,ee,ss,ll;reg[23:0] out_value;
reg started=0;
always @(posedge clk)begin #1;
 if(started&&od)begin
  if(head>=tail||out_rgb!==expected[head]||{od,os,ol}!==flags[head])$fatal(1,"edge/DE alignment head%0d got%h expected%h flags%b/%b",head,out_rgb,expected[head],{od,os,ol},flags[head]);
  head=head+1;
 end
end
initial begin
 force d.level=8'd128;
 f=$fopen("edge_vectors.txt","r");z=$fscanf(f,"%d",n);repeat(4)@(negedge clk);rst=0;started=1;
 for(i=0;i<n;i=i+1)begin
  @(negedge clk);z=$fscanf(f,"%d %d %h %d %d %d %h",xx,yy,rgb,dark,ss,ll,out_value);
  x=xx;y=yy;darkness=dark;de=1;sof=ss;eol=ll;expected[tail]=out_value;flags[tail]={1'b1,ss[0],ll[0]};tail=tail+1;
 end
 @(negedge clk);de=0;sof=0;eol=0;repeat(12)@(negedge clk);
 if(head!=tail)$fatal(1,"edge valid count mismatch");
 $display("PASS edge light RGB, black fade, SOF/EOL matched for %0d pixels",head);$finish;
end
endmodule
