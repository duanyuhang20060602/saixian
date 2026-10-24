// Native 1280x720 RGB565 pair scanout. No horizontal resampling here.
module water_expand(input video_clk,rst,output read_en,input[31:0] read_data,
 input read_empty,display_valid,output reg underflow_latched,
 input hs,vs,de,output hs_r,vs_r,de_r,output[23:0] vout_data);
reg[20:0] hs_d,vs_d,de_d;reg fetch_phase,out_phase,word_ok,frame_fault,previous_vs;
reg[31:0] pair;reg[23:0] rgb;
assign hs_r=hs_d[20];assign vs_r=vs_d[20];assign de_r=de_d[20];assign vout_data=rgb;
wire want=de_d[17]&&!fetch_phase&&display_valid&&!frame_fault;
assign read_en=want&&!read_empty;
wire[15:0] p=out_phase ? pair[15:0]:pair[31:16];
always @(posedge video_clk or posedge rst)begin
 if(rst)begin hs_d<=0;vs_d<=0;de_d<=0;fetch_phase<=0;out_phase<=0;word_ok<=0;frame_fault<=0;previous_vs<=0;pair<=0;rgb<=0;underflow_latched<=0;end
 else begin
  hs_d<={hs_d[19:0],hs};vs_d<={vs_d[19:0],vs};de_d<={de_d[19:0],de};
  previous_vs<=vs_d[17];word_ok<=read_en;
  if(previous_vs&&!vs_d[17])frame_fault<=0;
  else if(want&&read_empty)begin frame_fault<=1;underflow_latched<=1;end
  if(!de_d[17])fetch_phase<=0;else fetch_phase<=~fetch_phase;
  if(word_ok)pair<=read_data;
  if(!de_d[19])begin out_phase<=0;rgb<=0;end
  else begin
   out_phase<=~out_phase;
   if(!display_valid||frame_fault)rgb<=0;
   else rgb<={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};
  end
 end
end
endmodule
