`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,photo_scan=0,music_scan=0,font_available=1,font_ack=0,display=1;
reg[4:0] title_length=0,ticker_length=0;reg[2:0] photos=3,music=3;
always #5 clk=~clk;
top_photo_a d(.clk(clk),.key(4'hf),.hmi_uart_rx(1'b1));
initial begin
 force d.pixel_clk=clk;force d.rst_pixel=rst;force d.blank_start=1'b1;force d.init_done=1'b1;
 force d.award_scan_complete=photo_scan;force d.music_catalog_complete=music_scan;force d.music_buffer_ready=1'b1;
 force d.font_available=font_available;force d.font_transfer_complete=font_ack;force d.title_length=title_length;force d.ticker_length=ticker_length;
 force d.count=photos;force d.music_count=music;force d.display_valid=display;force d.started=display;
 force d.award_available=1'b0;force d.relief_available=1'b0;force d.carousel_mode=1'b1;
 force d.settings_mode=1'b0;force d.award_active=1'b0;force d.award_loading=1'b0;force d.result_busy=1'b0;force d.auto_enable=1'b1;
end
initial begin
 repeat(5)@(negedge clk);rst=0;repeat(150)@(negedge clk);
 if(d.boot_active!==1 || d.auto_advance.enable!==0)$fatal(1,"boot bypassed scan or autoplay ran while loading");
 photo_scan=1;music_scan=1;repeat(150)@(negedge clk);
 if(d.boot_active!==1)$fatal(1,"top did not wait for A font ACK");
 font_ack=1;title_length=4;repeat(150)@(negedge clk);
 if(d.boot_active!==1)$fatal(1,"top released with second font bank incomplete");
 ticker_length=6;repeat(150)@(negedge clk);
 if(d.boot_active!==0 || d.auto_advance.enable!==1)$fatal(1,"top failed to release complete startup");
 rst=1;repeat(5)@(negedge clk);photos=0;music=0;display=0;font_available=0;font_ack=0;title_length=0;ticker_length=0;rst=0;
 repeat(150)@(negedge clk);
 if(d.boot_active!==0 || d.feature_rgb!==24'd0)$fatal(1,"empty resources did not produce blank playback");
 $display("PASS actual A top boot: full photo/music scan, A font ACK plus both published banks, no autoplay during loading, empty-resource black output");$finish;
end
endmodule
