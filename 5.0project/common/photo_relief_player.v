// SXDLT006: 256 surface entries, then 24 192x192 indexed rotation views.
// Two small eRAMs hold the palette and two scanlines. Full-resolution wall
// normals arrive in the existing framebuffer. Input-to-output latency: 12.
module photo_relief_player #(parameter HOLD_FRAMES=5,SHARED_PALETTE=0)(
 input mem_clk,mem_rst,enable,input [20:0] base,
 output reg request,output reg [20:0] address,input ack,
 input [31:0] data,input valid,
 input clk,rst,pause,frame_tick,de,input [10:0] x,input [9:0] y,
 input [23:0] rgb_in,input touch_contact,input [10:0] cursor_x,input [9:0] cursor_y,
 output [23:0] rgb_out,output [3:0] error,output [4:0] angle,
 output cache_write_en,output [7:0] cache_write_address,output [31:0] cache_write_data,
 output [7:0] cache_read_address,input [31:0] cache_read_data
);
wire signed [5:0] light_x,light_y;wire frame_update;
photo_relief_motion #(.HOLD_FRAMES(HOLD_FRAMES)) motion(.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(frame_tick),
 .touch_contact(touch_contact),.cursor_x(cursor_x),.cursor_y(cursor_y),
 .angle(angle),.light_x(light_x),.light_y(light_y),.frame_update(frame_update));

reg request_toggle;reg [4:0] requested_angle;reg [7:0] requested_row;
(* async_reg="true" *)reg enable_meta,enable_sync;
(* async_reg="true" *)reg [2:0] request_sync;
(* async_reg="true" *)reg [4:0] angle_meta;reg [4:0] angle_sync;
(* async_reg="true" *)reg [7:0] row_meta;reg [7:0] row_sync;
reg done_toggle,palette_ready,seen;
reg [2:0] state;localparam INIT=0,ASK=1,READ=2,IDLE=3,DRAIN=4;
reg palette_job,job_bank;reg [7:0] position;reg [1:0] lane;
reg [20:0] burst_address;
reg [63:0] upper_halfwords;
// A four-word SDRAM response is consecutive. Write its low halfwords
// immediately, then drain the four saved high halves during bus recovery.
always @(posedge mem_clk)
 if((state==READ && valid && !palette_job) || state==DRAIN)
  upper_halfwords<={data[31:16],upper_halfwords[63:16]};
always @(posedge mem_clk or posedge mem_rst)begin
 if(mem_rst)begin enable_meta<=0;enable_sync<=0;end
 else begin enable_meta<=enable;enable_sync<=enable_meta;end
end
always @(posedge mem_clk)begin
 request_sync<={request_sync[1:0],request_toggle};
 angle_meta<=requested_angle;angle_sync<=angle_meta;
 row_meta<=requested_row;row_sync<=row_meta;
 if(mem_rst || !enable_sync)begin
  request_sync<=0;angle_meta<=0;angle_sync<=0;row_meta<=0;row_sync<=0;
  done_toggle<=0;palette_ready<=0;seen<=0;state<=INIT;request<=0;
  address<=0;burst_address<=0;palette_job<=1;job_bank<=0;position<=0;lane<=0;
 end else case(state)
 INIT:begin palette_job<=1;position<=0;burst_address<=base;state<=ASK;end
 ASK:begin
  address<=burst_address;request<=1;
  if(ack)begin request<=0;lane<=0;state<=READ;end
 end
 READ:if(valid)begin
  position<=position+1'b1;lane<=lane+1'b1;
  if(lane==3)begin
   if(!palette_job)begin state<=DRAIN;lane<=0;end
   else if(position==255)begin state<=IDLE;palette_ready<=1;end
   else begin burst_address<=burst_address+4;state<=ASK;end
  end
 end
 DRAIN:begin
  lane<=lane+1'b1;
  if(lane==3)begin
   if(position==48)begin state<=IDLE;done_toggle<=seen;end
   else begin burst_address<=burst_address+4;state<=ASK;end
  end
 end
 IDLE:if(request_sync[2]!=seen)begin
  seen<=request_sync[2];palette_job<=0;job_bank<=row_sync[0];position<=0;
  burst_address<=base+21'd256+({16'd0,angle_sync}<<13)+({16'd0,angle_sync}<<10)+
   ({13'd0,row_sync}<<5)+({13'd0,row_sync}<<4);
  state<=ASK;
 end
 endcase
end
wire palette_we=enable_sync && state==READ && valid && palette_job;
wire row_we=enable_sync && ((state==READ && valid && !palette_job) || state==DRAIN);
wire [3:0] drained_block=position[5:2]-4'd1;
wire [7:0] row_write_address=state==DRAIN ? {job_bank,drained_block,lane,1'b1}:
 {job_bank,position[5:0],1'b0};
wire [15:0] row_write_data=state==DRAIN ? upper_halfwords[15:0]:data[15:0];

(* async_reg="true" *)reg [2:0] done_sync,ready_sync;
reg pending,started;reg [1:0] row_valid;reg [7:0] row_tag0,row_tag1;
reg [7:0] source_row,source_column;reg [1:0] repeat_y,repeat_x;
reg [3:0] video_error;
assign error=video_error;
wire in_sprite=de && x>=352 && x<928 && y>=48 && y<624;
wire row_good=row_valid[source_row[0]] && (source_row[0] ? row_tag1:row_tag0)==source_row;
always @(posedge clk)begin
 done_sync<={done_sync[1:0],done_toggle};ready_sync<={ready_sync[1:0],palette_ready};
 if(rst || !enable)begin
  done_sync<=0;ready_sync<=0;pending<=0;started<=0;request_toggle<=0;
  requested_angle<=0;requested_row<=0;row_valid<=0;row_tag0<=0;row_tag1<=0;
  source_row<=0;source_column<=0;repeat_y<=0;repeat_x<=0;video_error<=0;
 end else begin
  if(pending && done_sync[2]==request_toggle)begin
   pending<=0;row_valid[requested_row[0]]<=1;
   if(requested_row[0])row_tag1<=requested_row;else row_tag0<=requested_row;
  end
  if(!in_sprite)begin source_column<=0;repeat_x<=0;end
  else if(repeat_x==2)begin repeat_x<=0;source_column<=source_column+1'b1;end
  else repeat_x<=repeat_x+1'b1;
  if(x==0)begin
   if(y<=48)begin source_row<=0;repeat_y<=0;end
   else if(y<624)begin
    if(repeat_y==2)begin repeat_y<=0;source_row<=source_row+1'b1;end
    else repeat_y<=repeat_y+1'b1;
   end
  end
  if(frame_update)begin
   started<=1;
   if(pending)video_error<=1;
   else begin
    requested_angle<=angle;requested_row<=0;request_toggle<=~request_toggle;
    pending<=1;row_valid<=0;
   end
  end else if(started && x==0 && (y==48 || (y>48 && y<621 && repeat_y==2)))begin
   if(pending)video_error<=2;
   else begin
    requested_row<=y==48 ? 8'd1:source_row+8'd2;
    request_toggle<=~request_toggle;pending<=1;
    row_valid[y==48 ? 1'b1:source_row[0]]<=0;
   end
  end
  if(started && de && x==352 && y>=48 && y<624 && ready_sync[2] && !row_good)video_error<=3;
 end
end

wire [15:0] row_word;wire [31:0] palette_word;reg [7:0] token;
reg byte_lane;reg [2:0] inside_pipe;
reg [15:0] bg0,bg1,bg2;
wire [15:0] raw={rgb_in[23:19],rgb_in[15:10],rgb_in[7:3]};
photo_relief_ram #(.DATA_BITS(16),.ADDRESS_BITS(8),.DEPTH(256)) rows(
 .wc(mem_clk),.we(row_we),.wa(row_write_address),.wd(row_write_data),
 .rc(clk),.ra({source_row[0],source_column[7:1]}),.rd(row_word));
assign cache_write_en=palette_we;assign cache_write_address=position;assign cache_write_data=data;
assign cache_read_address=token;
generate if(!SHARED_PALETTE)begin:private_palette
 photo_relief_ram #(.ADDRESS_BITS(8),.DEPTH(256)) palette(
 .wc(mem_clk),.we(palette_we),.wa(position),.wd(data),
 .rc(clk),.ra(token),.rd(palette_word));
end else begin:external_palette
 assign palette_word=cache_read_data;
end endgenerate
always @(posedge clk)begin
 byte_lane<=source_column[0];token<=row_word>>(byte_lane*8);
 bg0<=raw;bg1<=bg0;bg2<=bg1;
 inside_pipe<={inside_pipe[1:0],in_sprite && row_good && ready_sync[2] && enable};
 if(rst)begin inside_pipe<=0;token<=0;byte_lane<=0;bg0<=0;bg1<=0;bg2<=0;end
end
wire cup=inside_pipe[2] && palette_word[0];
wire [15:0] surface=cup ? palette_word[15:0]:bg2;
wire [15:0] base_color=cup ? palette_word[31:16]:bg2;
function [23:0] expand;input [15:0] p;begin
 expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end endfunction
// Two native DSP output registers keep the original stage-4 product latency.
function [7:0] sat;input [8:0] a;begin sat=a[8]?8'd255:a[7:0];end endfunction
reg signed [5:0] nx,ny;reg [4:0] nz;
reg [23:0] color3,color4,color5,color6;
reg [3:0] wall_pipe,cup_pipe;
wire signed [11:0] px,py;reg [9:0] pz;
photo_relief_product product_x(.clk(clk),.rst(rst),.a(nx),.b(light_x),.p(px));
photo_relief_product product_y(.clk(clk),.rst(rst),.a(ny),.b(light_y),.p(py));
reg signed [12:0] dot,half_dot;
reg [7:0] diffuse,specular;reg back;
wire signed [12:0] sum=$signed({px[11],px})+$signed({py[11],py})+$signed({3'b000,pz});
reg [23:0] shaded,delay8,delay9,delay10,delay11;
always @(posedge clk)begin
 // Stage 3: palette and background meet after the two synchronous RAM reads.
 nx<=$signed({surface[15:11],1'b0});ny<=$signed({surface[10:6],1'b0});nz<=surface[5:1];
 color3<=expand(base_color);wall_pipe<={wall_pipe[2:0],!cup && bg2[0]};cup_pipe<={cup_pipe[2:0],cup};
 // Stage 4.
 pz<={nz,4'b0000};color4<=color3;
 // Stage 5.
 dot<=sum;half_dot<=sum+$signed({3'b000,pz});color5<=color4;
 // Stage 6.
 diffuse<=dot<0 ? 8'd0:dot>1020 ? 8'd255:dot[9:2];
 specular<=half_dot<=960 ? 8'd0:half_dot>=1087 ? 8'd255:(half_dot-13'sd960)<<1;
 back<=dot<0;color6<=color5;
 // Stage 7: rough antique wall and polished gold cup use different response.
 if(wall_pipe[3])shaded<={8'd24+{1'b0,diffuse[7:1]},8'd12+{2'b00,diffuse[7:2]},8'd3+{4'b0000,diffuse[7:4]}};
 else if(cup_pipe[3])shaded<={
  sat({1'b0,color6[23:16]}-(back?{3'b000,color6[23:18]}:9'd0)+{2'b00,specular[7:1]}),
  sat({1'b0,color6[15:8]}-(back?{3'b000,color6[15:10]}:9'd0)+{3'b000,specular[7:2]}),
  sat({1'b0,color6[7:0]}-(back?{3'b000,color6[7:2]}:9'd0)+{4'b0000,specular[7:3]})};
 else shaded<=color6;
 // Stages 8..11 preserve the shared award menu/HDMI taps.
 delay8<=shaded;delay9<=delay8;delay10<=delay9;delay11<=delay10;
 if(rst)begin
  nx<=0;ny<=0;nz<=0;color3<=0;color4<=0;color5<=0;color6<=0;
  wall_pipe<=0;cup_pipe<=0;pz<=0;dot<=0;half_dot<=0;
  diffuse<=0;specular<=0;back<=0;shaded<=0;delay8<=0;delay9<=0;delay10<=0;delay11<=0;
 end
end
assign rgb_out=delay11;
endmodule

module photo_relief_ram #(parameter DATA_BITS=32,ADDRESS_BITS=8,DEPTH=256)(
 input wc,we,input [ADDRESS_BITS-1:0] wa,input [DATA_BITS-1:0] wd,
 input rc,input [ADDRESS_BITS-1:0] ra,output [DATA_BITS-1:0] rd
);
`ifdef RELIEF_SIM
reg [DATA_BITS-1:0] memory[0:DEPTH-1];reg [DATA_BITS-1:0] q;
always @(posedge wc)if(we)memory[wa]<=wd;
always @(posedge rc)q<=memory[ra];
assign rd=q;
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(DATA_BITS),.ADDR_WIDTH_A(ADDRESS_BITS),.DATA_DEPTH_A(DEPTH),
 .DATA_WIDTH_B(DATA_BITS),.ADDR_WIDTH_B(ADDRESS_BITS),.DATA_DEPTH_B(DEPTH),.BYTE_ENABLE(0),
 .MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),
 .WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) memory(
 .clka(wc),.rsta(1'b0),.cea(1'b1),.wea(we),.ocea(1'b1),.bea(1'b0),.addra(wa),.dia(wd),.doa(),
 .clkb(rc),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b1),.beb(1'b0),.addrb(ra),.dib({DATA_BITS{1'b0}}),.dob(rd));
`endif
endmodule


// Signed 6x6 product, exactly one registered clock and synchronous reset.
// RELIEF_NATIVE_DSP lets functional tests use the installed vendor model
// while keeping the compact RTL model for ordinary Icarus regressions.
module photo_relief_product(input clk,rst,input signed [5:0] a,b,output signed [11:0] p);
`ifdef RELIEF_SIM
`ifdef RELIEF_NATIVE_DSP
localparam NATIVE=1;
`else
localparam NATIVE=0;
`endif
`else
localparam NATIVE=1;
`endif
generate if(NATIVE)begin:native
 wire [35:0] wide;
 EG_PHY_MULT18 #(.INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),
  .OUTPUTREG("ENABLE"),.SRMODE("SYNC")) multiply(
  .a({{12{a[5]}},a}),.b({{12{b[5]}},b}),.p(wide),.signeda(1'b1),.signedb(1'b1),
  .acin(18'd0),.bcin(18'd0),.sourcea(1'b1),.sourceb(1'b1),.acout(),.bcout(),
  .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.clk(clk),.rstan(1'b1),.rstbn(1'b1),.rstpdn(!rst));
 assign p=wide[11:0];
end else begin:simulation
 reg signed [11:0] product;
 always @(posedge clk)if(rst)product<=0;else product<=a*b;
 assign p=product;
end endgenerate
endmodule
