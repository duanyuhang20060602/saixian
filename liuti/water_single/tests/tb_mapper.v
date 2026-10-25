module tb;
reg[10:0] x,offset;reg[9:0] y;reg right;reg[2:0] effect;
wire[20:0] original,compact;
mapper_2_0_reference reference(.xpos(x),.ypos(y),.old_base(21'h10000),.new_base(21'h100000),
 .enabled(1'b1),.move_right(right),.effect(effect),.offset(offset),.address(original));
saixian_frame_mapper #(.COLUMN_SHIFT(1)) dut(.xpos(x),.ypos(y),.old_base(21'h10000),.new_base(21'h100000),
 .enabled(1'b1),.move_right(right),.effect(effect),.offset(offset),.address(compact));
integer i,fx,dir,px,endpoint,n=0;reg[20:0] expected;
task check;begin
 #1;expected=(original&21'h1ffc00)|((original&21'h3ff)>>1);
 if(compact!==expected||original[9:0]>639)$fatal(1,"2.0 transition mismatch fx%0d offset%0d xy%0d,%0d",effect,offset,x,y);
 n=n+1;
end endtask
initial begin
 for(fx=0;fx<6;fx=fx+1)for(dir=0;dir<2;dir=dir+1)for(endpoint=0;endpoint<2;endpoint=endpoint+1)for(px=0;px<320;px=px+1)begin
  effect=fx;right=dir;offset=endpoint*640;x=px*2;y=719;check;
  if(compact!==(endpoint ? 21'h100000:21'h10000)+px)$fatal(1,"transition endpoint is not complete");
 end
 for(i=0;i<50000;i=i+1)begin
  effect=i%6;right=(i/6)%2;offset=(i*37)%641;x=((i*197)%320)*2;y=(i*113)%720;check;
 end
 $display("PASS %0d transition addresses: six original 2.0 effects, both directions, complete endpoints and compact framebuffer columns",n);$finish;
end
endmodule
