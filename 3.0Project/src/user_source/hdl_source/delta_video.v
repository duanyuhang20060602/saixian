module delta_video #(parameter SHOW_BOOT_SPINNER=0,parameter MIN_BOOT_FRAMES=0)(
 input clk,input rst,input publish_toggle,input publish_slot,
 input [31:0] head,input empty,output pop,
 output reg [23:0] rgb,output reg de_out,output reg vs_out,
 output reg commit_toggle,output reg frame_toggle,output reg active_slot,
 output reg display_valid,output reg underrun_latched
);
(* async_reg="true",keep="true" *)reg [2:0] publish_sync;
(* async_reg="true",keep="true" *)reg slot_meta,slot_sync;
reg [10:0] h;reg [9:0] v;reg frame_bad;
wire frame_tick=h==0 && v==0;
wire de=h>=260 && h<1540 && v>=25 && v<745;
wire scene=display_valid && h>=660 && h<1140 && v>=145 && v<625;
assign pop=scene && h[0] && !frame_bad && !empty;
wire [15:0] pixel=h[0] ? head[31:16] : head[15:0];
wire [23:0] expanded={pixel[15:11],pixel[15:13],pixel[10:5],pixel[10:9],pixel[4:0],pixel[4:2]};
wire [23:0] boot_rgb;wire boot_done;
delta_boot_spinner #(.MIN_FRAMES(MIN_BOOT_FRAMES)) boot(clk,rst,frame_tick,h,v,boot_rgb,boot_done);
always @(posedge clk)begin
 if(rst)begin h<=0;v<=0;publish_sync<=0;slot_meta<=0;slot_sync<=0;
  commit_toggle<=0;frame_toggle<=0;active_slot<=0;display_valid<=0;
  frame_bad<=0;underrun_latched<=0;rgb<=0;de_out<=0;vs_out<=0;end
 else begin
  publish_sync<={publish_sync[1:0],publish_toggle};slot_meta<=publish_slot;slot_sync<=slot_meta;
  if(h==1649)begin h<=0;if(v==749)v<=0;else v<=v+1'b1;end else h<=h+1'b1;
  if(frame_tick)begin
   frame_toggle<=~frame_toggle;frame_bad<=0;
   if(publish_sync[2]!=commit_toggle && (display_valid || boot_done))begin
    active_slot<=slot_sync;display_valid<=1;commit_toggle<=publish_sync[2];
   end
  end
  if(scene && empty)begin frame_bad<=1;underrun_latched<=1;end
  rgb<=!display_valid && SHOW_BOOT_SPINNER ? boot_rgb :
       scene && !frame_bad && !empty ? expanded : 24'd0;
  de_out<=de;vs_out<=v<5;
 end
end
endmodule

// A procedural spinner independent of TF, SDRAM and the frame FIFO.
// Centers use the production raster coordinates (active origin 260,25).
module delta_boot_spinner #(parameter MIN_FRAMES=96)(
 input clk,input rst,input frame_tick,input [10:0] h,input [9:0] v,
 output reg [23:0] rgb,output done
);
reg [6:0] frames;reg [2:0] subframe,phase;
assign done=frames>=MIN_FRAMES;
always @(posedge clk)begin
 if(rst)begin frames<=0;subframe<=0;phase<=0;end
 else if(frame_tick)begin
  if(!done)frames<=frames+1'b1;
  if(subframe==5)begin subframe<=0;phase<=phase+1'b1;end else subframe<=subframe+1'b1;
 end
end
reg hit;reg [2:0] dot;
always @*begin
 hit=1;dot=0;
 if(h>=892 && h<908 && v>=337 && v<353)dot=0;
 else if(h>=920 && h<936 && v>=349 && v<365)dot=1;
 else if(h>=932 && h<948 && v>=377 && v<393)dot=2;
 else if(h>=920 && h<936 && v>=405 && v<421)dot=3;
 else if(h>=892 && h<908 && v>=417 && v<433)dot=4;
 else if(h>=864 && h<880 && v>=405 && v<421)dot=5;
 else if(h>=852 && h<868 && v>=377 && v<393)dot=6;
 else if(h>=864 && h<880 && v>=349 && v<365)dot=7;
 else hit=0;
 rgb=hit ? (dot==phase ? 24'hffffff : 24'h404040) : 24'd0;
end
endmodule
