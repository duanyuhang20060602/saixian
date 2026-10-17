// Music features are measured from final played PCM. The edge envelope is
// smoothed at frame boundaries and never drives the water-wave scheduler.
module water_edge(input clk,rst,frame_tick,music_drive,pcm_valid,
 input signed[15:0] pcm_left,pcm_right,input[10:0] x,input[9:0] y,
 input de,sof,eol,input[23:0] rgb,input[5:0] darkness,
 output reg de_out,sof_out,eol_out,output reg[23:0] rgb_out,output reg[7:0] level);
reg[18:0] envelope;wire signed[16:0] sum=$signed({pcm_left[15],pcm_left})+$signed({pcm_right[15],pcm_right});
wire signed[16:0] mono=sum>>>1;wire[16:0] magnitude=mono<0 ? -mono:mono;
reg[15:0] breathe;
wire[7:0] target=envelope>8191 ? 8'd255:envelope[12:5];
always @(posedge clk)begin
 if(rst)begin envelope<=0;breathe<=0;level<=0;end
 else begin
  if(pcm_valid)begin
   if(magnitude>envelope)envelope<=envelope+((magnitude-envelope)>>6);
   else envelope<=envelope-((envelope-magnitude)>>10);
  end
  if(frame_tick)begin
   if({target,8'd0}>breathe)breathe<=breathe+(({target,8'd0}-breathe)>>3);
   else breathe<=breathe-((breathe-{target,8'd0})>>4);
   level<=music_drive ? breathe[15:8]:8'd0;
  end
 end
end
wire[10:0] right_dist=x<1280 ? 11'd1279-x:11'd0;
wire[9:0] bottom_dist=y<720 ? 10'd719-y:10'd0;
wire[10:0] xd=x<right_dist ? x:right_dist;
wire[10:0] yd={1'b0,y}<bottom_dist ? {1'b0,y}:{1'b0,bottom_dist};
wire[10:0] distance=xd<yd ? xd:yd;
reg[7:0] edge_rom[0:127];initial $readmemh("water_edge.hex",edge_rom);
reg[7:0] weight;reg[23:0] rgb0,rgb1,rgb2;reg[5:0] dark0,dark1,dark2;
reg[15:0] energy;reg[3:0] dq,sq,lq;reg[8:0] red,green,blue;
wire[7:0] amount=energy[15:8];
// Bounded 0..48-level blue/cyan edge light, added after source sampling.
wire[8:0] add_r={1'b0,rgb1[23:16]}+({1'b0,amount}>>3);
wire[8:0] add_g={1'b0,rgb1[15:8]}+({1'b0,amount}>>2);
wire[8:0] add_b={1'b0,rgb1[7:0]}+({1'b0,amount}>>1);
reg[15:0] pr,pg,pb;
function[15:0] dark_channel;input[7:0] c;input[5:0] d;reg[15:0] loss;
 begin
 loss=(d[0] ? {8'd0,c}:16'd0)+(d[1] ? {7'd0,c,1'b0}:16'd0)+
      (d[2] ? {6'd0,c,2'd0}:16'd0)+(d[3] ? {5'd0,c,3'd0}:16'd0)+
      (d[4] ? {4'd0,c,4'd0}:16'd0)+(d[5] ? {3'd0,c,5'd0}:16'd0);
 dark_channel={3'd0,c,5'd0}-loss;
 end
endfunction
function signed[15:0] edge_product; input signed[8:0] aa; input[7:0] b; reg signed[15:0] a; begin
a={{7{aa[8]}},aa};
edge_product=((((b[0] ? ($signed(a) <<< 0) : 16'sd0)+(b[1] ? ($signed(a) <<< 1) : 16'sd0))+((b[2] ? ($signed(a) <<< 2) : 16'sd0)+(b[3] ? ($signed(a) <<< 3) : 16'sd0)))+(((b[4] ? ($signed(a) <<< 4) : 16'sd0)+(b[5] ? ($signed(a) <<< 5) : 16'sd0))+((b[6] ? ($signed(a) <<< 6) : 16'sd0)+(b[7] ? ($signed(a) <<< 7) : 16'sd0))));
end endfunction
always @(posedge clk)begin
 weight<=distance<76 ? edge_rom[distance[6:0]]:8'd0;rgb0<=rgb;dark0<=darkness;
 energy<=edge_product($signed({1'b0,weight}),level);rgb1<=rgb0;dark1<=dark0;
 rgb2<={add_r[8]?8'hff:add_r[7:0],add_g[8]?8'hff:add_g[7:0],add_b[8]?8'hff:add_b[7:0]};dark2<=dark1;
 // Fade-to-black applies to the whole composited picture, including edge light.
 pr<=dark_channel(rgb2[23:16],dark2);pg<=dark_channel(rgb2[15:8],dark2);pb<=dark_channel(rgb2[7:0],dark2);
 rgb_out<={pr[12:5],pg[12:5],pb[12:5]};
 dq<={dq[2:0],de};sq<={sq[2:0],sof};lq<={lq[2:0],eol};
 de_out<=dq[3];sof_out<=sq[3];eol_out<=lq[3];
 if(rst)begin dq<=0;sq<=0;lq<=0;de_out<=0;sof_out<=0;eol_out<=0;rgb_out<=0;end
end
endmodule
