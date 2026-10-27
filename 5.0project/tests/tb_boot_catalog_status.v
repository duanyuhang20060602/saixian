`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,scan=0,font_present=0;always #5 clk=~clk;
wire atx,btx,valid,available,complete,scanned;wire[7:0] wi,addr;wire[31:0] wd;wire[4:0] wl,tl,bl;
wire[2:0] count;wire media_request;integer writes=0;reg[4:0] phase=0;
always @(posedge clk)if(rst)begin writes<=0;phase<=0;end else begin phase<=phase+1'b1;if(valid)writes<=writes+1;end
photo_control_b #(.CLK_HZ(921600),.TIMER_SCALE(64),.TITLE_SD(1),.INDEPENDENT_TEXT(1),.BOOT_STATUS(1),.AWARD_CONTROL(1)) b(
 .clk(clk),.rst(rst),.uart_rx(atx),.uart_tx(btx),.title_ready(font_present),.title_length(5'd4),.title_data(32'h13579bdf),.title_address(addr),
 .image_count(3'd0),.award_available(1'b0),.relief_available(1'b0),.award_scan_complete(scan),
 .media_ready(1'b0),.media_slot(2'd0),.media_error(4'd0),.media_source_width(16'd1280),.media_source_height(16'd720),.tx_done(1'b0),.tx_crc(32'd0),.media_request(media_request));
photo_cached_control_a #(.CLK_HZ(921600),.TIMER_SCALE(64),.TITLE_SD(1),.INDEPENDENT_TEXT(1),.BOOT_STATUS(1),.AWARD_CONTROL(1)) a(
 .clk(clk),.rst(rst),.uart_rx(btx),.uart_tx(atx),.font_available(available),.font_transfer_complete(complete),.award_scan_complete(scanned),.image_count(count),
 .title_word_valid(valid),.title_word_index(wi),.title_word_data(wd),.title_word_length(wl),
 .settings_mode(1'b0),.settings_state(19'd0),.award_toggle(1'b0),.relief_toggle(1'b0),.previous(1'b0),.next(1'b0),
 .active_slot(2'd0),.new_slot(2'd1),.transition_active(1'b0),.commit_toggle(1'b0),.rx_armed(1'b0),.rx_done(1'b0),.rx_fault(1'b0),.rx_crc(32'd0),.thumbnail_read_busy(1'b0),.thumbnail_read_slot(2'd0));
saixian_font_rom #(.TITLE_SD(1),.INDEPENDENT_TEXT(1)) font(.clk(clk),.rst(rst),.frame_tick(phase==0),.word_valid(valid),.word_index(wi),.word_data(wd),.word_length(wl),
 .title_length(tl),.ticker_length(bl),.glyph_id(7'd96),.row(4'd0),.bits());
initial begin
 repeat(5)@(negedge clk);rst=0;repeat(35000)@(negedge clk);
 if(scanned || available || complete || writes)$fatal(1,"unscanned empty card declared ready");
 scan=1;wait(scanned);repeat(10)@(negedge clk);
 if(count!=0 || available || complete || a.nav_pending || media_request)$fatal(1,"empty catalog did not settle cleanly");
 rst=1;repeat(5)@(negedge clk);scan=0;font_present=1;rst=0;repeat(35000)@(negedge clk);
 if(scanned || complete)$fatal(1,"font status bypassed full scan");
 scan=1;wait(available);if(complete)$fatal(1,"font transfer acknowledged before data");
 wait(complete);repeat(50)@(negedge clk);
 if(!scanned || writes!=256 || tl!=4 || bl!=4 || a.nav_pending || media_request)$fatal(1,"font completion/catalog handshake mismatch writes=%0d",writes);
 $display("PASS real duplex UART boot catalog: absent photos/music/font, delayed scan, validated font presence, all 256 words, final ACK and both A font banks");$finish;
end
initial begin #40000000;$fatal(1,"boot catalog timeout");end
endmodule
