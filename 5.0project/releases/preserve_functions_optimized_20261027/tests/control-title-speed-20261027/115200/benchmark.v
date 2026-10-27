`timescale 1ns/1ps
module tb;
parameter TEST_BAUD=115200;time title_start,title_end;
reg render=0;wire[10:0] font_addr;
reg clk=0,rst=1,drop_ack=0,frame_tick=0;
reg config_valid=0,config_end=0;reg [7:0] config_byte=0,config_records[0:4095];
wire title_ready;wire [4:0] stored_length;
always #5 clk=~clk;
wire a_tx,b_tx,word_valid;wire [7:0] word_index,title_address;
wire [31:0] word_data;wire [4:0] word_length,published_length,published_ticker;
reg [6:0] glyph=0;reg [3:0] row=0;wire [15:0] bits;
wire [31:0] title_data;
photo_sd_title_store #(.INDEPENDENT_TEXT(1)) store(.clk(clk),.rst(rst),.valid(config_valid),.data(config_byte),.sector_end(config_end),
 .ready(title_ready),.length(stored_length),.address(title_address),.word(title_data));
photo_control_b #(.BOOT_STATUS(1),.AWARD_CONTROL(1),.CLK_HZ(9216000),.CONTROL_BAUD(TEST_BAUD),.TIMER_SCALE(64),.TITLE_SD(1),.INDEPENDENT_TEXT(1)) b(
 .clk(clk),.rst(rst),.uart_rx(drop_ack ? 1'b1:a_tx),.uart_tx(b_tx),
 .title_ready(title_ready),.title_length(stored_length),.title_address(title_address),.title_data(title_data),
 .image_count(3'd1),.award_available(1'b0),.award_scan_complete(1'b1),.relief_available(1'b0),
 .media_ready(1'b0),.media_slot(2'd0),.media_error(4'd0),.media_source_width(16'd1280),.media_source_height(16'd720),.tx_done(1'b0),.tx_crc(32'd0));
photo_cached_control_a #(.BOOT_STATUS(1),.AWARD_CONTROL(1),.CLK_HZ(9216000),.CONTROL_BAUD(TEST_BAUD),.TIMER_SCALE(64),.TITLE_SD(1),.INDEPENDENT_TEXT(1)) a(
 .clk(clk),.rst(rst),.uart_rx(b_tx),.uart_tx(a_tx),
 .title_word_valid(word_valid),.title_word_index(word_index),.title_word_data(word_data),.title_word_length(word_length),
 .settings_mode(1'b0),.settings_state(19'd0),.award_toggle(1'b0),.relief_toggle(1'b0),.previous(1'b0),.next(1'b0),
 .active_slot(2'd0),.new_slot(2'd1),.transition_active(1'b0),.commit_toggle(1'b0),
 .rx_armed(1'b0),.rx_done(1'b0),.rx_fault(1'b0),.rx_crc(32'd0),.thumbnail_read_busy(1'b0),.thumbnail_read_slot(2'd0));
saixian_font_rom #(.TITLE_SD(1),.INDEPENDENT_TEXT(1)) font(.clk(clk),.rst(rst),.frame_tick(frame_tick),
 .word_valid(word_valid),.word_index(word_index),.word_data(word_data),.word_length(word_length),
 .ticker_length(published_ticker),.title_length(published_length),.glyph_id(render ? font_addr[10:4]:glyph),.row(render ? font_addr[3:0]:row),.bits(bits));
reg[9:0] sx=0;reg[8:0] sy=0;
wire[23:0] rgb;integer fd,px,py;
integer writes=0,first_retries=0,i;reg [15:0] expected_row;
always @(posedge clk)if(word_valid)begin
 if(word_index!==writes[7:0])$fatal(1,"font row duplicated or skipped");writes=writes+1;if(writes%32==0)$display("progress: %0d font words",writes);
end
always @(posedge clk)if(a.got && a.kind==33 && a.incoming[119:112]==128)first_retries=first_retries+1;
initial begin
 $readmemh("title_records.hex",config_records);
 repeat(5)@(negedge clk);rst=0;
 a.state_flags=4;a.session=1;a.image_count=1;b.state_flags=11'd4;b.session=1;b.announced_count=1;
 force a.plan_needed=0;
 repeat(10000)@(negedge clk);
 if(writes || published_length)$fatal(1,"missing config did not preserve fallback");
 title_start=$time;
 for(i=0;i<2048;i=i+1)begin
  @(negedge clk);config_valid=1;config_byte=config_records[i];
  if(i%512==511)begin @(negedge clk);config_valid=0;config_end=1;@(negedge clk);config_end=0;end
 end
 wait(b.title_complete);title_end=$time;repeat(8)@(negedge clk);
 if(writes!=256 || first_retries<0 || published_length!=0)$fatal(1,"ACK retry or atomic publication failed");
 frame_tick=1;@(negedge clk);frame_tick=0;repeat(2)@(negedge clk);
 if(published_length!=4 || published_ticker!=6)$fatal(1,"complete title did not publish in blanking");
 for(i=0;i<512;i=i+1)begin
  glyph=96+i/16;row=i%16;repeat(2)@(negedge clk);
  expected_row={config_records[(i/128)*512+20+(i%128)*2],config_records[(i/128)*512+21+(i%128)*2]};
  if(bits!==expected_row)$fatal(1,"font RAM mismatch at %0d: %h",i,bits);
 end

 $display("TITLE_CYCLES %0d",(title_end-title_start)/10);
 $display("PASS complete 256-word transfer, both native font banks and atomic publication");$finish;
end
initial begin #500000000;$fatal(1,"timeout");end
endmodule
