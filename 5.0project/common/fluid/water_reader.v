// The SDRAM IP executes aligned four-word bursts, not per-word random reads.
// Stream sequential rows into a 16-row RAM32K window; displace only on chip.
// Row prefetch overlaps geometry. Two alternating rows hold the second image.
module water_reader #(parameter POINTER_CENTER=0,ADDR_BITS=21,BURST_SIZE=128,FIFO_DEPTH=1024,FRAME_WIDTH=320,HEIGHT=720)(
 input rst,mem_clk,Sdr_init_done,Sdr_init_ref_vld,Sdr_busy,Sdr_rd_en,App_wr_busy,
 input[31:0] Sdr_rd_dout,output O_rd_busy,output App_rd_en,output[ADDR_BITS-1:0] App_rd_addr,
 input read_req,output reg read_req_ack,output read_finish,
 input[ADDR_BITS-1:0] read_addr_0,read_addr_1,read_addr_2,read_addr_3,
 input[1:0] read_addr_index,slide_old_index,slide_new_index,input[ADDR_BITS-1:0] read_len,
 input slide_active,slide_right,input[3:0] transition_mode,input[10:0] slide_offset,
 input[76:0] water_cfg,input force_effect_plane,output reg fifo_aclr,input[10:0] wrusedw,
 output fifo_we,output[31:0] fifo_data,output reg[31:0] read_timeouts,output read_urgent);
localparam IDLE=0,ACK=1,PRIME=2,PRIME_NEW=3,ROW_WAIT=4,ROW_RUN=5,END_FRAME=6,PRIME_NATIVE=7;
localparam M_IDLE=0,M_WAIT=1,M_ARM=2,M_ISSUE=3,M_DRAIN=4;
reg[2:0] state,ms;
reg req0,req1,req2;reg[121:0] c0,c1,cf;
wire[121:0] controls={force_effect_plane,water_cfg,slide_active,slide_right,transition_mode,slide_offset,
 read_addr_index,slide_old_index,slide_new_index,read_len};
always @(posedge mem_clk)begin
 if(rst)begin req0<=0;req1<=0;req2<=0;c0<=0;c1<=0;end
 else begin req0<=read_req;req1<=req0;req2<=req1;c0<=controls;c1<=c0;end
end
wire[76:0] cfg=cf[120:44];wire active=cf[43],right=cf[42];
// Diagnostic selection is committed with the complete frame snapshot. Keep
// the effect texture through the endpoint and dwell for a same-image A/B
// comparison with native scanout; do not compensate using a guessed offset.
wire force_effect=cf[121];
wire[3:0] effect=cf[41:38];wire[10:0] offset=cf[37:27];
// The complete destination is already native while the transition owns it.
// Committing the same image on the following frame cannot change its origin.
wire final_view=active&&cfg[8:0]==256;
wire effect_active=active&&!final_view;
wire blend=effect_active;
reg[20:0] length_q,old_base,new_base,total;
function[20:0] base;input[1:0] n;begin case(n)0:base=read_addr_0;1:base=read_addr_1;2:base=read_addr_2;default:base=read_addr_3;endcase end endfunction
function[20:0] row_address;input[9:0] n;begin row_address=({11'd0,n}<<8)+({11'd0,n}<<6);end endfunction
function[13:0] cache_row;input[3:0] n;begin cache_row=({10'd0,n}<<8)+({10'd0,n}<<6);end endfunction
function[20:0] full_row;input[9:0] n;begin full_row=({11'd0,n}<<9)+({11'd0,n}<<7);end endfunction
wire need_half=force_effect||effect_active||cfg[76]||cfg[75];
reg[9:0] iy,ix,prime_row;reg cadence,run_geometry;
reg[9:0] written;reg[1:0] prefetch_step;reg load_pending;
reg load_start;reg[1:0] load_kind;reg[9:0] load_row;
reg load_done;reg[1:0] fetch_kind;reg[9:0] fetch_row;reg[20:0] fetch_address;
reg[9:0] sent,returned;reg[15:0] watchdog;
assign O_rd_busy=ms==M_ARM||ms==M_ISSUE||ms==M_DRAIN;
assign App_rd_en=ms==M_ISSUE&&!Sdr_init_ref_vld;
assign App_rd_addr=fetch_address;
wire fetch_valid=Sdr_rd_en&&(ms==M_ISSUE||ms==M_DRAIN);
wire[13:0] fetch_cache_address=fetch_kind==2 ? full_row({9'd0,fetch_row[0]})+returned:cache_row(fetch_kind==1 ? {3'd0,fetch_row[0]}:fetch_row[3:0])+returned;
always @(posedge mem_clk)begin
 if(rst)begin
  ms<=M_IDLE;load_done<=0;fetch_kind<=0;fetch_row<=0;fetch_address<=0;
  sent<=0;returned<=0;watchdog<=0;read_timeouts<=0;
 end else begin
  load_done<=0;
  if(ms==M_ISSUE||ms==M_DRAIN)begin
   if(fetch_valid)watchdog<=0;
   else if(watchdog==16'hffff)begin watchdog<=0;read_timeouts<=read_timeouts+1'b1;end
   else watchdog<=watchdog+1'b1;
  end else watchdog<=0;
  if(fetch_valid)returned<=returned+1'b1;
  case(ms)
   M_IDLE:if(load_start)begin
    fetch_row<=load_row;fetch_kind<=load_kind;sent<=0;returned<=0;
    fetch_address<=(load_kind==1||((load_kind==2||force_effect)&&final_view) ? new_base:old_base)+
     (load_kind==2 ? full_row(load_row):HEIGHT*640+row_address(load_row));ms<=M_WAIT;
   end
   M_WAIT:if(!App_wr_busy&&!Sdr_busy&&!Sdr_init_ref_vld)ms<=M_ARM;
   M_ARM:if(App_wr_busy)ms<=M_WAIT;else ms<=M_ISSUE;
   M_ISSUE:if(App_rd_en)begin
    fetch_address<=fetch_address+1'b1;sent<=sent+1'b1;
    if(sent==(fetch_kind==2 ? 640:320)-1)ms<=M_DRAIN;
   end
   M_DRAIN:if(returned==(fetch_kind==2 ? 640:320))begin ms<=M_IDLE;load_done<=1;end
   default:ms<=M_IDLE;
  endcase
 end
end
wire feed=state==ROW_RUN&&run_geometry&&!cadence;
wire warp_valid;wire[9:0] wx,wy,ox,oy;
water_warp warp(.clk(mem_clk),.rst(rst||state==ACK),.valid(feed),.xword({ix[8:0],1'b0}),.y(iy),
 .water_mode(blend&&effect==6),.progress(cfg[8:0]),.drop0(cfg[76]),.drop1(cfg[75]),
 .cx0(cfg[74:64]),.cx1(cfg[63:53]),.cy0(cfg[52:43]),.cy1(cfg[42:33]),
 .radius0(cfg[32:21]),.radius1(cfg[20:9]),.out_valid(warp_valid),.sxword(wx),.sy(wy),.out_xword(ox),.out_y(oy));
wire mapped_valid;wire[9:0] old_x,old_y,new_x,bx,by;wire[8:0] map_alpha;wire[4:0] map_shade;wire[2:0] map_shine;
water_effect_map #(.POINTER_CENTER(POINTER_CENTER)) mapping(.center_x(cfg[74:64]),.center_y(cfg[52:43]),.clk(mem_clk),.rst(rst||state==ACK),.valid(warp_valid),.enabled(effect_active),
 .right(right),.effect(effect),.progress(cfg[8:0]),.ox(ox),.oy(oy),.wx(wx),.wy(wy),
 .out_valid(mapped_valid),.old_x(old_x),.old_y(old_y),.new_x(new_x),.out_x(bx),.out_y(by),
 .alpha(map_alpha),.shade(map_shade),.shine(map_shine));
wire[13:0] old_ra=cache_row(old_y[3:0])+(old_x>>1);
wire[13:0] new_ra=cache_row({3'd0,by[0]})+(new_x>>1);
wire[31:0] cached_old,cached_new;wire[63:0] cached_native;
reg new_half_q;always @(posedge mem_clk)new_half_q<=new_ra[0];
reg new_half_qq;always @(posedge mem_clk)new_half_qq<=new_half_q;
assign cached_new=new_half_qq ? cached_native[31:0]:cached_native[63:32];
water_cache #(.BANKS(3),.TAIL_HALF(1)) old_cache(.clk(mem_clk),.ra(old_ra),.wa(fetch_cache_address),
 .we(fetch_valid&&fetch_kind==0),.wd(Sdr_rd_dout),.rd(cached_old));
// A transition reads the destination half plane; dwell reads the native plane.
// They are never live together. One atomic four-pixel cache serves both modes.
wire[9:0] native_ra=blend ? {1'b0,new_ra[9:1]}:cache_row({3'd0,by[0]})+(bx>>1);
water_native_cache native_cache(.clk(mem_clk),.ra(native_ra),.wa(fetch_cache_address[10:0]),
 .we(fetch_valid&&fetch_kind!=0),.wd(Sdr_rd_dout),.rd(cached_native),
 .rst(rst||state==ACK),.read_valid(mapped_valid));
reg[2:0] cache_valid;reg[8:0] alpha0,alpha1;
reg[7:0] last_q,affected_q;
reg[4:0] shade_q[0:7];reg[2:0] shine_q[0:7];integer light_stage;
reg[63:0] native0,native1,native2,native3,native4,native5;
always @(posedge mem_clk)begin
 if(rst||state==ACK)begin
  cache_valid<=0;alpha0<=0;alpha1<=0;last_q<=0;affected_q<=0;native0<=0;native1<=0;native2<=0;native3<=0;native4<=0;native5<=0;
  for(light_stage=0;light_stage<8;light_stage=light_stage+1)begin shade_q[light_stage]<=0;shine_q[light_stage]<=0;end
 end
 else begin
  cache_valid<={cache_valid[1:0],mapped_valid};alpha0<=map_alpha;alpha1<=alpha0;
  last_q<={last_q[6:0],mapped_valid&&bx==638};
  affected_q<={affected_q[6:0],force_effect||effect_active||(!final_view&&(old_x!=bx||old_y!=by))};
  shade_q[0]<=map_shade;shine_q[0]<=map_shine;
  for(light_stage=1;light_stage<8;light_stage=light_stage+1)begin shade_q[light_stage]<=shade_q[light_stage-1];shine_q[light_stage]<=shine_q[light_stage-1];end
  native0<=cached_native;native1<=native0;native2<=native1;native3<=native2;native4<=native3;native5<=native4;
 end
end
wire blend_valid;wire[31:0] blended;
water_blend mixer(.clk(mem_clk),.rst(rst||state==ACK),.valid(cache_valid[1]),
 .old_word(cached_old),.new_word(blend ? cached_new:32'd0),
 .alpha(blend ? alpha1:9'd0),.out_valid(blend_valid),.word_out(blended));
wire[31:0] illuminated;wire surface_valid;
water_surface_light surface(.clk(mem_clk),.rst(rst||state==ACK),.valid(blend_valid),
 .color_mode(effect_active&&effect==6),.rgb(blended),.shade(shade_q[5]),.shine(shine_q[5]),.out_valid(surface_valid),.lit(illuminated));
wire color_valid,color_last;wire[31:0] color_pixels;
water_color_fringe fringe(.clk(mem_clk),.rst(rst||state==ACK),.enabled(effect_active&&effect==6),
 .valid(surface_valid),.last(last_q[7]),.amount(shine_q[7]),.rgb(illuminated),
 .out_valid(color_valid),.out_last(color_last),.pixels(color_pixels));
wire reconstructed_valid;wire[31:0] reconstructed_word;
water_reconstruct reconstruct(.clk(mem_clk),.rst(rst||state==ACK),.valid(color_valid),
 .last(color_last),.affected(effect_active&&effect==6 ? 1'b1:affected_q[7]),.effect_word(color_pixels),.native_pixels(native5),
 .out_valid(reconstructed_valid),.word_out(reconstructed_word));
assign fifo_we=state==ROW_RUN&&reconstructed_valid;
assign fifo_data=reconstructed_word;
assign read_finish=state==END_FRAME;
// Rows are produced in 640-word batches. A 768-word reserve can therefore
// remain asserted forever and starve the other board's background writes.
// Protect a short scanout reserve, and release the bus while idle/finished.
// Pending row fetches retain priority so a saturated writer cannot postpone
// the next row until the scanout reserve is already empty.
assign read_urgent=!rst&&state!=IDLE&&state!=END_FRAME&&
 (wrusedw<128||load_pending||load_start||ms!=M_IDLE);
always @(posedge mem_clk)begin
 if(rst)begin
  state<=IDLE;read_req_ack<=0;fifo_aclr<=1;cf<=0;length_q<=0;old_base<=0;new_base<=0;total<=0;
  iy<=0;ix<=0;prime_row<=0;cadence<=0;run_geometry<=0;written<=0;
  prefetch_step<=0;load_pending<=0;load_start<=0;load_row<=0;load_kind<=0;
 end else begin
  load_start<=0;
  if(feed)begin if(ix==319)run_geometry<=0;else ix<=ix+1'b1;end
  if(state==ROW_RUN)cadence<=~cadence;else cadence<=0;
  if(fifo_we)written<=written+1'b1;
  case(state)
   IDLE:if(req2&&Sdr_init_done)state<=ACK;
   ACK:begin
    read_req_ack<=1;fifo_aclr<=1;cf<=c1;length_q<=c1[20:0];
    old_base<=base(c1[43] ? c1[24:23]:c1[26:25]);new_base<=base(c1[22:21]);
    iy<=0;ix<=0;prime_row<=0;total<=0;written<=0;run_geometry<=0;load_pending<=0;
    if(!req2)begin state<=need_half ? PRIME:PRIME_NATIVE;read_req_ack<=0;fifo_aclr<=0;end
   end
   PRIME:begin
    if(!load_pending)begin load_start<=1;load_row<=prime_row;load_kind<=0;load_pending<=1;end
    if(load_done)begin
     load_pending<=0;
     if(prime_row==7)state<=effect_active ? PRIME_NEW:force_effect ? ROW_WAIT:PRIME_NATIVE;else prime_row<=prime_row+1'b1;
    end
   end
   PRIME_NEW:begin
    if(!load_pending)begin load_start<=1;load_row<=0;load_kind<=1;load_pending<=1;end
    if(load_done)begin load_pending<=0;state<=ROW_WAIT;end
   end
   PRIME_NATIVE:begin
    if(!load_pending)begin load_start<=1;load_row<=0;load_kind<=2;load_pending<=1;end
    if(load_done)begin load_pending<=0;state<=ROW_WAIT;end
   end
   ROW_WAIT:begin
    if(req2)state<=ACK;
    else if(wrusedw<FIFO_DEPTH-640-32)begin
     state<=ROW_RUN;ix<=0;run_geometry<=1;written<=0;prefetch_step<=0;
    end
   end
   ROW_RUN:begin
    if(!load_pending&&prefetch_step==0)begin
     if(need_half&&iy<HEIGHT-8)begin load_start<=1;load_row<=iy+10'd8;load_kind<=0;load_pending<=1;end
     else prefetch_step<=1;
    end else if(!load_pending&&prefetch_step==1)begin
     if(iy<HEIGHT-1&&(effect_active||!force_effect))begin load_start<=1;load_row<=iy+1'b1;load_kind<=effect_active ? 1:2;load_pending<=1;end
     else prefetch_step<=2;
    end
    if(load_done)begin load_pending<=0;prefetch_step<=prefetch_step+1'b1;end
    if(written==640&&prefetch_step==2&&!load_pending)begin
     total<=total+640;
     if(total+640>=length_q)state<=END_FRAME;
     else begin iy<=iy+1'b1;state<=ROW_WAIT;end
    end
   end
   END_FRAME:state<=IDLE;
   default:state<=IDLE;
  endcase
 end
end
endmodule
