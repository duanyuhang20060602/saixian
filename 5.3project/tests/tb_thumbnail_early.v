`timescale 1ns/1ps
module tb_thumbnail_early;
reg clk=0,mem_clk=0;always #7 clk=~clk;always #10 mem_clk=~mem_clk;
reg rst=1,next=0,transition=0,commit=0;
reg [1:0] active_slot=0;wire [1:0] new_slot;
wire cv,request,cancel,done,read_busy,visible;
wire [1:0] cache_slot,slot;wire [2:0] image_id;
wire [11:0] address;wire [15:0] data;
integer vc=0,mc=0,requests=0,reads=0,i,requests_at_ready;
always @(posedge clk)begin vc<=vc+1;if(!rst && request!=last_request)requests<=requests+1;last_request<=request;end
reg last_request=0;
wire frame_tick=vc%2000==0;
wire blank=mc%2000>=1400;
wire mem_request,claim,read_command;wire [20:0] mem_address;
reg [9:0] responses=0;reg [31:0] response[0:9];
always @(posedge mem_clk)begin
 mc<=mc+1;responses<={responses[8:0],read_command};
 if(read_command)begin response[0]<={mem_address[15:0],mem_address[15:0]};reads<=reads+1;end
 for(i=1;i<10;i=i+1)response[i]<=response[i-1];
end
photo_cached_control_a #(.FLUID(1),.CHECK_FRAME_CRC(1),.EARLY_THUMBNAIL(1)) ctrl(
 .clk(clk),.rst(rst),.uart_rx(1'b1),.settings_mode(1'b0),.settings_state(19'd0),.award_toggle(1'b0),.previous(1'b0),.next(next),
 .active_slot(active_slot),.new_slot(new_slot),.transition_active(transition),.commit_toggle(commit),
 .rx_armed(1'b0),.rx_done(1'b0),.rx_fault(1'b0),.rx_crc(32'd0),.ready_slot(new_slot),
 .thumbnail_valid(cv),.thumbnail_slot(cache_slot),.thumbnail_id(image_id),.thumbnail_read_busy(read_busy),.thumbnail_read_slot(slot));
photo_thumbnail_overlay #(.SEPARATE_DISPLAY(1)) overlay(
 .clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(1'b1),.display_enable(!transition && !ctrl.display_pending),
 .cache_valid(cv),.cache_slot(cache_slot),.identity({1'b0,image_id,cache_slot}),.de(1'b0),.x(12'd0),.y(11'd0),
 .request(request),.slot(slot),.cancel(cancel),.done(done),.data(data),.address(address),
 .visible(visible),.rgb_in(24'd0),.rgb_out(),.read_busy(read_busy));
photo_thumbnail_memory memory(
 .clk(mem_clk),.rst(rst),.init_done(1'b1),.refresh(1'b0),.busy(1'b0),.frame_busy(1'b0),.allow_access(1'b1),.other_request(1'b0),
 .request(mem_request),.claim(claim),.read_command(read_command),.address(mem_address),.response_valid(responses[9]),.response(response[9]),
 .video_clk(clk),.video_request(request),.video_cancel(cancel),.video_blank(blank),.video_slot(slot),.video_done(done),.video_address(address),.video_data(data));
task click;begin @(negedge clk);next=1;@(negedge clk);next=0;end endtask
task settle;begin repeat(8)@(negedge clk);end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 @(negedge clk);ctrl.state_flags=16'd4;ctrl.have_current=1;ctrl.current_image=0;ctrl.image_count=3;
 ctrl.cache_valid=7;ctrl.cache_id[0]=0;ctrl.cache_id[1]=1;ctrl.cache_id[2]=2;
 ctrl.cache_width[0]=1280;ctrl.cache_width[1]=1280;ctrl.cache_width[2]=1280;
 wait(visible);if(slot!=1)$fatal(1,"initial preview source wrong");
 click();wait(ctrl.display_pending);@(negedge clk);transition=1;
 wait(overlay.pending && slot==2);
 if(!cv || visible)$fatal(1,"preparation blocked or preview shown during transition");
 wait(overlay.ready);settle();requests_at_ready=requests;
 if(!transition || visible || cancel)$fatal(1,"early preview completion was not held hidden");
 // The old active/display_pending context changes, but the next identity is
 // unchanged. Do not cancel or reload the completed thumbnail at commit.
 @(negedge clk);active_slot=new_slot;transition=0;commit=~commit;
 wait(visible);settle();
 if(requests!=requests_at_ready || slot!=2 || !overlay.ready)$fatal(1,"commit discarded prepared thumbnail");
 // Pin a different valid source and force an urgent cache miss. The victim
 // decoder and registered plan must not pick the in-flight preview source.
 @(negedge clk);force ctrl.thumbnail_read_busy=1'b1;force ctrl.thumbnail_read_slot=2'd2;
 ctrl.nav_target=4;ctrl.nav_pending=1;ctrl.image_count=6;
 settle();
 if(ctrl.victim_ok && ctrl.victim==2)$fatal(1,"locked preview source selected as victim");
 if(ctrl.plan_ok && ctrl.plan_victim==2)$fatal(1,"locked source reached receive plan");
 release ctrl.thumbnail_read_busy;release ctrl.thumbnail_read_slot;
 $display("PASS early preview: real 2304-pixel memory completes during hidden transition; same identity survives commit without reread; source-slot victim lock");
 $finish;
end
initial begin #30000000;$fatal(1,"early preview timeout state=%d pending=%d ready=%d cv=%d",memory.state,overlay.pending,overlay.ready,cv);end
endmodule
