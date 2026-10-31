`timescale 1ns/1ps
module tb;wire map_complete;wire match_active,match_busy;reg frame=0;
wire rb,rf,re,rwv;wire[2:0] ri;wire[3:0] rl;wire[15:0] rt;wire[8:0] rwi;wire[31:0] rwd;
wire text_active,text_can_start,text_byte_valid,text_timeout,text_request,text_reply,text_reply_error;
wire [7:0] text_byte,text_tag,text_bank_length,text_character,text_reply_tag,text_reply_position;wire [13:0] text_code;
wire text_load,text_clear,text_ready,text_failed,text_consume,font_req;wire [13:0] font_code;wire [31:0] text_word,font_addr;
reg ac=0,bc=0;always #7 ac=~ac;always #5 bc=~bc;always @(posedge ac)frame<=!frame;
wire [7:0] title_address;integer title_writes=0;
always @(posedge ac)if(a.title_word_valid)title_writes=title_writes+1;
reg rst=1,award_toggle=0;reg [18:0] settings={1'b0,4'd4,4'd4,4'd4,2'd1,2'd1,1'b0,1'b0};
wire at,bt,high_color,format_changed,arm_t,abort_t,start_t,abort_b,ready_t,immediate,fluid,receive_award,updating;
wire [1:0] receive_slot,ready_slot,transmit_slot;reg [1:0] active_slot=0;reg commit=0,seen_ready=0;
wire [2:0] current,count,target;wire [15:0] width,height;wire [3:0] ae,be;wire abusy,bbusy;
wire request,release_media,cancel;reg media_ready=0;reg [2:0] locked=0;integer load_delay=0;
wire [18:0] b_settings;wire tx_done,rx_done;reg finished_toggle=0;reg previous_start=0;integer transfer_delay=0,transfers=0,award_requests=0,begins=0;
photo_event_sync finish_a(.clk(ac),.rst(rst),.toggle(finished_toggle),.pulse(rx_done));
photo_event_sync finish_b(.clk(bc),.rst(rst),.toggle(finished_toggle),.pulse(tx_done));
always @(posedge bc)begin
 if(rst)begin media_ready<=0;load_delay<=0;previous_start<=0;finished_toggle<=0;transfer_delay<=0;end
 else begin
  if(request)begin locked<=target;load_delay<=8;media_ready<=0;end
  if(load_delay>0)begin load_delay<=load_delay-1;if(load_delay==1)media_ready<=1;end
  if(release_media || cancel)media_ready<=0;
  previous_start<=start_t;
  if(start_t!=previous_start)transfer_delay<=20;
  if(transfer_delay>0)begin transfer_delay<=transfer_delay-1;if(transfer_delay==1)begin finished_toggle<=~finished_toggle;transfers<=transfers+1;end end
  if(b.got && b.kind==3 && b.incoming[98:96]==6)begin
   if(b.incoming[87:56]!=2764800 || b.incoming[93]!=0)$fatal(1,"award request still uses legacy plate length/plane");
   award_requests=award_requests+1;
  end
 end
end
always @(posedge ac)begin
 if(rst)begin active_slot<=0;commit<=0;seen_ready<=0;end
 else begin
  if(ready_t!=seen_ready)begin seen_ready<=ready_t;active_slot<=ready_slot;commit<=~commit;end
  if(a.got && a.kind==4 && a.incoming[98:96]==6)begin
   if(a.incoming[87:56]!=2764800 || a.incoming[93]!=0 || !a.incoming[55])$fatal(1,"award BEGIN metadata is incompatible");
   begins=begins+1;
  end
 end
end
photo_cached_control_a #(.RANK_TEXT(1),.INDEPENDENT_TEXT(1),.TITLE_SD(1),.CLK_HZ(806400),.SETTINGS_LINK(1),.AWARD_CONTROL(1),.FLUID(1),.AWARD_LIGHTS(1),.CHECK_FRAME_CRC(1)) a(
 .rank_word_valid(rwv),.rank_word_index(rwi),.rank_word_data(rwd),.text_request(text_request),.text_tag(text_tag),.text_bank_length(text_bank_length),.text_character(text_character),.text_code(text_code),.text_reply(text_reply),.text_reply_tag(text_reply_tag),.text_reply_position(text_reply_position),.text_reply_error(text_reply_error),
 .receive_award(receive_award),.receive_fluid(fluid),.settings_mode(1'b1),.settings_state(settings),.settings_updating(updating),
 .award_toggle(award_toggle),.clk(ac),.rst(rst),.uart_rx(bt),.uart_tx(at),.previous(1'b0),.next(1'b0),
 .active_slot(active_slot),.new_slot(2'd0),.transition_active(1'b0),.commit_toggle(commit),.receive_slot(receive_slot),.arm_toggle(arm_t),.abort_toggle(abort_t),
 .rx_armed(1'b1),.rx_done(rx_done),.rx_fault(1'b0),.rx_crc(32'hacbd1234),.ready_immediate(immediate),.ready_toggle(ready_t),.ready_slot(ready_slot),
 .image_count(count),.current_image(current),.busy(abusy),.error(ae),.current_source_width(width),.current_source_height(height));
photo_cached_control_a_before_match #(.INDEPENDENT_TEXT(1),.TITLE_SD(1),.CLK_HZ(806400),.SETTINGS_LINK(1),.AWARD_CONTROL(1),.FLUID(1),.AWARD_LIGHTS(1),.CHECK_FRAME_CRC(1)) reference_a(
.text_request(a.text_request),
.text_tag(a.text_tag),
.text_bank_length(a.text_bank_length),
.text_character(a.text_character),
.text_code(a.text_code),
.settings_mode(a.settings_mode),
.settings_state(a.settings_state),
.award_toggle(a.award_toggle),
.relief_toggle(a.relief_toggle),
.clk(a.clk),
.rst(a.rst),
.uart_rx(a.uart_rx),
.previous(a.previous),
.next(a.next),
.active_slot(a.active_slot),
.new_slot(a.new_slot),
.transition_active(a.transition_active),
.commit_toggle(a.commit_toggle),
.rx_armed(a.rx_armed),
.rx_done(a.rx_done),
.rx_fault(a.rx_fault),
.rx_crc(a.rx_crc),
.thumbnail_read_busy(a.thumbnail_read_busy),
.thumbnail_read_slot(a.thumbnail_read_slot));
always @(posedge ac)if(!rst)begin
 #1;
 if({a.state_flags,a.timer,a.send,a.message,a.image_count,a.current_image,a.error,a.ready_toggle,a.arm_toggle,a.abort_toggle}!==
    {reference_a.state_flags,reference_a.timer,reference_a.send,reference_a.message,reference_a.image_count,reference_a.current_image,reference_a.error,reference_a.ready_toggle,reference_a.arm_toggle,reference_a.abort_toggle})
  $fatal(1,"A UART predicate staging changed original controller cycle");
end
photo_control_b #(.INDEPENDENT_TEXT(1),.TITLE_SD(0),.CLK_HZ(1152000),.SETTINGS_LINK(1),.SEND_SOURCE_SIZE(1),.AWARD_CONTROL(1),.FLUID(1),.AWARD_LIGHTS(1),.CHECK_FRAME_CRC(1)) b(
 .text_load(text_load),.text_code(font_code),.text_clear(text_clear),.text_ready(text_ready),.text_failed(text_failed),.text_word(text_word),.text_consume(text_consume),
 .title_ready(1'b0),.title_length(5'd0),.title_data(32'd0),.title_address(title_address),
 .award_available(1'b1),.award_scan_complete(1'b1),.clk(bc),.rst(rst),.uart_rx(at),.uart_tx(bt),.image_count(3'd1),.media_ready(media_ready),
 .media_slot(2'd0),.media_error(4'd0),.media_source_width(locked==6 ? 16'h8500:16'd1280),.media_source_height(16'd720),
 .media_request(request),.media_target(target),.media_release(release_media),.media_cancel(cancel),.transmit_slot(transmit_slot),.start_toggle(start_t),
 .abort_toggle(abort_b),.settings_state(b_settings),.tx_done(tx_done),.tx_crc(32'hacbd1234),.busy(bbusy),.error(be));
reg screen_rx=1;
saixian_hmi_uart #(.TEXT_INPUT(1),.CLK_FREQ_HZ(806400)) screen(.clk(ac),.rst(rst),.uart_rx(screen_rx),.text_active(text_active || match_busy),.text_can_start(text_can_start),.text_byte_valid(text_byte_valid),.text_byte(text_byte),.text_timeout(text_timeout));
photo_serial_text_runtime_a #(.BOOT_TEXT(1),.RANK_INPUT(1)) serial_text(.boot_ready(map_complete),.rank_begin(rb),.rank_finish(rf),.rank_failed(re),.rank_index(ri),.rank_length(rl),.rank_time(rt),.clk(ac),.rst(rst),.byte_valid(text_byte_valid),.byte_data(text_byte),.can_start(text_can_start && !match_busy),.timeout(text_timeout),
 .reply_valid(text_reply),.reply_tag(text_reply_tag),.reply_position(text_reply_position),.reply_error(text_reply_error),
 .active(text_active),.request_valid(text_request),.tag(text_tag),.bank_length(text_bank_length),.character_index(text_character),.code(text_code));
photo_match_manager #(.HZ(806400),.DB_CYCLES(3),.HOLD_CYCLES(100),.SHARED_TIMEOUT(1)) match_mode(
 .clk(ac),.rst(rst),.frame_tick(frame),.entry_allowed(1'b1),.key_n(4'b1111),
 .byte_valid(text_byte_valid),.byte_data(text_byte),.serial_idle(text_can_start),.text_active(text_active),.serial_timeout(text_timeout),
 .active(match_active),.serial_busy(match_busy));
reg font_valid=0,font_finish=0;reg [7:0] font_data=0;integer pos=-1;reg [31:0] address;
wire map_valid;wire [31:0] map_sector;wire physical_req;wire [31:0] physical_sector;
reg scan_valid=0,scan_end=0;reg [7:0] scan_data=0;reg [31:0] scan_sector=0;
integer scan_count=0,scan_pos=0,scan_wait=0,gid=0,scan_phase=0;
function [7:0] record_byte;input integer groupno,at;begin
 if(at<8)case(at)0:record_byte="S";1:record_byte="X";2:record_byte="G";3:record_byte="L";4:record_byte="Y";5:record_byte="P";6:record_byte="0";7:record_byte="1";endcase
 else if(at==8)record_byte=groupno&255;
 else if(at==9)record_byte=groupno>>8;
 else if(at==10)record_byte=1;
 else if(at==11)record_byte=8;
 else if(at>=16 && at<272)record_byte=(groupno*256+at-16)&255;
 else record_byte=0;
end endfunction
photo_scan_font_index map(.clk(bc),.rst(rst),.valid(scan_valid),.data(scan_data),.sector_end(scan_end),.sector_address(scan_sector),.query(font_code[13:3]),.query_valid(map_valid),.query_sector(map_sector),.complete(map_complete));
photo_scan_glyph_b loader(.clk(bc),.rst(rst),.request(text_load),.code(font_code),.clear_line(text_clear),.map_valid(map_valid),.map_sector(map_sector),.scan_complete(map_complete),.ready(text_ready),.failed(text_failed),.consume(text_consume),.word(text_word),.read_sector(physical_req),.sector(physical_sector),.byte_valid(font_valid),.byte_data(font_data),.sector_end(font_finish));
always @(posedge bc)begin
 scan_valid<=0;scan_end<=0;
 if(rst)begin scan_wait<=0;scan_count<=0;scan_pos<=0;scan_phase<=0;end
 else if(scan_wait<1200)scan_wait<=scan_wait+1;
 else if(scan_count<1122)begin
  gid=scan_count==1121 ? 1024:(scan_count*37)%1121;
  scan_sector<=9000+gid*3;
  if(scan_pos<512)begin scan_valid<=1;scan_data<=record_byte(gid,scan_pos);scan_pos<=scan_pos+1;end
  else if(scan_pos==512)scan_pos<=513;
  else if(scan_pos==513)begin scan_end<=1;scan_pos<=514;end
  else begin scan_pos<=0;scan_count<=scan_count+1;end
 end
end
always @(posedge bc)begin
 font_valid<=0;font_finish<=0;
 if(physical_req)begin
  if((physical_sector-9000)%3!=0 || physical_sector<9000 || physical_sector>9000+1120*3)$fatal(1,"bad indexed LBA %0d",physical_sector);
  address<=physical_sector;pos<=0;
 end else if(pos>=0 && pos<512)begin font_valid<=1;font_data<=record_byte((address-9000)/3,pos);pos<=pos+1;end
 else if(pos==512)begin font_finish<=1;pos<=-1;end
end
wire [4:0] title_length,ticker_length;wire [15:0] font_bits;
saixian_font_rom #(.SERIAL_TEXT(1),.TITLE_SD(1),.INDEPENDENT_TEXT(1)) font(.clk(ac),.rst(rst),.frame_tick(frame),.word_valid(a.title_word_valid),.word_index(a.title_word_index),.word_data(a.title_word_data),.word_length(a.title_word_length),.title_length(title_length),.ticker_length(ticker_length),.glyph_id(7'd96),.row(4'd0),.bits(font_bits));
task byte_send;input [7:0] v;integer j;begin
 @(negedge ac);screen_rx=0;repeat(7)@(negedge ac);
 for(j=0;j<8;j=j+1)begin screen_rx=v[j];repeat(7)@(negedge ac);end
 screen_rx=1;repeat(7)@(negedge ac);
end endtask
task start_line;input integer bank;begin byte_send("@");byte_send("0"+bank);byte_send(":");end endtask
task end_line;begin byte_send(13);byte_send(10);wait(text_request);wait(!text_request);repeat(30)@(negedge ac);end endtask
integer n;reg [7:0] expected;
task check_rows;input integer bank,nchars;input [13:0] first,second;integer c,r,code;reg [15:0] wanted;begin
 for(c=0;c<nchars;c=c+1)for(r=0;r<16;r=r+1)begin
 code=c==0 ? first:second;wanted={8'((code*32+r*2)&255),8'((code*32+r*2+1)&255)};
 if(font.u_font_bram.memory[1536+bank*256+c*16+r]!==wanted)$fatal(1,"glyph mismatch bank=%0d char=%0d row=%0d got=%h expected=%h",bank,c,r,font.u_font_bram.memory[1536+bank*256+c*16+r],wanted);
 end
end endtask
task toggle_award;begin @(negedge ac);award_toggle=1;@(negedge ac);award_toggle=0;end endtask
task check_one;input integer bank,slot,code;integer r;reg [15:0] wanted;begin
 for(r=0;r<16;r=r+1)begin
 wanted={8'((code*32+r*2)&255),8'((code*32+r*2+1)&255)};
 if(font.u_font_bram.memory[1536+bank*256+slot*16+r]!==wanted)$fatal(1,"high index glyph mismatch %0d",code);
 end
end endtask
wire[31:0] rank_pixels;
saixian_sprint_runtime rank_view(.clk(ac),.rst(rst),.header(1'b0),.header_addr(10'd0),.row_id(3'd0),.x(9'd112),.font_y(4'd0),.bits(rank_pixels),
 .rank_begin(rb),.rank_finish(rf),.rank_failed(re),.rank_index(ri),.rank_length(rl),.rank_time(rt),.word_valid(rwv),.word_index(rwi),.word_data(rwd));
function integer startup_code;input integer n;begin case(n)
 0:startup_code=49;1,2:startup_code=48;3:startup_code=3378;4:startup_code=2593;5:startup_code=4840;
 6:startup_code=3061;7:startup_code=2036;8:startup_code=4964;9:startup_code=2116;default:startup_code=2636;endcase end endfunction
task check_startup;integer i;begin
 wait(title_length==4 && ticker_length==7);wait(!text_request);repeat(30)@(negedge ac);
 for(i=0;i<11;i=i+1)check_one(i<4 ? 0:1,i<4 ? i:i-4,startup_code(i));
end endtask
task rank_prefix;input[7:0] nr;begin byte_send("@");byte_send("R");byte_send(nr);byte_send(":");end endtask
task rank_timecode;begin byte_send(",");byte_send("1");byte_send("2");byte_send(".");byte_send("3");byte_send("4");end endtask
task rank_rows;input integer bank,nchars;input[13:0] first,second;integer c,rr,cc;reg[15:0] ww;begin
 for(c=0;c<nchars;c=c+1)for(rr=0;rr<16;rr=rr+1)begin
  cc=c==0 ? first:second;ww={8'((cc*32+rr*2)&255),8'((cc*32+rr*2+1)&255)};
  if(rank_view.font_memory[bank*128+c*16+rr]!==ww)$fatal(1,"real A/B rank SD glyph route mismatch bank=%0d glyph=%0d row=%0d",bank,c,rr);
 end
 if(!rank_view.custom[bank] || rank_view.lengths[bank]!=nchars || rank_view.time_memory[bank]!=16'h1234)$fatal(1,"real SD rank metadata not committed");
end endtask

initial begin
 repeat(20)@(negedge ac);rst=0;
 wait(a.have_current && current==0 && !abusy && !bbusy);toggle_award;
 wait(current==6 && !abusy && !bbusy);if(!width[15] || !immediate || fluid)$fatal(1,"normal-mode award entry");
 // Refresh picture settings while retaining the fixed RGB565 award payload.
 settings[14]=!settings[14];
 wait(updating);wait(transfers>=3 && !updating && !abusy && !bbusy);
 wait(a.have_current && current==6 && !updating && !abusy && !bbusy);
 if(!width[15] || fluid || !receive_award)$fatal(1,"refreshed award lost 565 metadata");
 toggle_award;wait(current==0 && !abusy && !bbusy);
 if(width!=1280)$fatal(1,"photo not restored after award");
 toggle_award;wait(current==6 && !abusy && !bbusy);
 toggle_award;wait(current==0 && !abusy && !bbusy);
 if(ae || be || award_requests<2 || begins<2 || transfers!=4)$fatal(1,"incomplete award control coverage %0d/%0d/%0d errors=%0d/%0d",award_requests,begins,transfers,ae,be);
 wait(scan_count==1122);repeat(10)@(negedge ac);if(!map_complete || map.groups_found!=1121)$fatal(1,"index missing or duplicate group accounting");
 check_startup;
 byte_send("!");byte_send("M");byte_send(":");byte_send("1");byte_send(13);byte_send(10);wait(match_active);
 start_line(0);byte_send("U");byte_send("@");end_line;
 wait(title_length==2);check_rows(0,2,85,64);
 start_line(1);byte_send(8'hb0);byte_send(8'ha1);byte_send("1");end_line;
 wait(ticker_length==2);check_rows(1,2,1538,49);
 if(title_length!=2)$fatal(1,"ticker update altered title");
 start_line(0);end_line;wait(title_length==0);
 if(ticker_length!=2)$fatal(1,"clear title altered ticker");
 start_line(1);byte_send(8'hf6);byte_send(8'hea);byte_send(8'hf6);byte_send(8'heb);byte_send(8'hfe);byte_send(8'hfe);end_line;
 wait(ticker_length==3);check_one(1,0,8191);check_one(1,1,8192);check_one(1,2,8963);

 // An interrupted line recovers, preserving the last committed content.
 start_line(0);byte_send("X");repeat(400)@(negedge ac);
 if(text_active || text_request || title_length!=0)$fatal(1,"partial line did not recover");
 start_line(0);for(n=0;n<17;n=n+1)byte_send("A");byte_send(13);repeat(80)@(negedge ac);
 if(text_request || title_length!=0)$fatal(1,"overflow was published");
 start_line(0);for(n=0;n<16;n=n+1)byte_send("A");end_line;wait(title_length==16);check_rows(0,16,65,65);
 // Binary HMI frame after text, including the ordinary value 0x40.
 byte_send(8'h55);byte_send(8'h10);byte_send(8'h40);byte_send(0);byte_send(255);byte_send(255);byte_send(255);
 repeat(40)@(negedge ac);if(screen.setting_value!=64)$fatal(1,"text demux broke binary HMI value");
 byte_send("!");byte_send("M");byte_send(":");byte_send("0");byte_send(13);byte_send(10);wait(!match_active);
 rank_prefix("1");byte_send(8'hb0);byte_send(8'ha1);byte_send("Z");rank_timecode;end_line;
 rank_rows(0,2,1538,90);
 rank_prefix("8");for(n=0;n<8;n=n+1)byte_send("X");rank_timecode;end_line;
 rank_rows(7,8,88,88);
 if(title_length!=16 || ticker_length!=3)$fatal(1,"rank SD transfer corrupted UI text bank");
 // Reset must reload defaults even though the physical font RAM retains edits.
 rst=1;repeat(20)@(negedge ac);rst=0;check_startup;
 $display("PASS real screen UART -> A controller -> B indexed SD glyph loader -> rank RAM for first/last rows, Chinese/ASCII names, exact times; automatic default title/ticker on cold and soft reset; captions and old media/match controls preserved");$finish;
end
initial begin #80000000;$fatal(1,"runtime rank transport timeout");end
endmodule
