module top_text_demo(input clk,hmi_uart_rx,output hmi_uart_tx,
 output sd_ncs,sd_dclk,sd_mosi,input sd_miso,
 output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,output HDMI_DDC_SCL,inout HDMI_DDC_SDA);
wire pixel,serial,locked,rst;video_pll u_video_pll(clk,1'b0,pixel,serial,locked);
dual_still_reset_sync reset_video(pixel,!locked,rst);
wire received,txbusy,reply;wire[7:0] data,response;
wire txsend;wire[7:0] txdata;wire[15:0] rx_count;wire[7:0] rx_last;wire font_ready,font_fault;
demo_uart uart(pixel,rst,hmi_uart_rx,txsend,txdata,hmi_uart_tx,txbusy,received,data);
wire init,readreq,readvalid,readend;wire[2:0] init_stage;wire[31:0] address;wire[7:0] sdbyte;
wire physical_read,physical_valid,physical_end;wire[31:0] physical_sector;wire[7:0] physical_byte;wire[3:0] fs_error;
demo_fat_font filesystem(.clk(pixel),.rst(rst),.card_ready(init && init_stage==4),.request(readreq),.address(address),.valid(readvalid),.data(sdbyte),.finish(readend),.error(fs_error),
 .read_sector(physical_read),.sector(physical_sector),.byte_valid(physical_valid),.byte_data(physical_byte),.sector_end(physical_end));
sd_card_top sd(.clk(pixel),.rst(rst),.SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso),
 .sd_init_done(init),.init_stage(init_stage),.sd_sec_read(physical_read),.sd_sec_read_addr(physical_sector),.sd_sec_read_data(physical_byte),.sd_sec_read_data_valid(physical_valid),.sd_sec_read_end(physical_end),
 .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
wire[11:0] x;wire[10:0] y;wire frame,de,hs,vs;wire[23:0] rgb;wire[9:0] r,g,b;
demo_text text(.clk(pixel),.rst(rst),.byte_valid(received),.byte_data(data),.initialized(init),.sd_read(readreq),.sd_address(address),.sd_valid(readvalid),.sd_data(sdbyte),.sd_end(readend),
 .frame_tick(frame),.x(x),.y(y),.rgb(rgb),.reply(reply),.reply_data(response),.font_ready(font_ready),.fault(font_fault),.sd_init_stage(init_stage),.rx_count(rx_count),.rx_last(rx_last),.fs_error(fs_error));
demo_uart_test heartbeat(pixel,rst,txbusy,reply,response,rx_count,rx_last,font_ready,font_fault,init_stage,txsend,txdata);
hdmi_minimal_tx #(.EXTERNAL_VIDEO(1),.VIDEO_DELAY(2)) video(pixel,rst,rgb,b,g,r,hs,vs,de,frame,x,y);
hdmi_phy_wrapper phy(pixel,serial,rst,b,g,r,10'b1111100000,HDMI_D0_P,HDMI_D1_P,HDMI_D2_P,HDMI_CLK_P);
assign HDMI_DDC_SCL=1'b1;assign HDMI_DDC_SDA=1'bz;
endmodule
