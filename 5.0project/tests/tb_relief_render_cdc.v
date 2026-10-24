`timescale 1ns/1ps
// Isolate the production renderer's clock-domain routing with adversarial,
// continuously pending clients. The production four-word arbiter is unchanged.
module tb #(parameter PHASE_PS=0, RESPONSE_CLOCKS=12);
reg mc=0,pc=0,rst=1,mode=0,run=1;
always #5 mc=~mc;
initial begin #(PHASE_PS/1000.0);forever #6.667 pc=~pc;end
integer cycle=0,pixel_cycle=0;
reg [15:0] mode_pattern=16'hace1;
always @(negedge pc)begin
 if(rst)begin pixel_cycle=0;mode=0;mode_pattern=16'hace1;end
 else begin
  pixel_cycle=pixel_cycle+1;
  mode_pattern={mode_pattern[14:0],mode_pattern[15]^mode_pattern[13]^mode_pattern[12]^mode_pattern[10]};
  mode=mode_pattern[0];
 end
end
wire request,ack,valid,claim,rd;
wire [20:0] address,ra;wire [31:0] data;
wire [23:0] rgb,menu;wire [3:0] error;wire [6:0] frame;
reg [RESPONSE_CLOCKS-1:0] pipe=0;
reg [31:0] response[0:RESPONSE_CLOCKS-1];integer i;
wire busy=|pipe;
wire refresh=(cycle%53)<3,frame_busy=(cycle%31)<7;
photo_award_render #(.RELIEF_ENABLE(1)) dut(
 .relief_mode(mode),.touch_contact(1'b0),.cursor_x(11'd640),.cursor_y(10'd360),
 .mem_clk(mc),.mem_rst(rst),.light_base(21'h03000),.light_request(request),.light_address(address),
 .light_ack(ack),.light_data(data),.light_valid(valid),.de_in(1'b0),.clk(pc),.rst(rst),.enable(1'b1),
 .pause(1'b0),.frame_tick(1'b0),.x(11'd0),.y(10'd0),.tagged_rgb(24'd0),
 .rgb(rgb),.menu_rgb(menu),.light_error(error),.light_frame(frame));
photo_award_memory bus(.clk(mc),.rst(rst),.enable(run),.init_done(1'b1),.refresh(refresh),.busy(busy),.frame_busy(frame_busy),
 .request(request),.address(address),.acknowledge(ack),.data(data),.valid(valid),.claim(claim),.read_command(rd),.read_address(ra),
 .response_valid(pipe[RESPONSE_CLOCKS-1]),.response(response[RESPONSE_CLOCKS-1]));
integer grants=0,old_grants=0,new_grants=0,issued=0,received=0,words=0;
integer ack_transition=0,data_other_mode=0,old_during_new=0,new_during_old=0;
reg owner=0,have_grant=0;reg [20:0] grant_address=0;
always @(posedge mc)begin
 cycle=cycle+1;
 pipe<=(pipe<<1)|rd;
 if(rd)response[0]<=32'h5a000000|{11'd0,ra};
 for(i=1;i<RESPONSE_CLOCKS;i=i+1)response[i]<=response[i-1];
 if(rst)pipe<=0;
 else begin
  // Check at the actual consumer sampling edge, before nonblocking updates.
  if(ack)begin
   if(have_grant && (received!=4 || issued!=4))$fatal(1,"previous burst incomplete %0d/%0d",issued,received);
   if(ra!==21'h13000 && ra!==21'h23000)$fatal(1,"address was not a complete client address %h",ra);
   owner=ra==21'h23000;grant_address=ra;received=0;issued=0;have_grant=1;grants=grants+1;
   if(owner)new_grants=new_grants+1;else old_grants=old_grants+1;
   if(dut.gold.player.ack!==owner || dut.lights.stream_ack!==!owner)$fatal(1,"registered ACK crossed clients owner=%b mode=%b synchronized=%b",owner,mode,dut.relief_mem);
   if(dut.relief_mem!=dut.route_d)ack_transition=ack_transition+1;
  end else if(dut.gold.player.ack || dut.lights.stream_ack)$fatal(1,"spurious client ACK");
  if(rd)begin
   if(!claim || !have_grant || ra!==grant_address+issued || issued>=4)$fatal(1,"native read changed transaction owner/address");
   issued=issued+1;
  end
  if(valid)begin
   if(!have_grant || received>=4)$fatal(1,"unexpected response word");
   if(dut.gold.player.valid!==owner || dut.lights.data_valid!==!owner)$fatal(1,"four-word response crossed clients owner=%b mode=%b",owner,mode);
   if(data!==(32'h5a000000|{11'd0,grant_address+received}))$fatal(1,"response reordered or corrupted %h",data);
   received=received+1;words=words+1;
   if(dut.relief_mem!=owner)begin
    data_other_mode=data_other_mode+1;
    if(owner)new_during_old=new_during_old+1;else old_during_new=old_during_new+1;
   end
  end else if(dut.gold.player.valid || dut.lights.data_valid)$fatal(1,"spurious client valid");
 end
end
initial begin
 repeat(8)@(negedge mc);rst=0;
 repeat(5000)@(negedge mc);run=0;
 wait(!claim && !busy);repeat(5)@(negedge mc);
 if(received!=4 || issued!=4 || words!=grants*4)$fatal(1,"incomplete final burst");
 if(old_grants<20 || new_grants<20 || ack_transition<5 || old_during_new<40 || new_during_old<40 || pixel_cycle<1000)
  $fatal(1,"insufficient switching coverage grants=%0d/%0d ack-edge=%0d other-mode=%0d/%0d",old_grants,new_grants,ack_transition,old_during_new,new_during_old);
 $display("PASS renderer CDC routing phase_ps=%0d latency=%0d: %0d grants/%0d words, %0d ACK-edge mode changes, %0d words returned during opposite mode",PHASE_PS,RESPONSE_CLOCKS,grants,words,ack_transition,data_other_mode);$finish;
end
initial begin #1000000;$fatal(1,"CDC routing timeout");end
endmodule

// Requests intentionally remain pending through mode changes so routing is
// checked independently of either player's reset/enable cancellation policy.
module photo_relief_player #(parameter SHARED_PALETTE=0)(input mem_clk,mem_rst,enable,input [20:0]base,
 output request,output [20:0]address,input ack,input [31:0]data,input valid,
 input clk,rst,pause,frame_tick,de,input[10:0]x,input[9:0]y,input[23:0]rgb_in,
 input touch_contact,input[10:0]cursor_x,input[9:0]cursor_y,output[23:0]rgb_out,output[3:0]error,output[4:0]angle,output cache_write_en,output[7:0]cache_write_address,output[31:0]cache_write_data,output[7:0]cache_read_address,input[31:0]cache_read_data);
assign cache_write_en=0;assign cache_write_address=0;assign cache_write_data=0;assign cache_read_address=0;
assign request=!mem_rst;assign address=base+21'h20000;assign rgb_out=rgb_in;assign error=0;assign angle=0;
endmodule
module photo_spotlight_player #(parameter SHARED_CACHE=0)(input mem_clk,mem_rst,enable,input[20:0]base,
 output stream_start,output[20:0]stream_offset,input stream_ack,input[31:0]data,input data_valid,
 output[3:0]error,input video_clk,video_rst,display_valid,pause,input[23:0]rgb_in,input de_in,vs_in,
 output[23:0]rgb_out,output de_out,vs_out,output[6:0]frame_index,output initialized,output cache_write_en,output[8:0]cache_write_address,output[31:0]cache_write_data,output[8:0]cache_read_address,input[31:0]cache_read_data);
assign cache_write_en=0;assign cache_write_address=0;assign cache_write_data=0;assign cache_read_address=0;
assign stream_start=!mem_rst;assign stream_offset=base+21'h10000;assign error=0;
assign rgb_out=rgb_in;assign de_out=de_in;assign vs_out=vs_in;assign frame_index=0;assign initialized=1;
endmodule
module award_fx #(parameter INITIAL_HOLD_FRAMES=0)(input clk,rst,enable,pause,frame_tick,input[10:0]x,input[9:0]y,input[23:0]base_rgb,input[5:0]tag,output[23:0]rgb);
assign rgb=base_rgb;
endmodule
module photo_award_delay(input clk,rst,input[23:0]rgb_in,output[23:0]rgb,menu_rgb);
assign rgb=rgb_in;assign menu_rgb=rgb_in;
endmodule

module photo_relief_ram #(parameter DATA_BITS=32,ADDRESS_BITS=8,DEPTH=256)(input wc,we,input[ADDRESS_BITS-1:0]wa,input[DATA_BITS-1:0]wd,input rc,input[ADDRESS_BITS-1:0]ra,output reg[DATA_BITS-1:0]rd);
reg[DATA_BITS-1:0]memory[0:DEPTH-1];always @(posedge wc)if(we)memory[wa]<=wd;always @(posedge rc)rd<=memory[ra];
endmodule
