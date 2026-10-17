`timescale 1ns/1ps
// Actual packer -> independent SDRAM planes -> reader/cache/mixer/reconstruction.
// Check the fully revealed low-resolution image BEFORE the native endpoint,
// not just two native frames which necessarily share the same path.
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,pv=0,wreq=0,req=0,active=0,force_effect=0;
reg[23:0] rgb=0;reg[3:0] mode=5;reg[10:0] offset=320;
reg[1:0] current=0,destination=1;reg[76:0] cfg=0;
wire nv,sv,overflow;wire[31:0] nw,sw;
water_pack packer(clk,rst,wreq,pv,rgb,1'b0,nv,nw,overflow,sv,sw);
reg[31:0] full_image[0:20479],half_image[0:10239];
integer fc=0,sc=0,seed=0,cycle=0,k,x,y,fx,dir,received=0,frames=0,checked=0;
function[15:0] source;input integer x,y,s;reg[4:0] r,b;reg[5:0] g;
 begin r=x/37+y*3+s*5;g=(y%2) ? 54-2*(x%24):8+2*(x%24);b=x/71+y*7+s*9;source={r,g,b};end
endfunction
function[15:0] filtered;input integer x,y,s;reg[15:0] a,b,c;integer r,g,bl;
 begin a=source(x==0 ? 0:x-1,y,s);b=source(x,y,s);c=source(x+1,y,s);
 r=((a>>11)+2*(b>>11)+(c>>11)+2)/4;
 g=(((a>>5)&63)+2*((b>>5)&63)+((c>>5)&63)+2)/4;
 bl=((a&31)+2*(b&31)+(c&31)+2)/4;filtered=(r<<11)|(g<<5)|bl;end
endfunction
function[15:0] avg;input[15:0] a,b;integer r,g,bl;
 begin r=((a>>11)+(b>>11)+1)/2;g=(((a>>5)&63)+((b>>5)&63)+1)/2;bl=((a&31)+(b&31)+1)/2;avg=(r<<11)|(g<<5)|bl;end
endfunction
function[15:0] effect_pixel;input integer x,y,s;
 begin effect_pixel=x%2 ? avg(filtered(x-1,y,s),filtered(x==1279 ? 1278:x+1,y,s)):filtered(x,y,s);end
endfunction
function[31:0] memory_word;input integer address;integer s,a;
 begin s=address>=691200;a=address-s*691200;
 memory_word=a>=460800 ? half_image[s*5120+a-460800]:full_image[s*10240+a];end
endfunction
always @(posedge clk)begin
 if(nv)begin full_image[seed*10240+fc]=nw;fc=fc+1;end
 if(sv)begin half_image[seed*5120+sc]=sw;sc=sc+1;end
end
wire ack,done,re,we,busy,clear;wire[20:0] address;wire[31:0] data,timeouts;
reg[13:0] val=0;reg[20:0] aq[0:13];
water_reader dut(.rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .Sdr_rd_en(val[13]),.Sdr_rd_dout(memory_word(aq[13])),.App_wr_busy(cycle%1024<40),.O_rd_busy(busy),.App_rd_en(re),.App_rd_addr(address),
 .read_req(req),.read_req_ack(ack),.read_finish(done),.read_addr_0(21'd0),.read_addr_1(21'd691200),.read_addr_2(21'd0),.read_addr_3(21'd1382400),
 .read_addr_index(current),.slide_old_index(current),.slide_new_index(destination),.read_len(21'd1280),
 .slide_active(active),.slide_right(dir[0]),.transition_mode(mode),.slide_offset(offset),.water_cfg(cfg),.force_effect_plane(force_effect),
 .fifo_aclr(clear),.wrusedw(11'd0),.fifo_we(we),.fifo_data(data),.read_timeouts(timeouts));
sdram_contract contract(clk,rst,re,address);
reg expect_half=0;integer expected_slot=0;reg[31:0] expected;
always @(posedge clk)begin
 cycle=cycle+1;val<={val[12:0],re};aq[0]<=address;for(k=1;k<14;k=k+1)aq[k]<=aq[k-1];
 if(we)begin
  if(expect_half)expected={effect_pixel(2*(received%640),received/640,expected_slot),effect_pixel(2*(received%640)+1,received/640,expected_slot)};
  else expected={source(2*(received%640),received/640,expected_slot),source(2*(received%640)+1,received/640,expected_slot)};
  if(data!==expected)$fatal(1,"origin mismatch frame%0d mode%0d force%b active%b offset%0d word%0d got%h expected%h",frames,mode,force_effect,active,offset,received,data,expected);
  received=received+1;checked=checked+2;
 end
end
task frame;begin
 received=0;repeat(8)@(negedge clk);req=1;wait(ack);@(negedge clk);req=0;wait(done);@(negedge clk);
 if(received!=1280)$fatal(1,"origin frame length");frames=frames+1;
end endtask
reg[15:0] p;
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(seed=0;seed<2;seed=seed+1)begin
  fc=0;sc=0;wreq=1;@(negedge clk);wreq=0;
  for(y=0;y<16;y=y+1)for(x=0;x<1280;x=x+1)begin
   p=source(x,y,seed);rgb={p[15:11],3'd0,p[10:5],2'd0,p[4:0],3'd0};pv=1;@(negedge clk);pv=0;@(negedge clk);
  end
  repeat(4)@(negedge clk);if(fc!=10240||sc!=5120||overflow)$fatal(1,"packer count");
 end
 for(dir=0;dir<2;dir=dir+1)begin
  current=dir;destination=1-dir;expected_slot=destination;
  // The curl front has left the screen at progress 248, before native handoff.
  mode=0;cfg=77'd248;active=1;offset=320;force_effect=0;expect_half=1;frame;
  offset=640;cfg=77'd256;expect_half=0;frame;active=0;current=destination;frame;
  // Force the SAME effect plane through the endpoint and ownership commit.
  for(fx=0;fx<11;fx=fx+1)begin
   current=dir;destination=1-dir;mode=fx;cfg=77'd256;active=1;offset=640;force_effect=1;expect_half=1;frame;
   active=0;current=destination;frame;
   // Toggle A/B without changing the image, then return to effect scanout.
   force_effect=0;expect_half=0;frame;force_effect=1;expect_half=1;frame;
  end
 end
 if(timeouts)$fatal(1,"origin read timeout");
 $display("PASS origin: %0d exact pixels in %0d frames through actual packer, SDRAM planes, reader caches and reconstruction; pre-end effect/native/commit plus eleven-effect forced-plane endpoint/commit and same-image A/B in both slot directions",checked,frames);$finish;
end
initial begin #24000000;$fatal(1,"origin timeout");end
endmodule
